import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// A delivery-class message (`props.modifiesInsulinDelivery`) is serialized even when the caller
/// passes `serialized: false`, so a bolus can never be pipelined. The busy-gate in `perform` is
/// checked before any bytes are written, using the effective serialized flag.
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
            try await coord.perform(expectedResponseOn: ch, opCode: opCode, deadline: deadline,
                                    serialized: serialized) { txId }
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

        let occupying = await launchAndRegister(client.transactions, on: .control, opCode: 0x03,
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

        let occupying = await launchAndRegister(client.transactions, on: .control, opCode: 0x03,
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

        let occupying = await launchAndRegister(client.transactions, on: .control, opCode: 0x03,
                                                 serialized: true)
        await #expect(throws: PumpTransactionCoordinator.TxError.busy) {
            try await client.sendAwaitingResponse(read, deadline: 1, serialized: true)
        }

        client.transactions.failAll(.cancelled)
        _ = await occupying.result
    }
}
