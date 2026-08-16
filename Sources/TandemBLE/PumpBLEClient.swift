import Foundation
@preconcurrency import CoreBluetooth
import TandemMessages
import os

/// D-06/D-07: fixed, documented literal subsystem/category — NOT `Bundle.main.bundleIdentifier`.
/// `LocalConfig.xcconfig` (faBolus repo) overrides `APP_BUNDLE_ID` per developer (gitignored), so a
/// bundle-derived subsystem would silently stop matching the off-device `log show` predicate on another
/// machine's build. This is the ONLY path to the true `bluetoothd`/HCI disconnect reason CoreBluetooth's
/// own `CBError` surface cannot reach (see D-03's CBError capture, app-side) — pull with:
///   `log collect --device-udid <UDID> --last 10m --output ~/fabolus.logarchive`
///   `log show ~/fabolus.logarchive --predicate 'subsystem == "com.fabolus.app" AND category == "ble"' --info --debug`
private let bleLog = Logger(subsystem: "com.fabolus.app", category: "ble")

/// Events emitted by `PumpBLEClient`, delivered on the main actor.
@MainActor
public protocol PumpBLEClientDelegate: AnyObject {
    func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State)
    /// A pump was discovered during scanning.
    func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int)
    /// The pump is connected and all characteristics are discovered + subscribed.
    func pumpClientDidBecomeReady(_ client: PumpBLEClient)
    /// A fully-reassembled inbound message frame arrived on `characteristic`. `frame` is the
    /// concatenated packet payloads (opcode/txId/len/cargo/…/crc), ready for parsing.
    func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic)
    func pumpClient(_ client: PumpBLEClient, didError error: Error)
    /// D-05: fired from `scheduleNextReconnectAttempt()` every time the reconnect ladder schedules a
    /// throttled attempt — including a silently-failed attempt that never reaches a `didChange`/`didError`
    /// state edge. `attempt` is the CONSECUTIVE-drop counter (`reconnectAttempts`, not reset on every
    /// drop — see its doc); `delay` is the jittered backoff actually armed for this attempt. This is the
    /// only way the count/backoff — which otherwise lives only in this class's private state — leaves the
    /// kit, so a host can record it for diagnostics without the kit taking on any logging concern itself.
    func pumpClient(_ client: PumpBLEClient, willRetryReconnect attempt: Int, after delay: TimeInterval)
}

/// Default no-op for `willRetryReconnect` — every conformer that doesn't care about the reconnect
/// ladder's internals (today: `WatchPumpClient` and the PumpX2Kit test/bench-harness conformers) keeps
/// compiling unchanged; only a conformer that wants the signal overrides it.
@MainActor
public extension PumpBLEClientDelegate {
    func pumpClient(_ client: PumpBLEClient, willRetryReconnect attempt: Int, after delay: TimeInterval) {}
}

/// B3(b) TEST SEAM — the minimal `CBCentralManager` surface `PumpBLEClient` actually uses. `CBCentralManager`
/// satisfies it unchanged (the empty conformance below), so injecting the real manager is behavior-preserving
/// by construction — if this compiles, the production path is untouched. A unit test injects a fake to
/// branch-test the connection lifecycle (scan timeout, retrieve-vs-scan) without CoreBluetooth/hardware,
/// which a macOS test host can't run (TCC-aborted at scan — see the class note).
protocol PumpCentral: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral]
    func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral]
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}
extension CBCentralManager: PumpCentral {}

/// Core Bluetooth central for the Tandem pump. Platform-agnostic (iOS + watchOS): imports
/// CoreBluetooth only. Mirrors the connection flow of upstream `TandemBluetoothHandler`:
/// scan for the pump service → connect → discover characteristics → request MTU → enable
/// notifications → write packetized requests / reassemble notified responses.
///
/// Hardware-validated on real pumps (see `PINNED.md` for the log): 6-digit EC-JPAKE pairing +
/// read-only monitor + a signed 0.10 u bolus (t:slim X2, Control-IQ+ 7.10.2, 2026-07-18), and legacy
/// V1 (16-char) pairing + read sweep + signed `BolusPermission` acceptance (spare t:slim X2, API 2.5,
/// 2026-08-07). This BLE path can only be exercised on hardware through the `TandemBenchHarness`
/// executable, not `swift test` — a macOS test host lacks `NSBluetoothAlwaysUsageDescription` and is
/// TCC-aborted at scan. Cartridge-dependent items (saline delivery on the legacy pump, mid-delivery
/// cancel) remain bench-gated (see `docs/BENCH-SESSION-PLAN.md`).
@MainActor
public final class PumpBLEClient: NSObject {
    public enum State: Equatable, Sendable {
        case poweredOff, unauthorized, unsupported, resetting, unknown
        case idle, scanning, connecting, discovering, ready, disconnected
        /// The reconnect backoff ladder was exhausted (`maxReconnectAttempts`) without ever reaching
        /// `.ready` — the peer kept accepting-then-dropping the link (classic during pairing: the
        /// official t:connect app still holds the pump, or the pump's pairing/GATT window closed).
        /// Automatic retry is suspended so a flapping peer can't spin the app forever; the caller should
        /// surface a "pairing is looping — cancel on the pump / retry" state. A fresh user-initiated
        /// `connect(_:)` / `connectKnownPeripheral(identifier:)` clears this and restarts the ladder.
        case reconnectExhausted
    }

    public enum ClientError: Error, Equatable {
        case notReady
        case unknownCharacteristic(Characteristic)
        case writeFailed(Characteristic)
        /// A message was refused by the current `writePolicy`.
        case writeBlocked(policy: WritePolicy, opcode: UInt8)
        /// The reconnect ladder hit `maxReconnectAttempts` without reaching `.ready` — surfaced alongside
        /// `State.reconnectExhausted` so a delegate that only observes `didError` still sees it.
        case reconnectLoopDetected
    }

