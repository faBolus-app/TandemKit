import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// Debug session `pump-background-disconnect` (owner-authorized 2026-08-20, re-scoped pass). Pins the
/// KIT half of the two-part root cause: a pump BLE link that drops while the app is BACKGROUNDED was never
/// recovered until the app was reopened, because the sole post-drop `central.connect()` re-issue lived in
/// `reconnectTick()` on a main-RunLoop `Timer` that freezes once the app suspends (H1).
///
/// The fix issues ONE background-safe `central.connect()` INLINE on an unintended drop (a pending CB connect
/// has no timeout and does not poll, so CoreBluetooth completes it while the app is suspended — battery-
/// neutral). The HIGHEST-BUG-RISK part is the reconciliation of that inline connect against the existing
/// throttled reconnect ladder (the pump-pairing-loop flap throttle, `.planning/debug/pump-pairing-loop.md`):
///
///   1. A NAIVE inline connect on EVERY drop would reintroduce that regression — a zero-delay connect that
///      recovers a flapping peer faster than the 5 s ladder tick means `reconnectAttempts` never climbs and
///      `.reconnectExhausted` never fires (an unthrottled accept-then-drop loop). So the inline connect is
///      GATED on the drop following a `>= readyStabilityWindow` stable `.ready` (the SAME signal
///      `consumeReadyStabilityAndMaybeReset` already trusts): a genuine stable-link drop (e.g. a background
///      idle/supervision-timeout drop) inline-connects; a sub-window flap does NOT, and is left to the
///      throttled ladder which still escalates to `.reconnectExhausted`.
///   2. The `inlineConnectPending` flag demotes the ladder's FIRST tick to pure backoff so it does NOT
///      stack a second concurrent connect; the drop path never resets `reconnectAttempts`/`reconnectExhausted`.
///
/// Like `ReconnectThrottleTests`/`ScanTimeoutTests`, this drives the internal-not-private state machine with
/// an injected `PumpCentral` fake — `didDisconnectPeripheral` itself takes a live `CBPeripheral` (no public
/// initializer; a macOS test host is TCC-aborted at a real connect), and the single `central.connect(peripheral,…)`
/// on that real handle is the only part that needs hardware (bench/device-verified). `planUnintendedDropRecovery`
/// factors out the reconcilable core so the throttle-preservation + non-stacking logic is unit-testable here.
@MainActor
@Suite struct BackgroundReconnectTests {

