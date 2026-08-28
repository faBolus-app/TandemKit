import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// An unintended drop after a stable `.ready` issues one background-safe `central.connect()` inline
/// (a pending CB connect has no timeout and completes while the app is suspended). A sub-window
/// flap does not: that would skip the 5 s reconnect ladder and never reach `.reconnectExhausted`.
/// The `inlineConnectPending` flag demotes the ladder's first tick so it does not stack a second connect.
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

    // MARK: - Throttle preservation

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
