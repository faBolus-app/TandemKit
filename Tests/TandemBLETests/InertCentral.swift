import CoreBluetooth
@testable import TandemBLE

/// An inert `PumpCentral` for pure-logic unit tests — see `PumpBLEClient.forUnitTest()`.
/// The bare `PumpBLEClient()` initializer builds a real `CBCentralManager`. The `swift test` host
/// (Apple's `swiftpm-testing-helper`) carries no `NSBluetoothAlwaysUsageDescription`, so
/// CoreBluetooth's ASYNCHRONOUS authorization check aborts the whole process with SIGABRT — a TCC
/// privacy violation — at a NONDETERMINISTIC point after the manager is constructed.
///
/// That asynchrony is the whole diagnostic: it is why a filtered run excluding the BLE suites never
/// reproduces (no central is ever built), while the long combined run lives long enough for the abort
/// to land and kill an unrelated test mid-flight — the "crashes at a random point" symptom. Reports
/// `.poweredOff` so nothing scans or connects even if a future test reaches the lifecycle through it.
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
    ///
    /// Unit tests MUST use this instead of the bare initializer, and `NoBareCentralGuardTests`
    /// enforces it. The real initializer is reserved for the Info.plist-carrying bench harness and the
    /// hardware-gated live suite, which genuinely drive CoreBluetooth.
    @MainActor static func forUnitTest() -> PumpBLEClient { PumpBLEClient(central: InertCentral()) }
}
