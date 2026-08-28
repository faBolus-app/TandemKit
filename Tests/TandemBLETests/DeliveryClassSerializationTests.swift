import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// CX-T-06 (phase 14 delivery-safety remediation). `sendAwaitingResponse`'s `serialized` parameter was a
/// caller-forgettable, default-`false` opt-in into the R3-D at-most-one-delivery-in-flight lane — nothing
/// tied it to `MessageProps.modifiesInsulinDelivery`, the SINGLE existing source of truth for "is this a
/// delivery command." A future/careless call site could pass `serialized: false` for a genuine bolus/
/// delivery message and it would be accepted, defeating the "a bolus is never pipelined" invariant
/// `PumpTransactionCoordinator` documents.
///
/// The busy-gate in `PumpTransactionCoordinator.perform` is checked BEFORE any bytes are written (R3-D),
/// using ONLY the caller-passed `serialized` flag — so it is directly observable without a live connection:
/// pre-occupy the serialized lane with an unrelated in-flight transaction, then assert that a delivery-class
/// message passed with `serialized: false` still hits `.busy` (because the fix ORs in
/// `message.props.modifiesInsulinDelivery`), while a non-delivery message with the same caller flag does
/// NOT (it falls through to `send()`, which throws `.notReady` — no live connection in a unit test).
@Suite struct DeliveryClassSerializationTests {

    final class FakeCentral: PumpCentral {
        var state: CBManagerState { .poweredOn }
        func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {}
        func stopScan() {}
        func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {}
        func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
        func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { [] }
        func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    }

    /// Drive `perform` to the point its pending transaction is registered — mirrors
    /// `PumpTransactionCoordinatorTests.launchAndRegister`, extended with a `serialized` param (each suite
    /// keeps its own copy per the existing convention).
    @MainActor private func launchAndRegister(
        _ coord: PumpTransactionCoordinator, on ch: Characteristic, opCode: UInt8,
        serialized: Bool, deadline: TimeInterval = 5, txId: UInt8 = 7
    ) async -> Task<[UInt8], Error> {
        let before = coord.inFlightCount
        let task = Task { @MainActor in
            try await coord.perform(
                expectedResponseOn: ch, opCode: opCode, deadline: deadline,
                serialized: serialized
            ) { txId }
        }
        while coord.inFlightCount == before { await Task.yield() }
        return task
    }

    /// A delivery-class message (`props.modifiesInsulinDelivery == true`) is serialized EVEN when the
    /// caller passes `serialized: false` — proven by the busy-gate firing against an unrelated occupying
    /// serialized transaction, which only happens if the EFFECTIVE serialized flag was true.
    @MainActor @Test func deliveryClassMessageIsSerializedRegardlessOfCallerFlag() async {
        let client = PumpBLEClient(central: FakeCentral())
        let bolus = InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1)
        #expect(bolus.props.modifiesInsulinDelivery, "sanity: InitiateBolusRequest IS delivery-class")

        let occupying = await launchAndRegister(
            client.transactions, on: .control, opCode: 0x03,
            serialized: true)
        await #expect(throws: PumpTransactionCoordinator.TxError.busy) {
            try await client.sendAwaitingResponse(bolus, deadline: 1, serialized: false)
        }

        client.transactions.failAll(.cancelled)
        _ = await occupying.result
    }

    /// A non-delivery message with the caller's `serialized: false` stays UNSERIALIZED — it must NOT hit
    /// the busy gate even with a serialized transaction already occupying the lane; it falls through to
    /// `send()`, which throws `.notReady` (no live connection), never `.busy`.
    @MainActor @Test func nonDeliveryMessageStaysUnserializedWhenCallerSaysFalse() async {
        let client = PumpBLEClient(central: FakeCentral())
        let read = ControlIQIOBRequest()
        #expect(!read.props.modifiesInsulinDelivery, "sanity: a read is NOT delivery-class")

        let occupying = await launchAndRegister(
            client.transactions, on: .control, opCode: 0x03,
            serialized: true)
        await #expect(throws: PumpBLEClient.ClientError.notReady) {
            try await client.sendAwaitingResponse(read, deadline: 1, serialized: false)
        }

        client.transactions.failAll(.cancelled)
        _ = await occupying.result
    }

    /// A caller that explicitly passes `serialized: true` for a non-delivery message is still honored (the
    /// fix ORs in `modifiesInsulinDelivery`, it never drops the caller's own opt-in).
    @MainActor @Test func callerSerializedOverrideIsStillHonoredForNonDelivery() async {
        let client = PumpBLEClient(central: FakeCentral())
        let read = ControlIQIOBRequest()

        let occupying = await launchAndRegister(
            client.transactions, on: .control, opCode: 0x03,
            serialized: true)
        await #expect(throws: PumpTransactionCoordinator.TxError.busy) {
            try await client.sendAwaitingResponse(read, deadline: 1, serialized: true)
        }

        client.transactions.failAll(.cancelled)
        _ = await occupying.result
    }
}
