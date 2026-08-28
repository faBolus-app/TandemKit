import CoreBluetooth
@testable import TandemBLE

/// An inert `PumpCentral` for pure-logic unit tests — see `PumpBLEClient.forUnitTest()`.
/// The bare `PumpBLEClient()` initializer builds a real `CBCentralManager`; the `swift test` host
/// has no Bluetooth entitlement, so that construction TCC-aborts the whole process.
final class InertCentral: PumpCentral {
    var state: CBManagerState { .poweredOff }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {}
    func stopScan() {}
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {}
    func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
    func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { [] }
    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
}

extension PumpBLEClient {
    /// A client for pure-logic unit tests that never scans or connects — backed by an `InertCentral`
    /// instead of a real `CBCentralManager`, so the test host is never TCC-aborted.
    @MainActor static func forUnitTest() -> PumpBLEClient { PumpBLEClient(central: InertCentral()) }
}
