import Testing
import Foundation
import CoreBluetooth
@testable import TandemBLE

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

    /// R2-11 defect 1: a first-time PAIRING scan (no `reconnectTargetId`) used to be INERT at timeout —
    /// `scanTimedOut()` early-returned, so the scan ran forever. It must now be BOUNDED: stop the scan and
    /// publish a retryable terminal `.disconnected`, and must NOT be routed into the known-target reconnect
    /// ladder (there is no target to recover toward). (Rewritten from the old
    /// `scanTimeoutIsInertForAPairingScanWithNoTarget`, which pinned the now-fixed inert behavior.)
    @Test func firstPairScanTimeoutIsBounded() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.startScan()                                   // fresh pairing scan — no reconnectTargetId
        #expect(client.state == .scanning)
        client.scanTimedOut()
        #expect(fake.stopScanCount == 1)                     // bounded: the scan is stopped…
        #expect(client.state == .disconnected)               // …and a retryable terminal is published
        #expect(!client.reconnectWatchdogArmedForTesting)    // NOT the known-target ladder
        client.disconnect()
    }

    /// R2-11 defect 2: a user cancel during a first-pair scan (before any discovery) must stop the scan and
    /// publish a terminal `.disconnected`. The old `disconnect()` never called `stopScan()` and, with no
    /// peripheral, never published `.disconnected` — so a late discovery could still auto-connect and the
    /// UI never left `.scanning`.
    @Test func cancelBeforeDiscoveryStopsScanAndGoesDown() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.startScan()                                   // first-pair scan in flight, no peripheral
        #expect(client.state == .scanning)
        client.disconnect()
        #expect(fake.stopScanCount >= 1)                     // radio quiesced → no late auto-connect
        #expect(client.state == .disconnected)               // first-pair cancel publishes the terminal
    }

    /// R2-11 defect 3: a cold/reconnect establishment that stalls before `.ready` must fail closed via the
    /// establishment watchdog. A live `CBPeripheral` cannot be constructed in a unit test (see the class
    /// doc and sibling suites — that is why every FakeCentral keeps `retrieveResult` empty), so the pending-
    /// connect `cancelPeripheralConnection` is exercised only on hardware; here we pin the state-machine
    /// outcome the watchdog drives, and that the watchdog is cleared so it can't outlive its window /
    /// double-fire: a KNOWN target lands on the throttled recovery ladder; a first-pair cold connect
    /// terminates cleanly at `.disconnected`.
    @Test func coldConnectEstablishmentWatchdogFailsClosed() {
        // KNOWN target → throttled recovery ladder (not a terminal).
        let fakeKnown = FakeCentral()
        let known = PumpBLEClient(central: fakeKnown)
        known.connectKnownPeripheral(identifier: UUID())     // known target set; empty retrieve ⇒ .scanning
        known.fireEstablishmentWatchdogForTesting()          // establishment stalls before .ready
        #expect(known.reconnectWatchdogArmedForTesting)      // KNOWN target ⇒ reconnect ladder
        #expect(!known.establishmentWatchdogArmedForTesting) // watchdog cleared — no outliving/double-fire
        #expect(known.state != .ready)
        known.disconnect()

        // FIRST PAIR (no known target) → clean, retryable terminal.
        let fakeFirst = FakeCentral()
        let first = PumpBLEClient(central: fakeFirst)
        first.startScan()                                    // no reconnectTargetId
        first.fireEstablishmentWatchdogForTesting()
        #expect(first.state == .disconnected)                // first pair ⇒ terminal, not the ladder
        #expect(!first.reconnectWatchdogArmedForTesting)
        #expect(!first.establishmentWatchdogArmedForTesting)
        first.disconnect()
    }
}
