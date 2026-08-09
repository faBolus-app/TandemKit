import Testing
import Foundation
import CoreBluetooth
@testable import PumpX2BLE

/// B3(b) / §5.2.4 — the BLE scan-timeout + cold-launch retrieve-vs-scan, branch-tested via an injected
/// fake `PumpCentral` (a macOS test host is TCC-aborted at a real scan, so this is the only way to exercise
/// the lifecycle in `swift test`). Pins the load-bearing safety property: a scan that never discovers the
/// pump escalates to the reconnect recovery ladder WITHOUT tearing down (no `stopScan`, no
/// `cancelPeripheralConnection`) — teardown/rebuild is the very thing that causes the stuck-scanning state.
/// Touches no message codec, so byte-parity is unaffected.
@MainActor
@Suite struct ScanTimeoutTests {

    /// Records the CBCentralManager calls `PumpBLEClient` makes, and lets a test drive `state` +
    /// `retrieve*` results — no CoreBluetooth, no hardware.
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

    @Test func coldLaunchRetrieveEmptyFallsBackToScan() {
        let fake = FakeCentral()                       // powered on, no known handle
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        #expect(fake.scanCount == 1)                   // C1: retrieve empty ⇒ scan
        #expect(client.state == .scanning)
        #expect(fake.connectCount == 0)
        client.disconnect()
    }

    @Test func connectKnownPeripheralDefersWhenBluetoothOff() {
        let fake = FakeCentral(); fake.stateValue = .poweredOff
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        #expect(fake.scanCount == 0)                   // deferred until poweredOn (pendingRetrieveId)
        #expect(fake.connectCount == 0)
        client.disconnect()
    }

    @Test func scanTimeoutEscalatesToRecoveryWithoutTeardown() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())   // ⇒ .scanning, reconnectTargetId set
        #expect(client.state == .scanning)
        let scansBefore = fake.scanCount
        client.scanTimedOut()                                // fire the timeout directly (no 30 s wait)
        #expect(client.reconnectWatchdogArmedForTesting)     // escalated to the recovery ladder…
        // …§5.2.4 invariant: WITHOUT teardown — the pending scan/connect is left in place.
        #expect(fake.stopScanCount == 0)
        #expect(fake.cancelCount == 0)
        #expect(fake.scanCount == scansBefore)               // and no synchronous re-scan
        client.disconnect()
    }

    @Test func scanTimeoutIsInertForAPairingScanWithNoTarget() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.startScan()                                   // fresh pairing scan — no reconnectTargetId
        #expect(client.state == .scanning)
        client.scanTimedOut()
        #expect(!client.reconnectWatchdogArmedForTesting)    // left to run exactly as before
        #expect(fake.stopScanCount == 0)
        client.disconnect()
    }
}
