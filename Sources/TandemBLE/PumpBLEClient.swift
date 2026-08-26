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
    /// CC-03 (kit half): the pump's qualifying-events bitmap, decoded and dispatched typed. Fired
    /// only when the decoded set is non-empty (an all-zero bitmap dispatches nothing). App-side
    /// pause-sends / dedup consumption is Phase 13 — NOT this delegate method's concern; the kit
    /// only decodes + dispatches + issues the reference-backed clear (see `PumpBLEClient
    /// .handleQualifyingEventsFrame`).
    func pumpClient(_ client: PumpBLEClient, didReceiveQualifyingEvent event: QualifyingEvent)
}

/// Default no-op for `willRetryReconnect` — every conformer that doesn't care about the reconnect
/// ladder's internals (today: `WatchPumpClient` and the TandemKit test/bench-harness conformers) keeps
/// compiling unchanged; only a conformer that wants the signal overrides it.
@MainActor
public extension PumpBLEClientDelegate {
    func pumpClient(_ client: PumpBLEClient, willRetryReconnect attempt: Int, after delay: TimeInterval) {}
    /// Default no-op, mirroring `willRetryReconnect` above — every existing conformer (WatchPumpClient,
    /// test/bench/harness delegates) keeps compiling unchanged; faBolus (Phase 13) overrides this to
    /// consume the comms-suspension signal instead of silently dropping it.
    func pumpClient(_ client: PumpBLEClient, didReceiveQualifyingEvent event: QualifyingEvent) {}
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
        /// A message was refused by the device/API send gate (D-08): the KNOWN connected pump does not
        /// support this opcode (wrong device family, or a negotiated API below the message's `minApi`).
        /// A refusal, not a delivery outcome — thrown BEFORE any byte is emitted, exactly like
        /// `writeBlocked`. Only ever raised for a KNOWN-incompatible target; an unknown target fails open.
        case unsupportedOnDevice(opcode: UInt8)
        /// CC-06 (REMED-15.5): a model-restricted message was refused because the send-time target is
        /// UNIDENTIFIED-OR-UNTRUSTED, carrying the refused message's `opcode`. DISTINCT from
        /// `.unsupportedOnDevice`: that case is raised for a KNOWN-TRUSTED-incompatible target (the model
        /// is confidently wrong); this case is raised when there is no trusted model to check against at
        /// all — either `connectedPumpModel == nil`, or a non-nil model that was never established via a
        /// TRUSTED source (see `identityTrusted`'s doc — the codex C1 hazard this closes: a t:slim
        /// misidentified as Mobi by op33's ambiguous API-version heuristic must NOT satisfy this gate). A
        /// refusal, not a delivery outcome — thrown BEFORE any byte is emitted, exactly like `writeBlocked`
        /// / `unsupportedOnDevice`. GENERALIZED (15.5-03, owner-ratified S-B): covers every
        /// `supportedDevices`-restricted message — the 14 control/delivery messages AND the 2
        /// model-restricted reads — minus the (currently empty) `SendGateBootstrapAllowlist` (see
        /// `identityGateError`'s doc for the exact predicate).
        case identityNotEstablished(opcode: UInt8)
        /// The reconnect ladder hit `maxReconnectAttempts` without reaching `.ready` — surfaced alongside
        /// `State.reconnectExhausted` so a delegate that only observes `didError` still sees it.
        case reconnectLoopDetected
        /// CX-T-10: refused because a user-initiated `disconnect()` is in flight — `intentionalDisconnect`
        /// is set but `didDisconnectPeripheral` hasn't yet fired to tear down `state`/`peripheral`/
        /// `characteristics`. Checked BEFORE the readiness guard (same precedence as `authorizationError`/
        /// `deviceSupportError`) so a straggler send can't slip through on a link CoreBluetooth is already
        /// tearing down. A DISTINCT case from `.notReady` — not just cosmetic: `.notReady` from a genuinely
        /// absent connection is masking-safe to retry once reconnected, while `.disconnecting` tells the
        /// caller this exact link is going away, mirroring why `.unsupportedOnDevice` is its own case
        /// rather than reusing `.notReady` (both make an otherwise-truthy readiness state a hidden refusal).
        case disconnecting
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

    /// The KNOWN connected pump model, or `nil` when unidentified. Input to the device/API send gate
    /// (D-08); `nil` means the gate fails **open** (send, let firmware NACK), preserving today's behavior.
    /// Reset to `nil` on every disconnect/error by `failClosed` — a fresh connection re-identifies.
    public private(set) var connectedPumpModel: PumpModel?
    /// CC-06 (REMED-15.5): whether `connectedPumpModel` was established via a TRUSTED source — live
    /// BLE-name detection, or a persisted trusted identity reapplied for the same peripheral (15.5-02) —
    /// as opposed to a merely-plausible non-nil model. Defaults to `false`. This is `identityGateError`'s
    /// (CC-06) trust signal for the model-restricted send gate: it is deliberately a SEPARATE bit from
    /// `connectedPumpModel != nil`, because `connectedPumpModel` alone can be set by op33's ambiguous
    /// API-version heuristic — an inference, not an identification — and a silent reconnect can land it on
    /// the WRONG family (the codex C1 hazard: a real t:slim misidentified as Mobi). `identityGateError`
    /// MUST NEVER treat a non-nil `connectedPumpModel` as sufficient on its own; it must consult this flag.
    /// `deviceSupportError` (D-08 / VA-06) is INTENTIONALLY UNCHANGED by this flag — it keeps consulting
    /// `connectedPumpModel` regardless of trust, since that gate's fail-open contract predates CC-06 and is
    /// out of scope here. Reset to `false` on every disconnect/error by `failClosed`, alongside
    /// `connectedPumpModel`, so a reconnect starts untrusted until a TRUSTED source re-establishes it.
    public private(set) var identityTrusted: Bool = false
    /// The negotiated pump API version, or `nil` when not yet negotiated. Input to the device/API send
    /// gate (D-08); `nil` fails **open**. Reset to `nil` on every disconnect/error by `failClosed`.
    public private(set) var negotiatedApiVersion: ApiVersion?

