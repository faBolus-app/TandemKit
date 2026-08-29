import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// `disconnect()` publishes `state = .disconnected` synchronously before async teardown, and `send()`
/// also refuses on `intentionalDisconnect` with `.disconnecting` (not reused `.notReady`) so a
/// straggler send cannot ride a stale `.ready` onto a link CoreBluetooth is already tearing down.
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

        #expect(
            client.state == .disconnected,
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

    /// Once `disconnect()` has set `intentionalDisconnect`, `send()` must refuse with the
    /// distinct `.disconnecting` error — checked before the readiness guard, so the refusal is not masked
    /// by (and not confusable with) a plain `.notReady`.
    @MainActor @Test func sendRefusesDuringDisconnectGap() {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowBenignControl  // clear the write-policy interlock first
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
        let client = PumpBLEClient(central: FakeCentral())  // default .readOnly
        client.intentionalDisconnectForTesting = true

        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: PlaySoundRequest().opCode)) {
            try client.send(PlaySoundRequest())
        }
    }
}
