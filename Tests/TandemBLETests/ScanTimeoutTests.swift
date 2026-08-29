import Testing
import Foundation
import CoreBluetooth
@testable import TandemBLE

/// A scan that never discovers the pump escalates to the reconnect ladder without tearing down
/// (`stopScan` / `cancelPeripheralConnection` would leave a stuck-scanning state). Driven via an
/// injected fake `PumpCentral` because a macOS test host is TCC-aborted at a real scan.
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
        let fake = FakeCentral()  // powered on, no known handle
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        #expect(fake.scanCount == 1)  // retrieve empty ⇒ scan
        #expect(client.state == .scanning)
        #expect(fake.connectCount == 0)
        client.disconnect()
    }

    @Test func connectKnownPeripheralDefersWhenBluetoothOff() {
        let fake = FakeCentral()
        fake.stateValue = .poweredOff
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        #expect(fake.scanCount == 0)  // deferred until poweredOn (pendingRetrieveId)
        #expect(fake.connectCount == 0)
        client.disconnect()
    }

    @Test func scanTimeoutEscalatesToRecoveryWithoutTeardown() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())  // ⇒ .scanning, reconnectTargetId set
        #expect(client.state == .scanning)
        let scansBefore = fake.scanCount
        client.scanTimedOut()  // fire the timeout directly (no 30 s wait)
        #expect(client.reconnectWatchdogArmedForTesting)  // escalated to the recovery ladder…
        // Without teardown — the pending scan/connect is left in place.
        #expect(fake.stopScanCount == 0)
        #expect(fake.cancelCount == 0)
        #expect(fake.scanCount == scansBefore)  // and no synchronous re-scan
        client.disconnect()
    }

    /// A first-time pairing scan (no `reconnectTargetId`) must be bounded at timeout: stop the scan and
    /// publish a retryable terminal `.disconnected`, and must not be routed into the known-target reconnect
    /// ladder (there is no target to recover toward).
    @Test func firstPairScanTimeoutIsBounded() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.startScan()  // fresh pairing scan — no reconnectTargetId
        #expect(client.state == .scanning)
        client.scanTimedOut()
        #expect(fake.stopScanCount == 1)  // bounded: the scan is stopped…
        #expect(client.state == .disconnected)  // …and a retryable terminal is published
        #expect(!client.reconnectWatchdogArmedForTesting)  // NOT the known-target ladder
        client.disconnect()
    }

    /// A user cancel during a first-pair scan (before any discovery) must stop the scan and publish
    /// `.disconnected`, so a late discovery cannot still auto-connect.
    @Test func cancelBeforeDiscoveryStopsScanAndGoesDown() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.startScan()  // first-pair scan in flight, no peripheral
        #expect(client.state == .scanning)
        client.disconnect()
        #expect(fake.stopScanCount >= 1)  // radio quiesced → no late auto-connect
        #expect(client.state == .disconnected)  // first-pair cancel publishes the terminal
    }

    /// A cold/reconnect establishment that stalls before `.ready` must fail closed via the establishment
    /// watchdog: a known target lands on the throttled recovery ladder; a first-pair cold connect
    /// terminates at `.disconnected`. The watchdog is cleared so it cannot outlive its window.
    @Test func coldConnectEstablishmentWatchdogFailsClosed() {
        // KNOWN target → throttled recovery ladder (not a terminal).
        let fakeKnown = FakeCentral()
        let known = PumpBLEClient(central: fakeKnown)
        known.connectKnownPeripheral(identifier: UUID())  // known target set; empty retrieve ⇒ .scanning
        known.fireEstablishmentWatchdogForTesting()  // establishment stalls before .ready
        #expect(known.reconnectWatchdogArmedForTesting)  // KNOWN target ⇒ reconnect ladder
        #expect(!known.establishmentWatchdogArmedForTesting)  // watchdog cleared — no outliving/double-fire
        #expect(known.state != .ready)
        known.disconnect()

        // FIRST PAIR (no known target) → clean, retryable terminal.
        let fakeFirst = FakeCentral()
        let first = PumpBLEClient(central: fakeFirst)
        first.startScan()  // no reconnectTargetId
        first.fireEstablishmentWatchdogForTesting()
        #expect(first.state == .disconnected)  // first pair ⇒ terminal, not the ladder
        #expect(!first.reconnectWatchdogArmedForTesting)
        #expect(!first.establishmentWatchdogArmedForTesting)
        first.disconnect()
    }
}