    /// Graded write safety. Governs which outgoing messages `send()` permits — a defense-in-
    /// depth interlock so delivery can only happen after a deliberate, explicit opt-in. Each policy
    /// authorizes up to a maximum `OperationRisk` (audit P-01), so a caller that only needs a benign
    /// op (dismiss an alert, find-my-pump) no longer has to open the same gate as therapy-config.
    public enum WritePolicy: Sendable, Equatable {
        /// Reads + pairing only. Blocks anything on CONTROL, any signed message, or anything
        /// insulin-affecting. The safe default.
        case readOnly
        /// Allow only **benign** signed control (dismiss notification, find-my-pump, non-calibration
        /// carb/BG metadata): signed proof works, but therapy-significant config, destructive commands,
        /// and delivery are all still blocked (audit P-01).
        case allowBenignControl
        /// Allow signed CONTROL up to therapy-significant **configuration** (limits, Control-IQ, time,
        /// CGM session/alerts/calibration, reminders, IDP/profile edits), but HARD-BLOCK **destructive**
        /// commands (factory reset / shelf / disconnect-pump) *and* insulin delivery. Used to validate
        /// signing on hardware without dispensing. (PX-03: no longer authorizes destructive ops.)
        case allowNonDelivery
        /// Allow **destructive** non-dispensing commands (factory reset, shelf mode, disconnect-pump) in
        /// addition to settings — HARD-BLOCK insulin delivery. Intended to be granted **explicitly and
        /// briefly** around a single destructive action, never left standing (PX-03).
        case allowDestructive
        /// Allow everything, including insulin delivery. Experimental.
        case allowDelivery

        /// The highest `OperationRisk` this policy authorizes.
        var maxRisk: OperationRisk {
            switch self {
            case .readOnly:           return .read
            case .allowBenignControl: return .benign
            case .allowNonDelivery:   return .settings      // PX-03: settings-only (was .destructive)
            case .allowDestructive:   return .destructive
            case .allowDelivery:      return .delivery
            }
        }
        func permits(_ risk: OperationRisk) -> Bool { risk <= maxRisk }
    }

    /// Current write policy. Defaults to `.readOnly`; callers must opt in explicitly. Reset to
    /// `.readOnly` fail-closed by the library on every disconnect/drop/restore/error (PX-04) — a caller
    /// must not rely on an elevated policy surviving a transaction or connection change.
    ///
    /// Prefer the scoped `withWritePolicy` over assigning this directly: it guarantees the elevation is
    /// short-lived and always restored to `.readOnly`, so a thrown/cancelled operation can't leave an
    /// elevated policy standing (PX-03/04).
    public var writePolicy: WritePolicy = .readOnly

    /// Run `body` with the write policy elevated to `policy` for exactly this one operation, then ALWAYS
    /// restore `.readOnly` — on success, throw, or task cancellation (PX-03/04). This is the sanctioned way
    /// to authorize a signed op: it prevents an arbitrary long-lived elevation (especially `.allowDestructive`
    /// / `.allowDelivery`) from leaking past the single operation it was granted for. Callers still run
    /// under their own serialization; the transport additionally fails-closed to `.readOnly` on any
    /// disconnect/error, so even a crash mid-body cannot carry the elevation into the next connection.
    /// `body` is `@MainActor` so its (possibly non-Sendable) result stays on this actor and isn't sent
    /// across an actor boundary — Swift 6 strict concurrency (the CI toolchain) rejects the nonisolated
    /// form. Same idiom as `TandemBackend.withPumpTx`.
    @discardableResult
    public func withWritePolicy<T>(_ policy: WritePolicy, _ body: @MainActor () async throws -> T) async rethrows -> T {
        writePolicy = policy
        defer { writePolicy = .readOnly }
        return try await body()
    }

    /// The pump product family, for the D2 (Addendum G) txId-correlation allowlist. The KIT owns the
    /// allowlist; the caller supplies only the identified family (it owns the BLE-name → model
    /// classification), so the kit never guesses a model.
    public enum PumpFamily: Sendable, Equatable {
        /// t:slim X2 — hardware-confirmed to echo the request txId in an inbound frame's `frame[1]`.
        case tslim
        /// Mobi — txId-echo unconfirmed; stays on the FIFO reference path.
        case mobi
        /// Not yet identified — fail-closed to FIFO.
        case unknown
    }

    /// Apply the D2 txId-correlation allowlist for the connected pump (Addendum G, `experimental` only).
    ///
    /// The allowlist is **all t:slim, and ONLY t:slim**: a t:slim enables `.txIdMatch`; Mobi and any
    /// unidentified pump stay on `.opcodeFIFO` (the `main` reference path). The kit enforces that mapping
    /// here, so a caller cannot accidentally enable txId correlation for a Mobi. The mode is reset to
    /// `.opcodeFIFO` on every disconnect/error/restore by `failClosed`, so this must be called AFTER each
    /// (re)identification. Correlation mode never relaxes delivery-class serialization (a bolus is never
    /// pipelined), so this only ever affects how concurrent READ replies are disambiguated.
    public func setPumpFamily(_ family: PumpFamily) {
        transactions.correlationMode = (family == .tslim) ? .txIdMatch : .opcodeFIFO
    }

    /// Pure authorization decision (PX-02), separated from readiness/transport so it is deterministically
    /// testable and cannot be masked by `.notReady`. Returns the exact `.writeBlocked` error a policy
    /// would raise for `message`, or `nil` if the policy permits it. `send()` consults this first.
    public func authorizationError(for message: Message) -> ClientError? {
        writePolicy.permits(message.operationRisk)
            ? nil
            : .writeBlocked(policy: writePolicy, opcode: message.opCode)
    }

