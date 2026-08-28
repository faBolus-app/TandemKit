import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

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
        /// D-05: every `willRetryReconnect` call, in order — the attempt# and jittered delay the ladder
        /// computed for that scheduled attempt.
        var retries: [(attempt: Int, delay: TimeInterval)] = []
        func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {}
        func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {}
        func pumpClientDidBecomeReady(_ client: PumpBLEClient) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {}
        func pumpClient(_ client: PumpBLEClient, didError error: Error) {
            if let e = error as? PumpBLEClient.ClientError { errors.append(e) }
        }
        func pumpClient(_ client: PumpBLEClient, willRetryReconnect attempt: Int, after delay: TimeInterval) {
            retries.append((attempt, delay))
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
        client.connectKnownPeripheral(identifier: UUID())  // → .scanning, reconnectTargetId set, no handle
        client.scanTimedOut()  // first "drop" → arms the ladder at attempts=0
        #expect(client.reconnectAttemptsForTesting == 0)

        client.reconnectTick()  // one throttled attempt fires → attempts=1
        #expect(client.reconnectAttemptsForTesting == 1)

        // Simulate what a SECOND disconnect does: call the arm entry point again while the ladder is
        // already running (`reconnectWatchdog != nil`).
        client.startReconnectWatchdog()
        #expect(client.reconnectAttemptsForTesting == 1)  // NOT reset to 0 — the bug this test pins
        #expect(client.reconnectWatchdogArmedForTesting)  // still armed (from the first tick's schedule)

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
            #expect(client.state != .reconnectExhausted)  // still within the ladder — kept retrying
            #expect(client.reconnectWatchdogArmedForTesting)  // next attempt is scheduled
        }

        // One more tick pushes the count past the ceiling → give up and surface the loop instead of
        // silently retrying forever.
        client.reconnectTick()
        #expect(client.state == .reconnectExhausted)
        #expect(!client.reconnectWatchdogArmedForTesting)  // no further attempt scheduled
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

        client.startReconnectWatchdog()  // simulates a stray late disconnect event
        #expect(!client.reconnectWatchdogArmedForTesting)  // must NOT re-arm
        #expect(client.state == .reconnectExhausted)  // still exhausted, not silently retrying

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

        client.connectKnownPeripheral(identifier: target)  // user/app retries — a fresh pairing intent
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

    /// D-05: `willRetryReconnect(attempt:after:)` fires once per scheduled attempt — the initial arm
    /// (`scanTimedOut` → `startReconnectWatchdog` → `scheduleNextReconnectAttempt`, attempt# still 0) and
    /// then once more from every throttled `reconnectTick()` up to (but not including) the ceiling tick —
    /// escalating in lockstep with `reconnectAttemptsForTesting` and matching `reconnectBackoff = [5,10,20,30]`
    /// (jitter only ever ADDS to the base step, never shortens it).
    @Test func willRetryReconnectEscalatesAttemptNumberInLockstepWithReconnectAttempts() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let delegate = RecordingDelegate()
        client.delegate = delegate
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()  // arms the ladder → willRetryReconnect(attempt: 0, …)
        #expect(delegate.retries.map(\.attempt) == [0])
        #expect(delegate.retries.first?.delay ?? 0 >= 5)  // reconnectBackoff[0] == 5, jitter only adds

        for expected in 1...PumpBLEClient.maxReconnectAttemptsForTesting {
            client.reconnectTick()
            #expect(client.reconnectAttemptsForTesting == expected)
        }
        // Every scheduled attempt (the initial arm plus each throttled tick, before the ceiling) fired
        // `willRetryReconnect` with the SAME attempt# the ladder itself reports via `reconnectAttemptsForTesting`.
        #expect(delegate.retries.map(\.attempt) == Array(0...PumpBLEClient.maxReconnectAttemptsForTesting))
        #expect(delegate.retries.allSatisfy { $0.delay >= 5 })

        // The ceiling tick gives up instead of scheduling another attempt — no extra `willRetryReconnect`.
        client.reconnectTick()
        #expect(client.state == .reconnectExhausted)
        #expect(delegate.retries.count == PumpBLEClient.maxReconnectAttemptsForTesting + 1)

        client.disconnect()
    }

    /// SECOND regression this fix targets — found via FRESH on-device evidence gathered AFTER the ladder
    /// fix above had already landed and been verified (`.planning/debug/pump-pairing-loop.md`,
    /// 2026-08-11): `maybeBecomeReady()` used to reset `reconnectAttempts`/`reconnectExhausted` the
    /// INSTANT `.ready` was reached, unconditionally. On-device diagnostics showed the peer can accept
    /// the connection and drop it again (`CBErrorDomain` code 7) in under a second, repeatedly — each
    /// such cycle nominally "succeeded" (it did reach `.ready`), so the ladder reset every time and
    /// `maxReconnectAttempts` never fired: this specific flap looped indefinitely despite the ceiling
    /// existing. `readyHeldLongEnoughToResetLadder`/`consumeReadyStabilityAndMaybeReset` close that gap by
    /// requiring the link to have held `.ready` for `readyStabilityWindow` before trusting it as a real
    /// recovery.
    @Test func briefReadyDoesNotResetLadderButLongReadyDoes() {
        #expect(!PumpBLEClient.readyHeldLongEnoughToResetLadder(heldFor: 0))
        #expect(!PumpBLEClient.readyHeldLongEnoughToResetLadder(heldFor: 0.9))
        #expect(!PumpBLEClient.readyHeldLongEnoughToResetLadder(heldFor: 2.999))
        #expect(PumpBLEClient.readyHeldLongEnoughToResetLadder(heldFor: 3))  // exactly at the window
        #expect(PumpBLEClient.readyHeldLongEnoughToResetLadder(heldFor: 28))  // on-device "healthy" cycle length
    }

    /// A peer that repeatedly reaches `.ready` and drops again WITHIN the stability window must still
    /// climb the ladder to the ceiling instead of resetting to step 0 every cycle — the exact defect this
    /// fix closes. `readySinceForTesting` + `consumeReadyStabilityAndMaybeReset()` simulate what
    /// `didDisconnectPeripheral` does on a real drop, without needing a live `.ready` transition (which
    /// requires a real `CBPeripheral` — see the class doc).
    @Test func briefReadyRepeatedlyDoesNotDefeatTheCeiling() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        let delegate = RecordingDelegate()
        client.delegate = delegate
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        #expect(client.reconnectWatchdogArmedForTesting)

        for expected in 1...PumpBLEClient.maxReconnectAttemptsForTesting {
            // This cycle momentarily "reaches ready" (readySince set to now), then drops immediately —
            // well under `readyStabilityWindow` — exactly like the on-device flap.
            client.readySinceForTesting = Date()
            client.consumeReadyStabilityAndMaybeReset()  // what the drop handler calls
            #expect(client.reconnectAttemptsForTesting == expected - 1)  // NOT reset by the brief "ready"
            client.reconnectTick()
            #expect(client.reconnectAttemptsForTesting == expected)
            #expect(client.state != .reconnectExhausted)
        }

        // One more brief ready-then-drop, then the ceiling tick — must give up, not keep flapping forever.
        client.readySinceForTesting = Date()
        client.consumeReadyStabilityAndMaybeReset()
        client.reconnectTick()
        #expect(client.state == .reconnectExhausted)
        #expect(delegate.errors.contains(.reconnectLoopDetected))

        client.disconnect()
    }

    /// The inverse: a connection that genuinely HOLDS `.ready` for >= `readyStabilityWindow` before
    /// dropping IS trusted as a real recovery and resets the ladder — matches the on-device "healthy
    /// ~28s cycle" pattern seen alongside the flap, which must keep resetting normally. Only the
    /// sub-second flap should be denied a reset, not every drop after a success.
    @Test func longHeldReadyStillResetsTheLadder() {
        let fake = FakeCentral()
        let client = PumpBLEClient(central: fake)
        client.connectKnownPeripheral(identifier: UUID())
        client.scanTimedOut()
        client.reconnectTick()
        client.reconnectTick()
        #expect(client.reconnectAttemptsForTesting == 2)

        // Simulate a connection that held `.ready` for a full 28s (the on-device healthy-cycle length)
        // before dropping — well past `readyStabilityWindow`.
        client.readySinceForTesting = Date().addingTimeInterval(-28)
        client.consumeReadyStabilityAndMaybeReset()
        #expect(client.reconnectAttemptsForTesting == 0)  // genuine recovery — ladder resets as before

        client.disconnect()
    }
}
