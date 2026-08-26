import CoreBluetooth
@testable import TandemBLE

/// An inert `PumpCentral` for pure-logic unit tests — see `PumpBLEClient.forUnitTest()`.
///
/// It exists so those suites never reach the bare `PumpBLEClient()` initializer, which builds a REAL
/// `CBCentralManager`. Under the `swift test` host process (Apple's `swiftpm-testing-helper`, which
/// carries no `NSBluetoothAlwaysUsageDescription` in its Info.plist), CoreBluetooth's asynchronous
/// authorization check aborts the WHOLE process with SIGABRT — a TCC privacy violation — at a
/// nondeterministic point after the manager is constructed.
///
/// That is the intermittent full-suite crash: a filtered run that excludes the BLE suites never
/// constructs a central, so it never reproduces; the long combined run lives long enough for the async
/// abort to land, killing an unrelated test mid-flight (the "random point" symptom). Mirrors the
/// `FakeCentral` seam already used by `ScanTimeoutTests` / `BackgroundReconnectTests`, but reports
/// `.poweredOff` so nothing ever scans or connects even if a future test reaches the lifecycle through it.
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
    /// A client for pure-logic unit tests (write-policy gate, device/API send gate, correlation-mode
    /// allowlist, qualifying-events decode) that never scan or connect — backed by an `InertCentral`
    /// instead of a real `CBCentralManager`, so the test host is never TCC-aborted (see `InertCentral`).
    ///
    /// Unit tests MUST use this instead of the bare initializer; the `NoBareCentralGuardTests` guard
    /// enforces it. The real initializer is reserved for the Info.plist-carrying bench harness and the
    /// hardware-gated live suite, both of which genuinely drive CoreBluetooth.
    @MainActor static func forUnitTest() -> PumpBLEClient { PumpBLEClient(central: InertCentral()) }
}