    /// Owns in-flight request/response correlation, deadlines, and fail-closed completion (PX-08).
    /// Callers that need an awaited response use `sendAwaitingResponse`; unsolicited frames (streams,
    /// proactive status) are not consumed here and still reach the delegate.
    public let transactions = PumpTransactionCoordinator()

    public weak var delegate: PumpBLEClientDelegate?
    public private(set) var state: State = .unknown {
        didSet {
            if state != oldValue {
                // D-08: a fixed enum case name is never PHI — .public is safe and necessary for this to
                // survive to a pulled logarchive (redaction is emit-time and unrecoverable — Pitfall 2).
                bleLog.log("BLE state → \(String(describing: self.state), privacy: .public)")
                notify { $0.pumpClient(self, didChange: self.state) }
            }
        }
    }

    private var central: PumpCentral!
    private var peripheral: CBPeripheral?
    /// Discovered pump characteristics keyed by our `Characteristic` enum.
    private var characteristics: [Characteristic: CBCharacteristic] = [:]
    /// PX-08 subscription-ready barrier: messaging notification characteristics we've requested
    /// `setNotifyValue(true)` on, and the subset the pump has CONFIRMED via `didUpdateNotificationState`.
    /// `.ready` is withheld until every requested one is confirmed, so a delivery can't be written before
    /// its response channel is actually subscribed (which would silently drop the reply → false timeout).
    private var requestedNotify: Set<Characteristic> = []
    private var confirmedNotifying: Set<Characteristic> = []
    /// Per-characteristic inbound reassembly buffers.
    private var reassembly: [Characteristic: PacketReassembler] = [:]
    private let txIds = TransactionId()

    /// Optional CoreBluetooth state-restoration identifier. When set, iOS preserves the central
    /// manager across app termination and relaunches the app on pump BLE events, calling
    /// `willRestoreState`. Requires the app's `bluetooth-central` background mode.
    public init(restoreIdentifier: String? = nil) {
        super.init()
        var options: [String: Any] = [:]
        if let restoreIdentifier {
            options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
        }
        self.central = CBCentralManager(delegate: self, queue: .main, options: options)
    }

    /// B3(b) TEST SEAM ONLY — inject a fake `PumpCentral` so the connection lifecycle (scan timeout,
    /// retrieve-vs-scan) can be branch-tested without CoreBluetooth/hardware. Never used in production
    /// (the real path is `init(restoreIdentifier:)`, which builds a real `CBCentralManager`).
    init(central: PumpCentral) {
        super.init()
        self.central = central
    }

    // MARK: - Public API

    public func startScan() {
        wasScanning = true
        guard central.state == .poweredOn else { state = mapCentralState(central.state); return }
        state = .scanning
        central.scanForPeripherals(withServices: [CBUUID(nsuuid: ServiceUUID.pumpService)], options: nil)
        armScanTimeout()   // §5.2.4 (B3b): recover a KNOWN-pump scan that never discovers, without teardown
    }

    public func stopScan() { wasScanning = false; cancelScanTimeout(); central.stopScan() }

    public func connect(_ peripheral: CBPeripheral) {
        stopScan()
        cancelReconnectWatchdog()
        intentionalDisconnect = false
        self.peripheral = peripheral
        reconnectTargetId = peripheral.identifier
        peripheral.delegate = self
        state = .connecting
        // Keep the connection request alive across states; iOS completes it when in range.
        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
    }

    /// Cold-launch fast path: re-adopt a previously-known pump by its persisted CoreBluetooth identifier
    /// via `retrievePeripherals`, connecting directly instead of running the slow scan (v3 group C — a
    /// cold launch could otherwise only scan). Falls back to a scan if the id can't be resolved yet
    /// (`didDiscover` then auto-connects when the target reappears, since `reconnectTargetId` is set); if
    /// Bluetooth isn't powered on yet, the retrieve is deferred until `centralManagerDidUpdateState`.
    /// Additive — the existing scan/connect/restore paths are unchanged.
    public func connectKnownPeripheral(identifier id: UUID) {
        intentionalDisconnect = false
        cancelReconnectWatchdog()   // genuinely new pairing/reconnect intent — restart the ladder at 0
        reconnectTargetId = id
        guard central.state == .poweredOn else { pendingRetrieveId = id; return }
        resolveOrScan(id)
    }

    /// Resolve `id` to a live handle and connect; else fall back to a scan. Mirrors the resolve step in
    /// `reconnectTick`. Precondition: the central is powered on.
    private func resolveOrScan(_ id: UUID) {
        let pumpUUID = CBUUID(nsuuid: ServiceUUID.pumpService)
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first
            ?? central.retrieveConnectedPeripherals(withServices: [pumpUUID]).first {
            connect(p)   // reuses connect(_:) → .connecting, sets reconnectTargetId
        } else {
            startScan()  // didDiscover auto-connects when the target (reconnectTargetId) reappears
        }
    }

    /// Set when the user (not a range/BLE drop) asks to disconnect, so we don't auto-reconnect.
    private var intentionalDisconnect = false
    /// Whether we want to be scanning (to resume after Bluetooth toggles back on).
    private var wasScanning = false

