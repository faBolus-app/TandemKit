import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// CX-T-10 (phase 14 delivery-safety remediation). `disconnect()` sets `intentionalDisconnect` synchronously
/// but the actual link teardown (`central.cancelPeripheralConnection`) and the resulting
/// `state`/`peripheral`/`characteristics` reset are async, arriving later via `didDisconnectPeripheral`.
/// Before this fix, `disconnect()` only published `state = .disconnected` when there was no live
/// `peripheral` (a first-pair scan); with a live peripheral, `state` stayed whatever it was — often
/// `.ready` — until the delegate callback caught up, so a straggler `send()` issued in that window would
/// sail through `send()`'s `state == .ready` readiness guard onto a link CoreBluetooth was already tearing
/// down.
///
/// The fix is defense-in-depth: (a) `disconnect()` now publishes `state = .disconnected` SYNCHRONOUSLY,
/// unconditionally, before the async teardown; (b) `send()` ALSO guards directly on `intentionalDisconnect`
/// (mirroring the `!intentionalDisconnect` guards already used elsewhere in the class), refusing with a
/// DISTINCT `ClientError.disconnecting` — not the reused `.notReady` — so the refusal is observable in a
/// unit test without a live `CBPeripheral`/`CBCharacteristic` (the same reason `.unsupportedOnDevice` is
/// its own case rather than `.notReady`, per `SendGateBoundaryTests`'s doc comment). A real end-to-end
/// "send actually proceeds on a `.ready` + live-peripheral link" scenario needs hardware (TCC-aborted at
/// scan on a macOS test host — see the class doc); (a) is proven directly via the reachable no-peripheral
/// branch, and (b) proves the specific hazard named in the plan's truths — a stale-`.ready`-looking send
/// during the gap is refused, not silently emitted.
@Suite struct DisconnectRaceGuardTests {

    final class FakeCentral: PumpCentral {
        var stateValue: CBManagerState = .poweredOn
        var state: CBManagerState { stateValue }
        var scanCount = 0, connectCount = 0, cancelCount = 0
        var retrieveResult: [CBPeripheral] = []
        func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) { scanCount += 1 }
        func stopScan() {}
        func connect(_ peripheral: CBPeripheral, options: [String: Any]?) { connectCount += 1 }
        func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { retrieveResult }
        func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { retrieveResult }
        func cancelPeripheralConnection(_ peripheral: CBPeripheral) { cancelCount += 1 }
    }

    // MARK: - (a) disconnect() publishes state synchronously

    /// `disconnect()` must leave `state == .disconnected` IMMEDIATELY — not deferred to a later async
    /// callback — even from a non-terminal in-flight state (here `.scanning`, reached via
    /// `connectKnownPeripheral` with no resolvable peripheral, the same setup `BackgroundReconnectTests`
    /// uses). A subsequent readiness check right after `disconnect()` returns must be honest.
    @MainActor @Test func disconnectPublishesTerminalStateSynchronously() {
        let client = PumpBLEClient(central: FakeCentral())
        client.connectKnownPeripheral(identifier: UUID())
        #expect(client.state == .scanning)

        client.disconnect()

        #expect(client.state == .disconnected,
                "disconnect() must transition state synchronously, not leave it stale until didDisconnectPeripheral")
    }

    /// `disconnect()` sets `intentionalDisconnect` synchronously too (pre-existing, pinned here alongside
    /// the state fix so the two are verified together — both are read by `send()`'s guard).
    @MainActor @Test func disconnectSetsIntentionalDisconnectSynchronously() {
        let client = PumpBLEClient(central: FakeCentral())
        #expect(!client.intentionalDisconnectForTesting)
        client.disconnect()
        #expect(client.intentionalDisconnectForTesting)
    }

    // MARK: - (b) send() refuses during the disconnect()→didDisconnect gap

    /// NEGATIVE PATH: once `disconnect()` has set `intentionalDisconnect`, `send()` must refuse with the
    /// DISTINCT `.disconnecting` error — checked BEFORE the readiness guard, so the refusal is not masked
    /// by (and not confusable with) a plain `.notReady`.
    @MainActor @Test func sendRefusesDuringDisconnectGap() {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowBenignControl   // clear the write-policy interlock first
        client.intentionalDisconnectForTesting = true

        #expect(throws: PumpBLEClient.ClientError.disconnecting) {
            try client.send(PlaySoundRequest())
        }
    }

    /// Calling `disconnect()` itself (not just the test seam) puts `send()` into the same refusal state —
    /// the end-to-end path a real caller hits.
    @MainActor @Test func sendRefusesAfterRealDisconnectCall() {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowBenignControl
        client.disconnect()

        #expect(throws: PumpBLEClient.ClientError.disconnecting) {
            try client.send(PlaySoundRequest())
        }
    }

    /// Outside the disconnect gap (`intentionalDisconnect == false`), `send()` is unaffected by this guard
    /// — it falls through to the pre-existing readiness guard and throws the ORIGINAL `.notReady` (no live
    /// connection in a unit test), never `.disconnecting`. Proves the new guard is additive, not a
    /// blanket refusal.
    @MainActor @Test func sendOutsideDisconnectGapIsUnaffected() {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowBenignControl

        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(PlaySoundRequest())
        }
    }

    /// The write-policy interlock still precedes the disconnect guard (mirrors
    /// `SendGateBoundaryTests.writePolicyInterlockStillPrecedesGate`): a blocked message under the default
    /// `.readOnly` policy is refused with `.writeBlocked` even mid-disconnect, not silently reclassified as
    /// `.disconnecting` — authorization is still checked first.
    @MainActor @Test func writePolicyInterlockStillPrecedesDisconnectGuard() {
        let client = PumpBLEClient(central: FakeCentral())   // default .readOnly
        client.intentionalDisconnectForTesting = true

        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: PlaySoundRequest().opCode)) {
            try client.send(PlaySoundRequest())
        }
    }
}