    /// Supply the identified device context for the device/API send gate (D-08) and the CC-06
    /// trusted-identity gate. The caller owns model classification + API negotiation (as with
    /// `setPumpFamily`); the kit never guesses. Passing `nil` for `model`/`apiVersion` keeps that dimension
    /// fail-open. `trusted` is REQUIRED (no default) so every call site makes an explicit, auditable trust
    /// decision — mirroring the codebase's explicit-over-implicit idiom — rather than silently defaulting
    /// to either extreme. Pass `true` only when `model` was identified via a TRUSTED source (BLE-name
    /// detection, or 15.5-02's persisted-trusted reapplication); pass `false` for any heuristic-derived
    /// model (e.g. op33's API-version inference alone), which is exactly the codex C1 hazard this gate
    /// exists to close. `identityTrusted` is set to `trusted && (model != nil)` — trust is meaningless
    /// without a model. Must be called AFTER each (re)identification, since `failClosed` clears both
    /// `connectedPumpModel` and `identityTrusted` on every link change.
    public func setDeviceContext(model: PumpModel?, apiVersion: ApiVersion?, trusted: Bool) {
        connectedPumpModel = model
        negotiatedApiVersion = apiVersion
        identityTrusted = trusted && (model != nil)
    }

    /// Pure authorization decision (PX-02), separated from readiness/transport so it is deterministically
    /// testable and cannot be masked by `.notReady`. Returns the exact `.writeBlocked` error a policy
    /// would raise for `message`, or `nil` if the policy permits it. `send()` consults this first.
    public func authorizationError(for message: Message) -> ClientError? {
        writePolicy.permits(message.operationRisk)
            ? nil
            : .writeBlocked(policy: writePolicy, opcode: message.opCode)
    }

    /// Pure device/API send-gate decision (D-08), separated from readiness/transport so it is
    /// deterministically testable and cannot be masked by `.notReady`. Returns `.unsupportedOnDevice`
    /// when the KNOWN connected pump does not support `message` (wrong family, or a negotiated API below
    /// the message's `minApi`), or `nil` when it is supported. **Fails open** on an unknown model/api:
    /// `MessageProps.isSupported` returns `true` for any nil target dimension, so an unidentified pump
    /// never gates a send — today's send-then-firmware-NACK behavior is preserved. `send()` consults this
    /// AFTER `authorizationError` (the write-policy interlock stays the first line of defense).
    public func deviceSupportError(for message: Message) -> ClientError? {
        message.props.isSupported(onModel: connectedPumpModel, apiVersion: negotiatedApiVersion)
            ? nil
            : .unsupportedOnDevice(opcode: message.opCode)
    }