    // MARK: Reconnect watchdog
    /// A watchdog that recovers a *stalled* auto-reconnect. CoreBluetooth's pending `connect` normally
    /// completes on its own when the pump returns, but if the peripheral handle was lost or the pending
    /// connect silently died, nothing re-establishes the link — the observed symptom being that the
    /// app has to be force-quit. The watchdog re-resolves the peripheral by identifier (and rescans as
    /// a last resort) on escalating backoff until we're `.ready` again or the user disconnects.
    private var reconnectWatchdog: Timer?
    /// Count of CONSECUTIVE reconnect cycles initiated since the last `.ready` (or a fresh
    /// user-initiated `connect`/`connectKnownPeripheral`). Unlike the pre-fix version, this is NOT reset
    /// on every disconnect — only on success or a genuinely new pairing/connect call — so a flapping
    /// peer actually climbs `reconnectBackoff` instead of restarting at step 0 on every drop.
    private var reconnectAttempts = 0
    /// Set once `reconnectAttempts` exceeds `maxReconnectAttempts` without reaching `.ready`. While true,
    /// automatic reconnect is suspended (`startReconnectWatchdog` becomes a no-op) — see `State.reconnectExhausted`.
    private var reconnectExhausted = false
    /// Identifier of the peripheral we're trying to keep/recover, so we can re-resolve or re-target it.
    private var reconnectTargetId: UUID?
    /// A cold-launch `connectKnownPeripheral(identifier:)` that arrived before Bluetooth was powered on;
    /// the retrieve is deferred to `centralManagerDidUpdateState` once the central reports `.poweredOn`.
    private var pendingRetrieveId: UUID?
    private static let reconnectBackoff: [TimeInterval] = [5, 10, 20, 30]
    /// Ceiling on consecutive reconnect cycles before giving up and surfacing `.reconnectExhausted`
    /// instead of retrying forever. At the ladder's top step (30s, +≤50% jitter) this is roughly 3
    /// minutes of continued, throttled retrying — enough grace for a transient flap, bounded so a peer
    /// that keeps accepting-then-dropping (e.g. still held by the official t:connect app, or a closed
    /// pairing window) can't spin the app indefinitely.
    private static let maxReconnectAttempts = 8
    /// Minimum time the link must have HELD `.ready` before a subsequent drop counts as a genuine
    /// recovery that resets the ladder (`reconnectAttempts`/`reconnectExhausted`). `maybeBecomeReady()`
    /// used to reset both the INSTANT `.ready` was reached, unconditionally — but on-device evidence
    /// (`.planning/debug/pump-pairing-loop.md`, 2026-08-11) shows the peer can accept the connection and
    /// drop it again (`CBErrorDomain` code 7) in under a second, repeatedly. Each such cycle nominally
    /// "succeeded" (it did reach `.ready`), so the ladder reset every time and `maxReconnectAttempts`
    /// never fired — this specific flap looped indefinitely despite the ceiling existing. A hold of at
    /// least this long is trusted as a real recovery; a same-instant re-drop is not, and now still counts
    /// toward the ceiling. Exposed as a pure decision (`readyHeldLongEnoughToResetLadder`) so the
    /// threshold itself is unit-testable without a live `.ready` transition (which needs a real
    /// `CBPeripheral` — see the class doc).
    private static let readyStabilityWindow: TimeInterval = 3
    /// When the link most recently reached `.ready`, so the NEXT disconnect can tell a genuine recovery
    /// from an accept-then-immediately-drop flap. Set in `maybeBecomeReady()`; consumed (and cleared) by
    /// `consumeReadyStabilityAndMaybeReset()` on the following disconnect/fail-to-connect.
    private var readySince: Date?

    /// Pure decision mirroring `jitteredDelay`'s testability: given how long the link had been `.ready`
    /// before this drop, was it held long enough to trust as a real recovery?
    static func readyHeldLongEnoughToResetLadder(heldFor duration: TimeInterval) -> Bool {
        duration >= readyStabilityWindow
    }

    /// Consume `readySince`: if the link had been ready long enough (`readyStabilityWindow`), this was a
    /// genuine recovery — reset the ladder exactly like a fresh success always has. Otherwise leave
    /// `reconnectAttempts`/`reconnectExhausted` untouched so a repeated instant flap still climbs toward
    /// `maxReconnectAttempts` instead of resetting to step 0 on every drop. Internal (not private) so a
    /// unit test can simulate "a disconnect just happened after being ready for N seconds" by setting
    /// `readySinceForTesting` and calling this directly — the same workaround the class already uses for
    /// `reconnectTick()`/`scanTimedOut()` (a live `.ready` transition needs a real `CBPeripheral`).
    func consumeReadyStabilityAndMaybeReset() {
        defer { readySince = nil }
        guard let since = readySince,
              Self.readyHeldLongEnoughToResetLadder(heldFor: Date().timeIntervalSince(since)) else { return }
        reconnectAttempts = 0
        reconnectExhausted = false
    }

    /// Test seam — see `consumeReadyStabilityAndMaybeReset()`. Setting this simulates "the link reached
    /// `.ready` this long ago" without needing a real `CBPeripheral`.
    var readySinceForTesting: Date? {
        get { readySince }
        set { readySince = newValue }
    }

    // MARK: Scan timeout (§5.2.4 / B3b)
    /// A separate one-shot timer (NOT the reconnect watchdog) that fires when a scan for a KNOWN pump
    /// finds nothing within the window. It exists because once `startScan()` latches `.scanning`, nothing
    /// else re-kicks recovery — the watchdog is armed only by disconnect / fail-to-connect. Kept distinct
    /// from `reconnectWatchdog` so the two can't invalidate each other.
    private var scanTimeout: Timer?
    /// How long a known-pump scan may run before we escalate to the reconnect recovery ladder. A minimal
    /// bound — long enough to discover a nearby pump, short enough to escape a latched scan.
    private static let scanTimeoutSeconds: TimeInterval = 30