    /// Same fake as the sibling suites (each keeps its own copy — they are private to their suite scope):
    /// records the CBCentralManager calls and lets a test drive `state` + `retrieve*` results, no hardware.
    final class FakeCentral: PumpCentral {
        var stateValue: CBManagerState = .poweredOn
        var state: CBManagerState { stateValue }
        var scanCount = 0, stopScanCount = 0, connectCount = 0, cancelCount = 0
        var retrieveResult: [CBPeripheral] = []
        func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) { scanCount += 1 }
        func stopScan() { stopScanCount += 1 }
        func connect(_ peripheral: CBPeripheral, options: [String: Any]?) { connectCount += 1 }
        func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { retrieveResult }
        func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { retrieveResult }
        func cancelPeripheralConnection(_ peripheral: CBPeripheral) { cancelCount += 1 }
    }

    /// Records `didError` so a test can assert `.reconnectLoopDetected` was surfaced at exhaustion.
    final class RecordingDelegate: PumpBLEClientDelegate {
        var errors: [PumpBLEClient.ClientError] = []
        func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {}
        func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {}
        func pumpClientDidBecomeReady(_ client: PumpBLEClient) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {}
        func pumpClient(_ client: PumpBLEClient, didError error: Error) {
            if let e = error as? PumpBLEClient.ClientError { errors.append(e) }
        }
    }

    // MARK: - Throttle preservation (the reconciliation, rail 2)

    /// A GENUINE stable-then-dropped link (held `.ready` >= the stability window) plans an inline
    /// background-safe connect AND arms the ladder — but must NOT reset the flap-throttle counters.
    @Test func stableDropArmsInlineConnectWithoutResettingThrottle() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        client.reconnectTick(); client.reconnectTick(); client.reconnectTick()   // climb to step 3
        #expect(client.reconnectAttemptsForTesting == 3)

        let issued = client.planUnintendedDropRecovery(heldReadyStably: true)
        #expect(issued, "a stable-link drop must establish ONE inline background-safe pending connect")
        #expect(client.inlineConnectPendingForTesting)
        #expect(client.reconnectAttemptsForTesting == 3, "the drop path must NOT reset the flap throttle")
        #expect(client.state != .reconnectExhausted)
        client.disconnect()
    }

    /// A sub-window FLAP (the link dropped again before it had held `.ready` for the stability window) must
    /// get NO zero-delay inline connect — that is exactly the pump-pairing-loop regression. The ladder still
    /// arms, so the flap is recovered on the THROTTLED path and can still escalate to `.reconnectExhausted`.
    @Test func subWindowFlapGetsNoInlineConnectButStillThrottles() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()

        let issued = client.planUnintendedDropRecovery(heldReadyStably: false)
        #expect(!issued, "a <window flap must NOT get a zero-delay inline connect (throttle intact)")
        #expect(!client.inlineConnectPendingForTesting)
        #expect(client.reconnectWatchdogArmedForTesting, "the throttled ladder still owns flap recovery")
        client.disconnect()
    }

    // MARK: - Non-stacking (the inline connect vs the Timer ladder)

    /// The FIRST ladder tick after an inline connect is pure BACKOFF: it consumes `inlineConnectPending` and
    /// does NOT stack a second concurrent connect (here, with no live handle, "would stack" == "would
    /// rescan"). The NEXT tick escalates normally — so escalation is only demoted for exactly one tick, the
    /// window CoreBluetooth needs to complete the already-pending inline connect.
    @Test func firstTickAfterInlineConnectIsPureBackoffThenEscalates() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())   // → .scanning
        client.scanTimedOut()                               // arm ladder at attempts=0
        let scansAfterArm = fake.scanCount

        client.planUnintendedDropRecovery(heldReadyStably: true)
        #expect(client.inlineConnectPendingForTesting)

        client.reconnectTick()                              // FIRST tick — pure backoff
        #expect(client.reconnectAttemptsForTesting == 1)
        #expect(!client.inlineConnectPendingForTesting, "the first tick consumes the pending flag")
        #expect(fake.scanCount == scansAfterArm, "must NOT stack a second connect/rescan on the first tick")
        #expect(client.reconnectWatchdogArmedForTesting)

        client.reconnectTick()                              // SECOND tick — escalation resumes
        #expect(client.reconnectAttemptsForTesting == 2)
        #expect(fake.scanCount == scansAfterArm + 1, "escalation (rescan) resumes once the flag is consumed")
        client.disconnect()
    }

    // MARK: - Terminal-state hygiene

    /// Exhaustion is still reachable after an inline-connect drop, and the pending flag is cleared when the
    /// ladder gives up (the still-pending connect is cancelled there, so nothing may claim it is pending).
    @Test func exhaustionStillReachedAndClearsInlinePending() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let delegate = RecordingDelegate(); client.delegate = delegate
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        client.planUnintendedDropRecovery(heldReadyStably: true)
        for _ in 1...(PumpBLEClient.maxReconnectAttemptsForTesting + 1) { client.reconnectTick() }
        #expect(client.state == .reconnectExhausted)
        #expect(!client.inlineConnectPendingForTesting, "exhaustion cancels the pending connect → flag clear")
        #expect(delegate.errors.contains(.reconnectLoopDetected))
        client.disconnect()
    }

    /// A fresh user-initiated connect (genuinely new intent) clears any inline-pending flag alongside the
    /// ladder reset — a stale pending marker can never leak into a brand-new connection attempt.
    @Test func freshConnectClearsInlinePending() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        client.planUnintendedDropRecovery(heldReadyStably: true)
        #expect(client.inlineConnectPendingForTesting)

        client.connectKnownPeripheral(identifier: UUID())   // fresh pairing/connect intent
        #expect(!client.inlineConnectPendingForTesting)
        #expect(client.reconnectAttemptsForTesting == 0)
        client.disconnect()
    }
}