    /// CC-06 (REMED-15.5): pure trusted-identity send-gate decision, separated from readiness/transport so
    /// it is deterministically testable and cannot be masked by `.notReady` — same `xxxError(for:)` shape
    /// and doc discipline as the sibling `deviceSupportError` (D-08), which this is layered ABOVE (not a
    /// replacement for it — `deviceSupportError` is UNCHANGED and still consults `connectedPumpModel`
    /// regardless of trust). Returns `nil` (fail OPEN) when the identity is TRUSTED and known
    /// (`connectedPumpModel != nil AND identityTrusted`) — the codex C1 fix: gating on non-nil alone would
    /// let a wrong op33-heuristic model satisfy the gate, which this predicate must never do — this trust
    /// condition is preserved UNCHANGED through the 15.5-03 generalization below.
    ///
    /// GENERALIZED (15.5-03, owner-ratified scope S-B — see `OWNER-DECISIONS.md` "15.5-03 scope of the
    /// fail-closed net"): the 15.5-01 tracer's opcode-narrowing guard (which refused ONLY
    /// `SetSleepScheduleRequest`'s 0xCE) is REMOVED. The final predicate:
    ///  1. `connectedPumpModel != nil AND identityTrusted` → fail OPEN (unchanged, see above).
    ///  2. `message.props.supportedDevices == nil` (UNRESTRICTED message) → fail OPEN, exactly like
    ///     `deviceSupportError`'s own unrestricted case.
    ///  3. `(message.characteristic, message.opCode)` is in `SendGateBootstrapAllowlist.entries`
    ///     (or, in a `#if DEBUG` build, `bootstrapAllowlistOverrideForTesting` when non-nil — see that
    ///     property's doc) **AND** `message.operationRisk == .read` → fail OPEN. The `operationRisk == .read`
    ///     conjunct is a STRUCTURAL, runtime-enforced guard (codex C2): even a mistaken control/delivery-class
    ///     entry in the allowlist can NEVER be honored, because this check is inside the gate itself, not a
    ///     convention the allowlist's authors must uphold. Under S-B every model-restricted message not
    ///     covered by 1–3 above is refused — the full 14 control/delivery messages AND the 2 model-restricted
    ///     reads (`CgmStatusV2Request` 0xBE, `UnknownMobiOpcode110Request` 110) all fail closed on an
    ///     untrusted/unidentified target.
    ///  4. Otherwise → `.identityNotEstablished(opcode:)`.
    public func identityGateError(for message: Message) -> ClientError? {
        if connectedPumpModel != nil && identityTrusted { return nil }
        guard message.props.supportedDevices != nil else { return nil }
        // RED-STATE PLACEHOLDER (15.5-03 TDD scaffold): still tracer-scoped to 0xCE — REMOVED in the GREEN
        // commit that follows. Present only so the generalized/collision/S-B test assertions below fail
        // first, proving they exercise the not-yet-generalized code.
        guard message.opCode == SetSleepScheduleRequest.props.opCode else { return nil }
        let key = SendGateAllowlistKey(characteristic: message.characteristic, opCode: message.opCode)
        #if DEBUG
        let allowlist = bootstrapAllowlistOverrideForTesting ?? SendGateBootstrapAllowlist.entries
        #else
        let allowlist = SendGateBootstrapAllowlist.entries
        #endif
        if allowlist.contains(key) && message.operationRisk == .read { return nil }
        return .identityNotEstablished(opcode: message.opCode)
    }

    #if DEBUG
    /// Test-only override for the CC-06 bootstrap-read allowlist (codex C2 Open Question #2), so a test can
    /// prove the ALLOWLISTED branch of `identityGateError` is reachable and correct without depending on
    /// today's real (empty) `SendGateBootstrapAllowlist.entries` content. `nil` (the default) uses the real
    /// production allowlist. Mirrors the existing `*ForTesting` test-seam idiom used elsewhere in this class
    /// (e.g. `establishmentTimeoutForTesting`) and in the app (`PumpReadScheduler.alertReadDelaySecForTesting`).
    /// `send()`'s call site (`identityGateError(for: message)`) stays byte-unchanged — this seam is consulted
    /// entirely inside `identityGateError` itself.
    var bootstrapAllowlistOverrideForTesting: Set<SendGateAllowlistKey>?
    #endif

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
        // R2-11 defect 3: bound this fresh/cold establishment. Armed AFTER `cancelReconnectWatchdog()`
        // above (which clears it) so the deadline starts now; cancelled at `.ready` / on any teardown.
        armEstablishmentWatchdog()
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
    /// debug pump-background-disconnect (H1). Set when an UNINTENDED-drop path has issued its ONE inline
    /// background-safe `central.connect()` (see `planUnintendedDropRecovery`), so the reconnect ladder's
    /// FIRST tick is pure BACKOFF and does NOT stack a second concurrent connect against the still-pending
    /// one. Cleared on any link change (`failClosed`), a successful `didConnect`, a fresh user-initiated
    /// connect (`cancelReconnectWatchdog`), the first tick that consumes it, and ladder exhaustion.
    private var inlineConnectPending = false
    /// Identifier of the peripheral we're trying to keep/recover, so we can re-resolve or re-target it.
    /// CC-06/C10 (REMED-15.5): read-only exposed (`public private(set)`) so faBolus's app-side trust
    /// reapplication (`reapplyTrustedIdentityIfKnown`) can confirm the peripheral the kit is ACTUALLY
    /// (re)connecting before stamping a persisted trusted identity — a stale trusted record for a
    /// DIFFERENT peripheral (pump-swap-mid-reconnect, or a restoration adopting a different peripheral)
    /// must never be applied. Additive, read-only — no writer changed, no behavior change.
    public private(set) var reconnectTargetId: UUID?
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

    /// Test seam (CX-T-05) — a real `.ready` transition needs a live `CBPeripheral`/`CBCharacteristic`
    /// (hardware-only per the class doc's TCC note). Setting this directly lets a unit test exercise
    /// `.ready`-gated behavior (the post-ready notification-loss revoke) without driving the full
    /// CoreBluetooth discovery dance. Goes through the same stored property as production, so `didSet`'s
    /// `didChange` notification still fires — no divergent test path.
    var stateForTesting: State {
        get { state }
        set { state = newValue }
    }