    /// Arm the scan timeout (called from `startScan`). Replaces any prior one so re-scans re-arm cleanly.
    private func armScanTimeout() {
        scanTimeout?.invalidate()
        scanTimeout = Timer.scheduledTimer(withTimeInterval: Self.scanTimeoutSeconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanTimedOut() }
        }
    }

    private func cancelScanTimeout() { scanTimeout?.invalidate(); scanTimeout = nil }

    /// §5.2.4: a scan that never discovers the pump must recover WITHOUT tearing down — teardown/rebuild
    /// cycles are the CAUSE of the stuck-scanning state. So this does NOT `stopScan` or cancel the pending
    /// connect; it just starts the reconnect recovery ladder (re-resolve + rescan on jittered backoff),
    /// and ONLY when that ladder isn't already running (arming it while it runs would reset the backoff to
    /// step 0). Scoped to a KNOWN-pump scan (`reconnectTargetId != nil`) — a first-time PAIRING scan (no
    /// target) is left to run exactly as before.
    /// Internal (not private) so a unit test can fire it without waiting out the real 30 s timer.
    func scanTimedOut() {
        guard state == .scanning, !intentionalDisconnect,
              reconnectTargetId != nil, reconnectWatchdog == nil else { return }
        startReconnectWatchdog()
    }

    /// B3(b) test accessor — whether the reconnect recovery ladder is currently armed. Read-only; lets a
    /// test assert the scan-timeout escalated to recovery without exposing the timer itself.
    var reconnectWatchdogArmedForTesting: Bool { reconnectWatchdog != nil }
    /// Test accessor — the current consecutive-attempt count, so a test can assert it escalates across
    /// ticks instead of resetting to 0 on every simulated drop (the fast-path-reconnect-loop regression).
    var reconnectAttemptsForTesting: Int { reconnectAttempts }
    /// Test accessor for the ceiling, so a test doesn't hardcode the constant separately.
    static var maxReconnectAttemptsForTesting: Int { maxReconnectAttempts }

    /// A reconnect delay with additive jitter (up to +50%) applied to a fixed ladder step. Without it,
    /// a phone and pump both retrying/advertising on fixed intervals can lock into a beat pattern where
    /// their scan and advertise windows repeatedly miss, stalling recovery; the jitter breaks that
    /// lockstep. Bounded and never shorter than `base`, so it can't tighten the ladder — result is
    /// always in `[base, 1.5·base]` (and exactly `base` when `base <= 0`).
    nonisolated static func jitteredDelay(base: TimeInterval, using rng: inout some RandomNumberGenerator) -> TimeInterval {
        guard base > 0 else { return base }
        return base + TimeInterval.random(in: 0 ... base * 0.5, using: &rng)
    }
    nonisolated static func jitteredDelay(base: TimeInterval) -> TimeInterval {
        var g = SystemRandomNumberGenerator()
        return jitteredDelay(base: base, using: &g)
    }

    public func disconnect() {
        intentionalDisconnect = true
        cancelReconnectWatchdog()
        cancelScanTimeout()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    /// Arm the reconnect ladder if it isn't already running. No-op if the user disconnected or the
    /// ladder is already `.reconnectExhausted` (cleared only by a fresh `connect`/`connectKnownPeripheral`
    /// via `cancelReconnectWatchdog`). Deliberately does NOT reset `reconnectAttempts` and does NOT
    /// re-arm an already-running watchdog: this is called from EVERY disconnect/fail-to-connect, so
    /// resetting here is exactly the bug this fixes — it would let a flapping peer hold the ladder at
    /// step 0 (or restart its currently-pending delay) forever instead of escalating.
    /// Internal (not private) so a unit test can call it directly to simulate a repeated/late disconnect
    /// arriving mid-ladder or after exhaustion, without a real CBPeripheral.
    func startReconnectWatchdog() {
        guard !intentionalDisconnect, !reconnectExhausted, reconnectWatchdog == nil else { return }
        reconnectTargetId = peripheral?.identifier ?? reconnectTargetId
        scheduleNextReconnectAttempt()
    }

    private func scheduleNextReconnectAttempt() {
        let base = Self.reconnectBackoff[min(reconnectAttempts, Self.reconnectBackoff.count - 1)]
        let delay = Self.jitteredDelay(base: base)   // break phone↔pump fixed-interval lockstep (group C)
        // D-08: reconnect attempt# and backoff duration are both non-PHI numerics — .public per the
        // allowlist, so a flapping-peer pattern is visible in a pulled logarchive without correlating
        // back to the app-side BLESessionLog.
        bleLog.log("reconnect attempt=\(self.reconnectAttempts, privacy: .public) delay=\(delay, privacy: .public)s")
        notify { $0.pumpClient(self, willRetryReconnect: self.reconnectAttempts, after: delay) }   // D-05
        reconnectWatchdog?.invalidate()
        reconnectWatchdog = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconnectTick() }
        }
    }

    private func cancelReconnectWatchdog() {
        reconnectWatchdog?.invalidate(); reconnectWatchdog = nil
        reconnectAttempts = 0
        reconnectExhausted = false
        readySince = nil   // a fresh user-initiated connect discards any stale stability window
    }

    /// Internal (not private) so a unit test can fire ladder ticks directly — no real Timer wait, and no
    /// CBPeripheral needed for the "no handle" branch (rescans), which is exactly the path a FakeCentral
    /// test exercises.
    func reconnectTick() {
        // Recovered or the user took over → stop.
        guard !intentionalDisconnect, state != .ready else { cancelReconnectWatchdog(); return }
        // Bluetooth off → wait for `centralManagerDidUpdateState`, but keep the watchdog armed.
        guard central.state == .poweredOn else { scheduleNextReconnectAttempt(); return }
        reconnectAttempts += 1
        if reconnectAttempts > Self.maxReconnectAttempts {
            // Ladder exhausted without ever reaching `.ready` (a flapping peer) — stop the automatic
            // retries and surface it via BOTH the state (for a delegate that keys off `didChange`) and
            // an error (for one that only observes `didError`). `reconnectExhausted` blocks
            // `startReconnectWatchdog` from re-arming until a fresh user-initiated connect clears it.
            reconnectWatchdog?.invalidate(); reconnectWatchdog = nil
            reconnectExhausted = true
            // Fully quiesce: cancel any still-pending `central.connect()` from the last attempt so
            // CoreBluetooth can't silently complete it later and contradict the "gave up" state — mirrors
            // the cancel `disconnect()` issues for a user-initiated stop.
            if let p = peripheral { central.cancelPeripheralConnection(p) }
            state = .reconnectExhausted
            notify { $0.pumpClient(self, didError: ClientError.reconnectLoopDetected) }
            return
        }
        let pumpUUID = CBUUID(nsuuid: ServiceUUID.pumpService)
        // Re-resolve a fresh, valid handle if we lost ours.
        if peripheral == nil, let id = reconnectTargetId {
            peripheral = central.retrievePeripherals(withIdentifiers: [id]).first
                ?? central.retrieveConnectedPeripherals(withServices: [pumpUUID]).first
            peripheral?.delegate = self
        }
        if let p = peripheral {
            if p.state == .connected {
                state = .discovering
                p.discoverServices([pumpUUID])
            } else {
                state = .connecting
                // Re-issuing connect on the same peripheral is idempotent in CoreBluetooth.
                central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
            }
        } else {
            // No handle at all — rescan and auto-reconnect to the target when it reappears.
            startScan()
        }
        scheduleNextReconnectAttempt()
    }

    /// Serializes `message` (framing + optional signing) and writes it to the pump.
    /// - Parameters:
    ///   - authenticationKey/pumpTimeSinceReset: required for signed (insulin-affecting) messages.
    ///   - allowInsulinDelivery: safety gate mirrored into `Packetize`.
    /// - Returns: the transaction id used (for correlating the response).
    @discardableResult
    public func send(
        _ message: Message,
        authenticationKey: [UInt8] = [],
        pumpTimeSinceReset: UInt32 = 0,
        allowInsulinDelivery: Bool = false
    ) throws -> UInt8 {
        // Write interlock (defense in depth): refuse messages the current policy disallows. Authorize on
        // the operation-risk class (audit P-01), via the pure `authorizationError` decision (PX-02) so
        // the block is checked BEFORE readiness — a wrongly-permitted command can't be hidden by
        // `.notReady`. `.readOnly` blocks any control/signed/delivery; `.allowNonDelivery` now blocks
        // destructive too (PX-03); `.allowBenignControl` permits only benign ops.
        if let authError = authorizationError(for: message) { throw authError }
        guard state == .ready, let peripheral,
              let cbChar = characteristics[message.characteristic] else {
            throw ClientError.notReady
        }
        let txId = txIds.nextThenIncrement()
        let packets = try Packetize.packetize(
            message,
            authenticationKey: authenticationKey,
            txId: txId,
            pumpTimeSinceReset: pumpTimeSinceReset,
            actionsAffectingInsulinDeliveryEnabled: allowInsulinDelivery
        )
        for packet in packets {
            peripheral.writeValue(Data(packet.build()), for: cbChar, type: .withResponse)
        }
        return txId
    }

    /// Sends `message` and awaits its correlated response frame with a bounded deadline (PX-08).
    /// The synchronous parts of `send` (authorization + readiness + write) run before suspending, so an
    /// authorization/not-ready failure is thrown immediately and never registers a pending transaction.
    /// On disconnect/teardown the awaiting call is resumed with `TxError.connectionLost` (fail-closed);
    /// on deadline expiry with `TxError.timedOut` — which a delivery caller must treat as *indeterminate*.
    ///
    /// - Parameter responseOpCode: the opcode to correlate; defaults to `message.props.responseOpCode`.
    ///   Throws `ClientError.notReady` if the message declares no response opcode and none is given.
    @discardableResult
    public func sendAwaitingResponse(
        _ message: Message,
        authenticationKey: [UInt8] = [],
        pumpTimeSinceReset: UInt32 = 0,
        allowInsulinDelivery: Bool = false,
        responseOpCode: UInt8? = nil,
        deadline: TimeInterval,
        serialized: Bool = false
    ) async throws -> [UInt8] {
        guard let expectedOpCode = responseOpCode ?? message.props.responseOpCode else {
            throw ClientError.notReady
        }
        let characteristic = message.characteristic
        return try await transactions.perform(
            expectedResponseOn: characteristic, opCode: expectedOpCode, deadline: deadline,
            serialized: serialized
        ) {
            try self.send(message,
                          authenticationKey: authenticationKey,
                          pumpTimeSinceReset: pumpTimeSinceReset,
                          allowInsulinDelivery: allowInsulinDelivery)
        }
    }

    /// Fail-closed teardown (PX-04): reset the write policy to `.readOnly` and resume every outstanding
    /// transaction. Called by the library itself on every disconnect / failed connect / restoration /
    /// error — a caller must never rely on an elevated policy or a pending response surviving a link
    /// change. Prior to this the app had to reset the policy externally (audit A-03), and a missed reset
    /// left `.allowDelivery` standing into the next connection.
    private func failClosed(resumePending: Bool) {
        writePolicy = .readOnly
        // D2 (Addendum G): revert to the FIFO reference correlation on EVERY link change, exactly like the
        // write policy. A relaunched/reconnected central must be re-told the pump family before txId
        // correlation resumes — a fresh connection can never inherit a prior connection's elevated mode.
        transactions.correlationMode = .opcodeFIFO
        if resumePending { transactions.failAll(.connectionLost) }
    }

    // MARK: - Helpers

    // The class is @MainActor; the CB delegate methods (nonisolated) hop here via
    // assumeIsolated, so this runs on the main actor and can call the @MainActor delegate.
    private func notify(_ block: (PumpBLEClientDelegate) -> Void) {
        if let d = delegate { block(d) }
    }

    private func mapCentralState(_ s: CBManagerState) -> State {
        switch s {
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .resetting: return .resetting
        case .poweredOn: return .idle
        default: return .unknown
        }
    }
}

