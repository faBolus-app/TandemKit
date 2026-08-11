import Testing
import Foundation
import CoreBluetooth
import PumpX2Messages
@testable import PumpX2BLE

/// Pump-pairing connect/disconnect-loop fix (`.planning/debug/pump-pairing-loop.md`, faBolus repo):
/// `didDisconnectPeripheral` / `didFailToConnect` used to re-issue `central.connect()` immediately (zero
/// delay), and `startReconnectWatchdog()` reset `reconnectAttempts = 0` on EVERY call — so a peer that
/// kept accepting-then-dropping the link (classic during pairing: the official t:connect app still holds
/// the pump, or the pump's pairing/GATT window closing) drove a rapid, unthrottled, never-escalating
/// connect/disconnect loop.
///
/// This suite pins the fix at the unit that actually drives the ladder: `reconnectTick()` (one throttled
/// attempt) and `startReconnectWatchdog()` (the arm entry point every disconnect/fail-to-connect calls).
/// Both are exposed internal-not-private for this — same convention as `scanTimedOut()` in
/// `ScanTimeoutTests.swift` — because `didDisconnectPeripheral`/`didFailToConnect` themselves take a live
/// `CBPeripheral`, which cannot be constructed in a unit test (no public initializer, and a macOS test
/// host is TCC-aborted at a real scan/connect — see `PumpBLEClient`'s class doc).
@MainActor
@Suite struct ReconnectThrottleTests {

    /// Same fake as `ScanTimeoutTests.FakeCentral` (duplicated locally — that one is private to its own
    /// suite): records calls, lets a test drive `state` + `retrieve*` results, no CoreBluetooth/hardware.
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

    /// Records every `didError` the client reports, so a test can assert `.reconnectLoopDetected` was
    /// surfaced without needing a full app-level delegate.
    final class RecordingDelegate: PumpBLEClientDelegate {
        var errors: [PumpBLEClient.ClientError] = []
        func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {}
        func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {}
        func pumpClientDidBecomeReady(_ client: PumpBLEClient) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {}
        func pumpClient(_ client: PumpBLEClient, didError error: Error) {
            if let e = error as? PumpBLEClient.ClientError { errors.append(e) }
        }
    }

    /// THE regression this fix targets: repeatedly arming the ladder (what every disconnect/fail-to-
    /// connect callback does via `startReconnectWatchdog()`) while it's already running must NOT reset
    /// `reconnectAttempts` back to 0. Pre-fix, `startReconnectWatchdog()` unconditionally set
    /// `reconnectAttempts = 0` on every call — this is the exact line that let a flapping peer hold the
    /// backoff at step 0 forever.
    @Test func repeatedArmCallsDoNotResetAttempts() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())   // → .scanning, reconnectTargetId set, no handle
        client.scanTimedOut()                               // first "drop" → arms the ladder at attempts=0
        #expect(client.reconnectAttemptsForTesting == 0)

        client.reconnectTick()                              // one throttled attempt fires → attempts=1
        #expect(client.reconnectAttemptsForTesting == 1)

        // Simulate what a SECOND disconnect does: call the arm entry point again while the ladder is
        // already running (`reconnectWatchdog != nil`).
        client.startReconnectWatchdog()
        #expect(client.reconnectAttemptsForTesting == 1)    // NOT reset to 0 — the bug this test pins
        #expect(client.reconnectWatchdogArmedForTesting)    // still armed (from the first tick's schedule)

        client.disconnect()
    }

    /// Consecutive ticks (each standing in for one throttled reconnect cycle) escalate the attempt
    /// counter monotonically and keep retrying — until `maxReconnectAttempts` is exceeded, at which point
    /// automatic retry stops and `.reconnectExhausted` is surfaced instead of looping forever.
    @Test func consecutiveDropsEscalateThenHitTheCeiling() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let delegate = RecordingDelegate()
        client.delegate = delegate
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        #expect(client.reconnectWatchdogArmedForTesting)

        for expected in 1...PumpBLEClient.maxReconnectAttemptsForTesting {
            client.reconnectTick()
            #expect(client.reconnectAttemptsForTesting == expected)
            #expect(client.state != .reconnectExhausted)      // still within the ladder — kept retrying
            #expect(client.reconnectWatchdogArmedForTesting)   // next attempt is scheduled
        }

        // One more tick pushes the count past the ceiling → give up and surface the loop instead of
        // silently retrying forever.
        client.reconnectTick()
        #expect(client.state == .reconnectExhausted)
        #expect(!client.reconnectWatchdogArmedForTesting)      // no further attempt scheduled
        #expect(delegate.errors.contains(.reconnectLoopDetected))

        client.disconnect()
    }

    /// Once exhausted, `startReconnectWatchdog()` (the entry point every disconnect/fail-to-connect
    /// calls) must stay a no-op — a stray late disconnect can't silently resume the retry storm.
    @Test func startReconnectWatchdogStaysInertAfterExhaustion() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        for _ in 1...(PumpBLEClient.maxReconnectAttemptsForTesting + 1) { client.reconnectTick() }
        #expect(client.state == .reconnectExhausted)

        client.startReconnectWatchdog()                        // simulates a stray late disconnect event
        #expect(!client.reconnectWatchdogArmedForTesting)       // must NOT re-arm
        #expect(client.state == .reconnectExhausted)            // still exhausted, not silently retrying

        client.disconnect()
    }

    /// Item 2 of the fix: the ladder resets on a genuinely new user-initiated pairing/connect call, not
    /// on every drop. `connectKnownPeripheral` is exactly that call.
    @Test func freshUserInitiatedConnectResetsTheLadder() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let target = UUID()
        client.connectKnownPeripheral(identifier: target)
        client.scanTimedOut()
        client.reconnectTick()
        client.reconnectTick()
        #expect(client.reconnectAttemptsForTesting == 2)

        client.connectKnownPeripheral(identifier: target)      // user/app retries — a fresh pairing intent
        #expect(client.reconnectAttemptsForTesting == 0)

        client.disconnect()
    }

    /// The same fresh-connect reset also clears `.reconnectExhausted` — giving up is not permanent; the
    /// user can always explicitly retry.
    @Test func freshConnectClearsExhaustedState() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let target = UUID()
        client.connectKnownPeripheral(identifier: target)
        client.scanTimedOut()
        for _ in 1...(PumpBLEClient.maxReconnectAttemptsForTesting + 1) { client.reconnectTick() }
        #expect(client.state == .reconnectExhausted)

        client.connectKnownPeripheral(identifier: target)
        #expect(client.state != .reconnectExhausted)
        #expect(client.reconnectAttemptsForTesting == 0)

        client.disconnect()
    }
}