    /// Test seam (CX-T-10) — simulates "a user-initiated `disconnect()` is in flight" without needing a
    /// real `CBPeripheral`/`cancelPeripheralConnection` round trip.
    var intentionalDisconnectForTesting: Bool {
        get { intentionalDisconnect }
        set { intentionalDisconnect = newValue }
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

    // MARK: Establishment watchdog (R2-11 defect 3)
    /// A one-shot deadline on the PRE-`.ready` establishment chain:
    /// `.connecting → didConnect → .discovering → discoverServices → discoverCharacteristics →
    /// maybeBecomeReady → .ready`. A transient CoreBluetooth stall can otherwise strand `.connecting`/
    /// `.discovering` forever — unlike a scan (bounded by `scanTimeout`) or a post-`.ready` drop (recovered
    /// by the reconnect ladder), nothing else re-kicks an establishment that accepts the connect but never
    /// finishes discovery/subscription. Armed on entry to `.connecting` for a fresh/cold establishment
    /// (`connect(_:)` and the connect branch of `reconnectTick`) and cancelled at `.ready`
    /// (`maybeBecomeReady`) plus on every teardown (`disconnect`, `failClosed`, `cancelReconnectWatchdog`)
    /// so it can't outlive its window or double-fire.
    ///
    /// COMPOSITION: this is DISJOINT from the app-side pairing-handshake watchdog (faBolus `TandemBackend`,
    /// FB-4 / R2-01, armed AFTER `.ready` at `coord.start()`). This one covers PRE-`.ready` and hands off
    /// exactly at `.ready` (cancelled in `maybeBecomeReady`); the app-side one covers POST-`.ready`. No
    /// pairing logic lives here.
    private var establishmentWatchdog: Timer?
    /// How long the pre-`.ready` establishment may run before failing closed. A sane bound — long enough
    /// for a real connect + service/characteristic discovery + subscription confirmation, short enough that
    /// a stalled establishment can't strand the UI indefinitely. Matches the scan-timeout bound.
    private static let establishmentTimeoutSeconds: TimeInterval = 30
    /// Test seam — inject a shorter/zero establishment deadline so a unit test needn't wait out the real
    /// timer (mirrors the injectable-deadline `*ForTesting` convention used elsewhere in this class).
    var establishmentTimeoutForTesting: TimeInterval?

    /// Arm the establishment watchdog, replacing any prior one so a re-entry re-arms cleanly. Called on
    /// entry to `.connecting` for a genuine fresh/cold establishment only (see the property doc).
    private func armEstablishmentWatchdog() {
        establishmentWatchdog?.invalidate()
        let interval = establishmentTimeoutForTesting ?? Self.establishmentTimeoutSeconds
        establishmentWatchdog = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.establishmentTimedOut() }
        }
    }

    private func cancelEstablishmentWatchdog() { establishmentWatchdog?.invalidate(); establishmentWatchdog = nil }

    /// R2-11 defect 3: the establishment chain stalled before reaching `.ready`. Fail closed (reset write
    /// policy + resume any waiter), cancel the still-pending connect so CoreBluetooth can't silently
    /// complete it later, and drop the half-built discovery/subscription state. Then recover per target: a
    /// KNOWN target enters the throttled reconnect ladder (same as a scan-timeout / drop — no counter
    /// reset, no double-arm), while a first-pair cold connect terminates cleanly at a retryable
    /// `.disconnected`. Internal (not private) so a unit test can fire it directly without waiting out the
    /// real timer (mirrors `scanTimedOut()`).
    func establishmentTimedOut() {
        cancelEstablishmentWatchdog()
        guard state != .ready else { return }
        failClosed(resumePending: true)
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        characteristics.removeAll()
        requestedNotify.removeAll()
        confirmedNotifying.removeAll()
        if reconnectTargetId != nil {
            startReconnectWatchdog()   // KNOWN target → throttled recovery ladder (no reset, no double-arm)
        } else {
            state = .disconnected      // first-pair cold connect → clean, retryable terminal
        }
    }

    /// Test accessor — whether the establishment watchdog is currently armed (read-only; mirrors
    /// `reconnectWatchdogArmedForTesting`).
    var establishmentWatchdogArmedForTesting: Bool { establishmentWatchdog != nil }
    /// Test seam — fire the establishment watchdog without waiting out the real timer (mirrors calling
    /// `scanTimedOut()` directly). Thin wrapper over the internal `establishmentTimedOut()`.
    func fireEstablishmentWatchdogForTesting() { establishmentTimedOut() }

    /// §5.2.4 / R2-11 defect 1: a scan that never discovers the pump must not run forever. Branches on
    /// whether a target is KNOWN:
    ///  • KNOWN pump (`reconnectTargetId != nil`) — recover WITHOUT tearing down (teardown/rebuild cycles
    ///    are the CAUSE of the stuck-scanning state). Does NOT `stopScan` or cancel the pending connect; it
    ///    just starts the reconnect recovery ladder (re-resolve + rescan on jittered backoff), and ONLY when
    ///    that ladder isn't already running (arming it while it runs would reset the backoff to step 0).
    ///    This branch is preserved byte-for-byte behaviorally from before the fix, so the throttle/backoff/
    ///    exhaustion assertions (ReconnectThrottleTests/BackgroundReconnectTests) still hold.
    ///  • FIRST PAIR (`reconnectTargetId == nil`) — there is no target to ladder toward, and the old code
    ///    early-returned so this scan ran unbounded forever. Terminate cleanly instead: `stopScan()` then
    ///    publish a retryable terminal `.disconnected`. Deliberately NOT routed into the reconnect ladder.
    /// Internal (not private) so a unit test can fire it without waiting out the real 30 s timer.
    func scanTimedOut() {
        guard state == .scanning, !intentionalDisconnect else { return }
        if reconnectTargetId != nil {
            guard reconnectWatchdog == nil else { return }
            startReconnectWatchdog()
        } else {
            stopScan()
            state = .disconnected
        }
    }

    /// B3(b) test accessor — whether the reconnect recovery ladder is currently armed. Read-only; lets a
    /// test assert the scan-timeout escalated to recovery without exposing the timer itself.
    var reconnectWatchdogArmedForTesting: Bool { reconnectWatchdog != nil }
    /// Test accessor — the current consecutive-attempt count, so a test can assert it escalates across
    /// ticks instead of resetting to 0 on every simulated drop (the fast-path-reconnect-loop regression).
    var reconnectAttemptsForTesting: Int { reconnectAttempts }
    /// Test seam (debug pump-background-disconnect) — whether an inline background-safe connect is currently
    /// marked pending. Get/set (mirrors `readySinceForTesting`) so a unit test can simulate the drop path
    /// having issued the inline connect without a live `CBPeripheral` (see the class doc).
    var inlineConnectPendingForTesting: Bool {
        get { inlineConnectPending }
        set { inlineConnectPending = newValue }
    }
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
        // R2-11 defect 2: a user cancel must quiesce the radio and reject any late discovery. The old
        // code never stopped the scan, so a first-pair discovery that landed after Cancel still
        // auto-connected (see the `!intentionalDisconnect` guard added at the top of `didDiscover`), and
        // when there was no peripheral (a first-pair scan) it never published a terminal state at all.
        stopScan()                      // stop scanning + cancelScanTimeout (subsumed) — no late auto-connect
        cancelReconnectWatchdog()       // also cancels the establishment watchdog
        cancelEstablishmentWatchdog()   // explicit: no cold-connect watchdog may outlive a user cancel
        reconnectTargetId = nil         // no auto-reconnect target survives an intentional disconnect
        pendingRetrieveId = nil         // drop any deferred cold-launch retrieve
        // CX-T-10: publish the terminal state SYNCHRONOUSLY, before the async CoreBluetooth teardown
        // (`cancelPeripheralConnection` → eventual `didDisconnectPeripheral`) completes. The old code only
        // set `state` here for the no-peripheral (first-pair scan) branch and otherwise left `state`
        // whatever it was (often `.ready`/`.connecting`) until the delegate callback caught up — a
        // straggler `send()` issued in that gap saw an honest-looking `.ready` on a link already being torn
        // down. `send()` additionally guards on `intentionalDisconnect` directly (see its doc), so the two
        // fixes are defense-in-depth, not redundant: this makes `state` itself honest for any caller that
        // checks it; the guard in `send()` closes the gap even for a caller that doesn't.
        state = .disconnected
        if let p = peripheral {
            central.cancelPeripheralConnection(p)   // established/connecting → CB will report didDisconnect
        }
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

    /// debug pump-background-disconnect (H1 root). The reconcilable core of unintended-drop recovery,
    /// factored out of `didDisconnectPeripheral` so the throttle-preservation + non-stacking logic is
    /// unit-testable without a live `CBPeripheral`; the caller performs the single
    /// `central.connect(peripheral, …)` on the real handle CoreBluetooth hands it — the only part that needs
    /// hardware (bench/device-verified).
    ///
    /// Returns whether the caller SHOULD issue the inline background-safe connect. It is issued ONLY for a
    /// GENUINE drop — one where the link had held `.ready` for at least `readyStabilityWindow`
    /// (`heldReadyStably`) — so a background idle/supervision-timeout drop recovers immediately (a pending CB
    /// connect completes while the app is suspended, which the main-RunLoop reconnect Timer cannot do once
    /// suspended), while a sub-window pairing FLAP gets NO zero-delay connect and is left to the throttled
    /// ladder. That gate is exactly what keeps the pump-pairing-loop flap throttle intact: without it a
    /// zero-delay connect would recover a flapping peer faster than the 5 s ladder tick, so `reconnectAttempts`
    /// would never climb to `.reconnectExhausted` (the exact regression `.planning/debug/pump-pairing-loop.md`
    /// fixed). Never resets `reconnectAttempts`/`reconnectExhausted`; arms the ladder as backoff/escalation
    /// exactly as before. Internal (not private) so a unit test can drive it without a `CBPeripheral`.
    @discardableResult
    func planUnintendedDropRecovery(heldReadyStably: Bool) -> Bool {
        guard !intentionalDisconnect, !reconnectExhausted else { return false }
        if heldReadyStably { inlineConnectPending = true }
        startReconnectWatchdog()   // backoff/escalation ladder; no counter reset, no double-arm
        return heldReadyStably
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
        inlineConnectPending = false   // debug pump-background-disconnect: fresh intent → no stale pending connect
        cancelEstablishmentWatchdog()  // R2-11: a fresh intent / teardown must not leave a stale cold-connect deadline
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
            inlineConnectPending = false   // debug pump-background-disconnect: pending connect cancelled above
            state = .reconnectExhausted
            notify { $0.pumpClient(self, didError: ClientError.reconnectLoopDetected) }
            return
        }
        // debug pump-background-disconnect (H1): if the drop already issued an inline background-safe
        // connect, this FIRST ladder tick is pure BACKOFF — CoreBluetooth will complete that pending connect
        // when the pump returns, so do NOT stack a second concurrent connect. Consume the flag; the NEXT tick
        // escalates (re-resolve / reconnect / rescan) if the pending connect is still stalled by then.
        if inlineConnectPending {
            inlineConnectPending = false
            scheduleNextReconnectAttempt()
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
                // R2-11 defect 3: a ladder-driven connect can also stall pre-`.ready`; bound it. Cancelled
                // at `.ready`/teardown. `armEstablishmentWatchdog()` REPLACES any prior instance, so the two
                // watchdogs never stack; the reconnect ladder still owns its own throttle timer separately.
                armEstablishmentWatchdog()
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
        // Device/API send gate (D-08): refuse — do NOT emit — a message the KNOWN connected pump does not
        // support (wrong family or a negotiated API below the message's minApi). Checked BEFORE readiness
        // so a KNOWN-incompatible send can't be masked by `.notReady`; fail-OPEN on an unknown target
        // (nil model/api ⇒ isSupported == true ⇒ proceed exactly as today). Lives here, above the
        // coordinator — PumpTransactionCoordinator is untouched (D-05).
        if let deviceError = deviceSupportError(for: message) { throw deviceError }
        // CC-06 (REMED-15.5): refuse — do NOT emit — a model-restricted message (GENERALIZED, 15.5-03,
        // S-B: the full model-restricted set minus the SendGateBootstrapAllowlist) whose target is
        // UNIDENTIFIED-OR-UNTRUSTED. Checked STRICTLY AFTER `deviceSupportError`
        // (that gate's fail-open-on-unknown contract is unchanged) and BEFORE the CX-T-10 disconnecting
        // guard, so a refusal here stays pre-write and determinate — never masked by `.notReady` — and
        // fails open on an unrestricted message or a trusted-known target.
        if let identityError = identityGateError(for: message) { throw identityError }
        // CX-T-10: refuse during the `disconnect()` → `didDisconnectPeripheral` gap. `disconnect()` sets
        // `intentionalDisconnect` synchronously but the link teardown (`cancelPeripheralConnection`) and the
        // resulting `state`/`peripheral`/`characteristics` reset are async — without this guard, a send
        // issued in that window would sail through the `state == .ready` check below on a link CoreBluetooth
        // is already tearing down. Checked BEFORE readiness, same precedence as `authorizationError`/
        // `deviceSupportError` above, and mirrors the `!intentionalDisconnect` guards already used elsewhere
        // in this class (`didDiscover`, `reconnectTick`, `startReconnectWatchdog`, …).
        if intentionalDisconnect { throw ClientError.disconnecting }
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
    /// - Parameter serialized: caller opt-in for the R3-D at-most-one-in-flight delivery lane. CX-T-06:
    ///   this is OR'd with `message.props.modifiesInsulinDelivery`, never just trusted — a delivery-class
    ///   message is serialized BY CONSTRUCTION even if a caller forgets (or a future call site is added
    ///   without) the opt-in, so "is this a delivery command" has exactly one source of truth
    ///   (`MessageProps.modifiesInsulinDelivery`) instead of two that can drift apart.
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
        let effectiveSerialized = serialized || message.props.modifiesInsulinDelivery
        return try await transactions.perform(
            expectedResponseOn: characteristic, opCode: expectedOpCode, deadline: deadline,
            serialized: effectiveSerialized
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
        // D-08: clear the identified device context so a reconnected/relaunched central re-identifies
        // before the device/API send gate can refuse anything — fail-OPEN across every link change.
        connectedPumpModel = nil
        negotiatedApiVersion = nil
        // CC-06 (REMED-15.5): clear the trust signal alongside the model so a reconnect starts UNTRUSTED
        // until a TRUSTED source (BLE-name detection, or 15.5-02's persisted reapplication) re-establishes
        // it — a stale `identityTrusted == true` must never survive a link change.
        identityTrusted = false
        // debug pump-background-disconnect (H1): every link change resolves any inline background-safe
        // connect (a drop re-sets it below; a failed-connect / restore / power-off leaves it clear so the
        // ladder escalates normally). Consistent with resetting write policy/correlation/device context here.
        inlineConnectPending = false
        // R2-11 defect 3: every link change ends any in-flight establishment, so its watchdog must not
        // outlive the attempt (it would otherwise fire into the NEXT establishment). Cancel here — this is
        // the fail-closed choke point every disconnect / failed-connect / restore / power-off routes through.
        cancelEstablishmentWatchdog()
        if resumePending { transactions.failAll(.connectionLost) }
    }

    // MARK: - Helpers

    // The class is @MainActor; the CB delegate methods (nonisolated) hop here via
    // assumeIsolated, so this runs on the main actor and can call the @MainActor delegate.
    private func notify(_ block: (PumpBLEClientDelegate) -> Void) {
        if let d = delegate { block(d) }
    }

    /// CC-03 (kit half): decode + typed-dispatch + reference-backed clear of the qualifying-events
    /// bitmap. Extracted out of `didUpdateValueFor` so it is unit-testable via an injected `clear`
    /// closure — a macOS test host cannot construct a real `CBPeripheral`/`CBCharacteristic` (TCC-
    /// aborted at scan; see the class note). STRICTLY ADDITIVE: this is the only new dispatch this
    /// phase adds; the reassembler -> `transactions.ingest` -> `didReceiveFrame` path it is called
    /// alongside stays byte-identical.
    ///
    /// - An empty decoded bitmap (all-zero, or an undersized buffer) dispatches NOTHING and clears
    ///   NOTHING, mirroring upstream's `if (!rawEvents.isEmpty())` clear gate.
    /// - A non-empty bitmap always dispatches the typed event via the additive delegate method.
    /// - The reference-backed clear (`[0,0,0,0]` `.withResponse` to `.qualifyingEvents`, per
    ///   `TandemBluetoothHandler.clearQualifyingEvents`) fires ONLY when no delivery-class
    ///   (`serialized`) transaction is in flight (delivery-transaction-safety guard, freeze-
    ///   reconciliation note). If one IS in flight, the clear is DEFERRED — fire-and-forget, no
    ///   retry, matching upstream: the next non-empty bitmap clears again.
    func handleQualifyingEventsFrame(_ frame: [UInt8], clear: () -> Void) {
        let events = QualifyingEvent.decode(frame)
        guard !events.isEmpty else { return }
        notify { $0.pumpClient(self, didReceiveQualifyingEvent: events) }
        guard !transactions.hasSerializedInFlight else { return }
        clear()
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
                    // C1-02 (faBolus Phase 13): this branch re-issues `central.connect` directly, bypassing
                    // `connect(_:)` — which is the ONLY other fresh-establishment entry point and is the one
                    // that arms `armEstablishmentWatchdog()`. Without arming it here too, a BT-power-on
                    // resume whose establishment stalls (pre-`.ready`) has no bound: it can strand
                    // `.connecting` forever, unlike every other establishment path.
                    armEstablishmentWatchdog()
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
            // C1-02 (faBolus Phase 13): a restored-connected peripheral is a KNOWN target — set
            // `reconnectTargetId` so a subsequent establishment-watchdog timeout (below) enters the
            // throttled reconnect ladder (eventually reaching `.reconnectExhausted`, which alarms) instead
            // of dead-ending at an un-alarmed `.disconnected` (the `reconnectTargetId == nil` "first-pair"
            // branch in `establishmentTimedOut()`). Mirrors what `connect(_:)` already does for a fresh
            // establishment.
            reconnectTargetId = p.identifier
            state = .discovering
            p.discoverServices([pumpUUID])
            // C1-02: `connect(_:)` arms this bound on every fresh establishment; `willRestoreState` adopts a
            // restored-connected peripheral and enters `.discovering` the SAME way but previously never
            // armed it — a stalled restoration discovery could strand `.discovering` forever with no
            // recovery. Cancelled at `.ready` (`maybeBecomeReady`) exactly like any other establishment.
            armEstablishmentWatchdog()
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                           advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            // R2-11 defect 2: a discovery that lands AFTER a user cancel must be rejected outright — both
            // the auto-connect and the delegate-notify below. Without this, a late first-pair discovery
            // still auto-connected past a Cancel (and `disconnect()` now also `stopScan()`s to make late
            // discoveries rare, but a callback already in flight can still arrive).
            guard !intentionalDisconnect else { return }
            // Watchdog rescan fallback: if this is the peripheral we're trying to recover, reconnect
            // to it directly rather than waiting for the app to choose again.
            if state != .ready, peripheral.identifier == reconnectTargetId {
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
            inlineConnectPending = false   // debug pump-background-disconnect: the pending connect completed
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
            // debug pump-background-disconnect (H1): capture whether the link had HELD `.ready` long enough
            // to trust as a stable connection, BEFORE `consumeReadyStabilityAndMaybeReset()` clears the
            // `readySince` stamp. This gates the inline background-safe reconnect below (a genuine stable-link
            // drop recovers immediately; a sub-window flap does NOT get a zero-delay connect → throttle intact).
            let heldReadyStably = readySince.map {
                Self.readyHeldLongEnoughToResetLadder(heldFor: Date().timeIntervalSince($0))
            } ?? false
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
            // Auto-reconnect on an unintended drop (e.g. out of range, or a background idle/supervision-timeout
            // drop). Go straight to .connecting (skip a .disconnected flicker) so the UI shows "reconnecting".
            // debug pump-background-disconnect (H1 root): for a GENUINE stable-link drop we now re-issue ONE
            // background-safe `central.connect()` INLINE, right here — a pending CB connect has no timeout and
            // does not poll, so CoreBluetooth completes it automatically when the pump returns, in the
            // foreground OR while the app is suspended (battery-neutral). This is the fix for "drops in the
            // background, only reconnects when reopened": the main-RunLoop reconnect Timer freezes on suspend,
            // so it could never ISSUE the connect in the background. A sub-window FLAP is deliberately NOT
            // inline-connected (`planUnintendedDropRecovery` gates on `heldReadyStably`): a zero-delay connect
            // on every flap drop would recover faster than the ladder tick and defeat the pairing-window
            // throttle (`.planning/debug/pump-pairing-loop.md`) — the flap is left to the throttled ladder,
            // which still escalates to `.reconnectExhausted`. Either way the ladder is armed as
            // backoff/ESCALATION (recovering a stalled/lost handle) and, via `inlineConnectPending`, does NOT
            // stack a second concurrent connect on its first tick. `reconnectAttempts` is never reset here.
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
                    if planUnintendedDropRecovery(heldReadyStably: heldReadyStably) {
                        central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
                    }
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
        cancelScanTimeout()             // B3b: no scan in flight once ready
        cancelEstablishmentWatchdog()   // R2-11 defect 3: establishment succeeded — hand off to the app-side
                                        // post-`.ready` pairing watchdog (FB-4 / R2-01); no pre-`.ready` deadline left standing
        readySince = Date()         // starts the stability window `consumeReadyStabilityAndMaybeReset` checks
        state = .ready
        notify { $0.pumpClientDidBecomeReady(self) }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated {
            handleNotificationStateUpdate(
                mapped: Characteristic.of(uuid: characteristic.uuid.uuidValue),
                isNotifying: characteristic.isNotifying,
                error: error
            )
        }
    }

    /// Core logic for `didUpdateNotificationStateFor`, extracted (internal, not private) so it is
    /// unit-testable without a real `CBCharacteristic` — the real delegate method above decodes the CB
    /// types into plain values and forwards; this does no CoreBluetooth work itself. Same testability
    /// pattern already used for `handleQualifyingEventsFrame`.
    ///
    /// A failed subscription means a response channel isn't live → fail closed (PX-04/PX-08): reset the
    /// write policy and resume any pending transaction, and surface the error — unchanged from before.
    ///
    /// CX-T-05 (post-ready notification loss): when `isNotifying` flips false with NO CB error while
    /// `state == .ready`, the response channel this subscription guarded just went dark on an otherwise-
    /// healthy-looking link. `maybeBecomeReady()` below is a no-op once `.ready` (its own guard), so
    /// without an explicit revoke this loss would be silently absorbed — the link would keep reporting
    /// `.ready` to every caller even though its subscription-ready barrier (PX-08) no longer holds.
    func handleNotificationStateUpdate(mapped: Characteristic?, isNotifying: Bool, error: Error?) {
        if let error {
            failClosed(resumePending: true)
            notify { $0.pumpClient(self, didError: error) }
            return
        }
        guard let mapped else { return }
        if isNotifying {
            confirmedNotifying.insert(mapped)
        } else {
            confirmedNotifying.remove(mapped)
            if state == .ready { revokeReadiness() }
        }
        maybeBecomeReady()
    }

    /// CX-T-05: revoke `.ready` on a post-ready notification loss. Transitions to `.discovering` — the
    /// same state used while the PX-08 subscription-ready barrier is still being satisfied during initial
    /// establishment — so `maybeBecomeReady()` can re-declare `.ready` once the subscription is reconfirmed,
    /// and any caller gating a send on `state == .ready` correctly sees the link as not-yet-ready in the
    /// interim, instead of a stale `.ready` masking the lost channel. Does not touch `characteristics` or
    /// tear down the link — only the notify barrier was lost, not the whole connection; a genuine
    /// disconnect is handled separately by `failClosed`/`didDisconnectPeripheral`.
    private func revokeReadiness() {
        state = .discovering
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
                    // CC-03 (kit half), STRICTLY ADDITIVE: the qualifying-events characteristic
                    // carries a raw little-endian 4-byte bitmap (no opcode/txId/len/crc framing,
                    // per upstream QualifyingEvent.fromRawBtBytes) — decode + typed-dispatch + a
                    // reference-backed clear write, alongside (not instead of) the opaque
                    // didReceiveFrame delivery above.
                    if mapped == .qualifyingEvents {
                        handleQualifyingEventsFrame(frame) { [self] in
                            // `self.peripheral` (not the `peripheral:` parameter of this delegate
                            // callback, which is non-optional and shadows it in this scope).
                            guard let target = self.peripheral,
                                  let cbChar = characteristics[.qualifyingEvents] else { return }
                            target.writeValue(Data([0, 0, 0, 0]), for: cbChar, type: .withResponse)
                        }
                    }
                }
            } else {
                reassembly[mapped] = reassembler
            }
        }
    }

    public nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                                       error: Error?) {
        MainActor.assumeIsolated { handleWriteResult(error: error) }
    }

    /// Core logic for `didWriteValueFor`, extracted (internal, not private) so it is unit-testable without
    /// a real `CBPeripheral`/`CBCharacteristic` — same pattern as `handleNotificationStateUpdate`. Neither
    /// the real delegate method's `characteristic` nor `peripheral` parameter was ever used in this body
    /// (before or after this fix), so no CB value needs to cross the boundary.
    ///
    /// CX-T-05: a failed write orphans any transaction awaiting THAT write's correlated response — the
    /// reply it was en route to unlock never arrives — so this must fail closed (PX-04/PX-08) exactly like
    /// its two correct siblings (`didUpdateNotificationStateFor`/`didUpdateValueFor`'s error branches),
    /// instead of only notifying and leaving the write policy elevated / the transaction hanging.
    func handleWriteResult(error: Error?) {
        if let error {
            failClosed(resumePending: true)
            notify { $0.pumpClient(self, didError: error) }
        }
    }
}

private extension CBUUID {
    /// CBUUIDs from the pump are 128-bit; convert to Foundation UUID for our enum lookup.
    var uuidValue: UUID { UUID(uuidString: uuidString) ?? UUID() }
}