// MARK: - CBCentralManagerDelegate
//
// CoreBluetooth delegate methods are nonisolated by protocol, but the central is created with
// `queue: .main`, so they always run on the main thread — `MainActor.assumeIsolated` hops into
// the @MainActor instance soundly.

extension PumpBLEClient: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            state = mapCentralState(central.state)
            // Recover after Bluetooth toggles back on: resume a pending connection (or rescan).
            if central.state == .poweredOn && !intentionalDisconnect {
                if let p = peripheral, p.state != .connected {
                    state = .connecting
                    central.connect(p, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                } else if peripheral == nil, let id = pendingRetrieveId {
                    // A cold-launch connectKnownPeripheral() arrived before BT was on — honor it now.
                    pendingRetrieveId = nil
                    resolveOrScan(id)
                } else if peripheral == nil && wasScanning {
                    startScan()
                }
            } else if central.state != .poweredOn {
                // R3-D: any non-usable central state — poweredOff, unauthorized, unsupported, resetting —
                // means the link is gone. `didDisconnectPeripheral` does NOT necessarily fire for a BT
                // power-off, so without this an outstanding transaction would hang to its deadline and an
                // elevated write policy would survive the outage. Fail closed: reset to read-only and
                // resume every pending transaction with `.connectionLost` (a bolus caller maps that to
                // indeterminate — never a fabricated success).
                failClosed(resumePending: true)
            }
        }
    }

    /// State restoration: iOS relaunched us (e.g. after termination) with the pump connection
    /// preserved. Re-adopt the restored pump so notifications/reconnect resume without a fresh scan.
    ///
    /// We re-find it via `central.retrieveConnectedPeripherals` rather than reading the restored-
    /// state `dict`: `[String: Any]` is non-Sendable and can't be sent into the main-actor closure
    /// under Swift 6. A restore that was still mid-connection isn't "connected" yet, so it won't be
    /// returned here — but its pending connect persists across restoration and completes via
    /// `didConnect` (which adopts the peripheral). Discovery/subscription continue as normal.
    public nonisolated func centralManager(_ central: CBCentralManager,
                                           willRestoreState dict: [String: Any]) {
        MainActor.assumeIsolated {
            failClosed(resumePending: false)   // PX-04: a relaunched central starts read-only
            let pumpUUID = CBUUID(nsuuid: ServiceUUID.pumpService)
            guard let p = central.retrieveConnectedPeripherals(withServices: [pumpUUID]).first else { return }
            self.peripheral = p
            p.delegate = self
            state = .discovering
            p.discoverServices([pumpUUID])
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            // Watchdog rescan fallback: if this is the peripheral we're trying to recover, reconnect
            // to it directly rather than waiting for the app to choose again.
            if !intentionalDisconnect, state != .ready, peripheral.identifier == reconnectTargetId {
                connect(peripheral)
                return
            }
            notify { $0.pumpClient(self, didDiscover: peripheral, rssi: RSSI.intValue) }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            // Adopt the peripheral (idempotent in the normal flow where connect() already set it;
            // also covers a connect that completed after state restoration).
            self.peripheral = peripheral
            peripheral.delegate = self
            state = .discovering
            peripheral.discoverServices([CBUUID(nsuuid: ServiceUUID.pumpService)])
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated {
            characteristics.removeAll()
            reassembly.removeAll()
            failClosed(resumePending: true)   // PX-04/PX-08: policy → .readOnly, resume all waiters
            // Was the link that just dropped a genuine recovery (held `.ready` >= `readyStabilityWindow`),
            // or an accept-then-immediately-drop flap? Only the former resets the ladder — see
            // `readyStabilityWindow`'s doc. Must run before the `reconnectExhausted` check below, since a
            // long-held `.ready` (e.g. a stray late reconnect after exhaustion) can flip it back to false.
            consumeReadyStabilityAndMaybeReset()
            if let error {
                // D-03/D-06: domain+code are stable machine tokens, not PHI → .public, so they survive to
                // a pulled logarchive alongside the app-side CBError capture. `localizedDescription` can
                // occasionally embed a peripheral/device name on some CB error paths → stays .private
                // (D-08; redaction is emit-time and unrecoverable — Pitfall 2).
                let ns = error as NSError
                bleLog.log("disconnect domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) desc=\(ns.localizedDescription, privacy: .private)")
                notify { $0.pumpClient(self, didError: error) }
            }
            // Auto-reconnect on an unintended drop (e.g. out of range): re-issuing `central.connect()`
            // makes CoreBluetooth complete it automatically when the pump comes back in range, in the
            // foreground or background — no manual "Connect" needed. Go straight to .connecting (skip a
            // .disconnected flicker) so the UI shows "reconnecting". The actual `central.connect()` call
            // is now made by `reconnectTick()` after the ladder's jittered delay, NOT here with zero
            // delay — a peer that keeps accepting-then-dropping the link (pairing-window flap) would
            // otherwise drive an unthrottled connect/disconnect loop, since `startReconnectWatchdog` no
            // longer resets `reconnectAttempts` on every drop (that reset was the other half of the bug).
            if !intentionalDisconnect {
                self.peripheral = peripheral
                peripheral.delegate = self
                if reconnectExhausted {
                    // Already gave up (e.g. a stray late completion of the connect we cancelled when the
                    // ceiling hit). Re-confirm the exhausted state rather than flashing `.connecting` with
                    // no watchdog behind it — `startReconnectWatchdog` would be a no-op here anyway.
                    state = .reconnectExhausted
                } else {
                    state = .connecting
                    startReconnectWatchdog()   // schedules the throttled reconnect attempt (and recovers a stall)
                }
            } else {
                state = .disconnected
            }
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                           error: Error?) {
        MainActor.assumeIsolated {
            failClosed(resumePending: true)   // PX-04/PX-08: never leave policy elevated or a waiter hung
            // Defensive/symmetry with `didDisconnectPeripheral` — normally already consumed (and cleared)
            // by the disconnect that preceded this failed reconnect attempt; harmless no-op if so.
            consumeReadyStabilityAndMaybeReset()
            if let error { notify { $0.pumpClient(self, didError: error) } }
            // Retry unless the user disconnected. As in `didDisconnectPeripheral`, the retry itself is
            // throttled through the reconnect ladder (`startReconnectWatchdog` → `reconnectTick`), not
            // re-issued here with zero delay — see that handler's comment for why.
            if !intentionalDisconnect {
                self.peripheral = peripheral
                peripheral.delegate = self
                if reconnectExhausted {
                    state = .reconnectExhausted
                } else {
                    state = .connecting
                    startReconnectWatchdog()
                }
            } else {
                state = .disconnected
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension PumpBLEClient: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            if let error { notify { $0.pumpClient(self, didError: error) }; return }
            // Fresh (re)discovery → reset the subscription-ready barrier so a reconnect re-confirms notify.
            requestedNotify.removeAll()
            confirmedNotifying.removeAll()
            let pumpUUID = CBUUID(nsuuid: ServiceUUID.pumpService)
            for service in peripheral.services ?? [] where service.uuid == pumpUUID {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                       error: Error?) {
        MainActor.assumeIsolated {
            if let error { notify { $0.pumpClient(self, didError: error) }; return }
            for cb in service.characteristics ?? [] {
                guard let mapped = Characteristic.of(uuid: cb.uuid.uuidValue) else { continue }
                characteristics[mapped] = cb
                if ServiceUUID.notificationCharacteristics.contains(mapped),
                   cb.properties.contains(.notify) {
                    requestedNotify.insert(mapped)
                    peripheral.setNotifyValue(true, for: cb)
                }
            }
            // PX-08: do NOT declare `.ready` here. Readiness now waits for the pump to CONFIRM the
            // notification subscriptions (`didUpdateNotificationState`) so a response channel is live
            // before any delivery is written — see `maybeBecomeReady()`.
            maybeBecomeReady()
        }
    }

    /// Become `.ready` only once the messaging characteristics are present AND every requested
    /// notification subscription has been confirmed by the pump (PX-08 subscription-ready barrier).
    private func maybeBecomeReady() {
        guard state != .ready else { return }
        guard characteristics[.currentStatus] != nil, characteristics[.authorization] != nil else { return }
        guard !requestedNotify.isEmpty, requestedNotify.isSubset(of: confirmedNotifying) else { return }
        // NOTE: deliberately NOT `cancelReconnectWatchdog()` here — that would reset
        // `reconnectAttempts`/`reconnectExhausted` the instant `.ready` is reached, before we know the
        // link will actually hold (see `readyStabilityWindow`'s doc: a flapping peer can reach `.ready`
        // and drop again in under a second, every cycle). No pending retry needs to fire while ready,
        // though, so invalidate the watchdog TIMER without touching the attempt count.
        reconnectWatchdog?.invalidate(); reconnectWatchdog = nil
        cancelScanTimeout()         // B3b: no scan in flight once ready
        readySince = Date()         // starts the stability window `consumeReadyStabilityAndMaybeReset` checks
        state = .ready
        notify { $0.pumpClientDidBecomeReady(self) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            // A failed subscription means a response channel isn't live → fail closed (PX-04/PX-08): reset
            // the write policy and resume any pending transaction, and surface the error.
            if let error {
                failClosed(resumePending: true)
                notify { $0.pumpClient(self, didError: error) }
                return
            }
            guard let mapped = Characteristic.of(uuid: characteristic.uuid.uuidValue) else { return }
            if characteristic.isNotifying { confirmedNotifying.insert(mapped) }
            else { confirmedNotifying.remove(mapped) }
            maybeBecomeReady()
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            // A read/notify-value error orphans any awaited response → fail closed (reset policy + resume
            // every pending transaction) so a delivery caller sees connectionLost, not a silent hang (§6 req 5).
            if let error {
                failClosed(resumePending: true)
                notify { $0.pumpClient(self, didError: error) }
                return
            }
            guard let mapped = Characteristic.of(uuid: characteristic.uuid.uuidValue),
                  let data = characteristic.value else { return }
            var reassembler = reassembly[mapped] ?? PacketReassembler()
            if let frame = reassembler.ingest([UInt8](data)) {
                reassembly[mapped] = PacketReassembler()
                // PX-08: if an awaited transaction correlates to this frame, it consumes it. Otherwise
                // (unsolicited stream/status, or a caller still on the delegate path) deliver as before.
                if !transactions.ingest(frame: frame, on: mapped) {
                    notify { $0.pumpClient(self, didReceiveFrame: frame, on: mapped) }
                }
            } else {
                reassembly[mapped] = reassembler
            }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated { if let error { notify { $0.pumpClient(self, didError: error) } } }
    }
}

private extension CBUUID {
    /// CBUUIDs from the pump are 128-bit; convert to Foundation UUID for our enum lookup.
    var uuidValue: UUID { UUID(uuidString: uuidString) ?? UUID() }
}
