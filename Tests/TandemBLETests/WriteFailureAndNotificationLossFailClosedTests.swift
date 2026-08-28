import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// CX-T-05 (phase 14 delivery-safety remediation, ledger id CX-T-05). `PumpBLEClient` has two CORRECT
/// sibling `CBPeripheralDelegate` error branches (`didUpdateNotificationStateFor`/`didUpdateValueFor`) that
/// call `failClosed(resumePending: true)` on error; `didWriteValueFor`'s error branch did not — an async
/// write failure left `writePolicy` elevated and any transaction awaiting that write's correlated response
/// hanging instead of resolving `.connectionLost`. Separately, a POST-ready notification loss (no CB error,
/// `isNotifying` flips false while `state == .ready`) was silently absorbed: `maybeBecomeReady()` no-ops
/// once `.ready`, so nothing ever revoked the (now-stale) readiness.
///
/// Both fixed methods are exercised through internal (not private) helpers extracted from the real
/// `CBPeripheralDelegate` methods — `handleWriteResult`/`handleNotificationStateUpdate` — the SAME
/// testability pattern this file already uses for `handleQualifyingEventsFrame`: a real `CBPeripheral`/
/// `CBCharacteristic` cannot be constructed in a macOS unit test host (TCC-aborted at scan; see the class
/// doc), and neither helper's real CB parameters were ever read in the delegate bodies they were extracted
/// from, so nothing is lost by testing the plain-value core directly.
@Suite struct WriteFailureAndNotificationLossFailClosedTests {

    /// Same fake as the sibling suites (each keeps its own copy — private to their suite scope, per the
    /// convention already established in `BackgroundReconnectTests`/`ReconnectThrottleTests`).
    final class FakeCentral: PumpCentral {
        var state: CBManagerState { .poweredOn }
        func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {}
        func stopScan() {}
        func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {}
        func retrievePeripherals(withIdentifiers identifiers: [UUID]) -> [CBPeripheral] { [] }
        func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [CBPeripheral] { [] }
        func cancelPeripheralConnection(_ peripheral: CBPeripheral) {}
    }

    struct Boom: Error {}

    /// Drive `PumpTransactionCoordinator.perform` to the point where its pending transaction is registered
    /// — mirrors `PumpTransactionCoordinatorTests.launchAndRegister` (each suite keeps its own copy).
    @MainActor private func launchAndRegister(
        _ coord: PumpTransactionCoordinator, on ch: Characteristic, opCode: UInt8,
        deadline: TimeInterval = 5, txId: UInt8 = 7
    ) async -> Task<[UInt8], Error> {
        let before = coord.inFlightCount
        let task = Task { @MainActor in
            try await coord.perform(expectedResponseOn: ch, opCode: opCode, deadline: deadline) { txId }
        }
        while coord.inFlightCount == before { await Task.yield() }
        return task
    }

    // MARK: - CX-T-05 (first half): didWriteValueFor's error branch fails closed

    /// NEGATIVE PATH: an async write error must resume any transaction awaiting that write's correlated
    /// response with a connection-lost-class failure, and must de-elevate the write policy — never leave a
    /// caller hanging or the policy standing elevated (PX-04/PX-08), exactly like the two correct siblings.
    @MainActor @Test func writeErrorFailsClosedAndResumesPendingTransaction() async {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowDelivery   // elevate first, so the reset is observable
        let pending = await launchAndRegister(client.transactions, on: .currentStatus, opCode: 0x01)

        client.handleWriteResult(error: Boom())

        let result = await pending.result
        if case .success = result {
            Issue.record("expected the pending transaction to resolve with a failure, got success")
        }
        #expect(client.writePolicy == .readOnly, "failClosed must de-elevate the write policy on write error")
        #expect(client.transactions.inFlightCount == 0, "the pending transaction must not be left hanging")
    }

    /// A successful write (no error) must NOT fail closed — the write-policy reset above is specific to the
    /// error branch, not a blanket side effect of every write completion.
    @MainActor @Test func successfulWriteDoesNotFailClosed() {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowDelivery
        client.handleWriteResult(error: nil)
        #expect(client.writePolicy == .allowDelivery, "a successful write must not touch the write policy")
    }

    // MARK: - CX-T-05 (second half): post-ready notification loss revokes readiness

    /// NEGATIVE PATH: once `.ready`, a notification-state update with NO CB error but `isNotifying == false`
    /// (the pump/OS dropped the subscription) must revoke readiness rather than being silently absorbed —
    /// `maybeBecomeReady()` alone cannot do this since it no-ops once `state == .ready`.
    @MainActor @Test func postReadyNotificationLossRevokesReadiness() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(client.state != .ready,
                "a post-ready notification loss must revoke readiness, not be silently absorbed")
    }

    /// A notification CONFIRMATION (isNotifying == true) while `.ready` must NOT revoke readiness — the
    /// revoke is specific to a LOSS, not every notification-state callback.
    @MainActor @Test func postReadyNotificationConfirmationDoesNotRevokeReadiness() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: true, error: nil)

        #expect(client.state == .ready, "a notification confirmation must not revoke an already-ready link")
    }

    /// A notification-state ERROR must still fail closed exactly as before (unchanged sibling behavior) —
    /// the CX-T-05 fix is additive to the write-error/notification-loss branches, not a replacement for the
    /// existing error handling in this same delegate.
    @MainActor @Test func notificationStateErrorStillFailsClosed() async {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowDelivery
        let pending = await launchAndRegister(client.transactions, on: .currentStatus, opCode: 0x01)

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: Boom())

        let result = await pending.result
        if case .success = result {
            Issue.record("expected the pending transaction to resolve with a failure, got success")
        }
        #expect(client.writePolicy == .readOnly)
    }

    /// 14-WR-02 (Phase 14 review, Option 2 — pin the DELIBERATE no-fail-closed behavior): a post-ready
    /// notification LOSS (no CB error) revokes readiness to `.discovering` but INTENTIONALLY does NOT reset
    /// `writePolicy` and does NOT fail in-flight transactions — unlike the CB-error branch above. A
    /// notify-barrier flip is not a disconnect, and failing every in-flight transaction on a possibly
    /// transient toggle would be an unbenched pump-link RELIABILITY change. The write gate is `writePolicy`
    /// + `TandemBackend`'s at-most-one-in-flight serialization + `perform()`'s `defer`, NOT `state == .ready`
    /// alone. This test pins that contract so a future edit that "helpfully" fails closed here (a bench-gated
    /// change) is caught and forced through hardware validation first.
    @MainActor @Test func postReadyNotificationLossDoesNotResetWritePolicyOrFailPending() async {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready
        client.writePolicy = .allowDelivery              // elevated, so a spurious reset would be observable
        let pending = await launchAndRegister(client.transactions, on: .currentStatus, opCode: 0x01)

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(client.state == .discovering,
                "a notify-only loss revokes readiness to .discovering (re-declarable), not a full teardown")
        #expect(client.writePolicy == .allowDelivery,
                "14-WR-02: a notify-only loss must NOT reset writePolicy — the gate is writePolicy + serialization, not state")
        #expect(client.transactions.inFlightCount == 1,
                "14-WR-02: a notify-only loss must NOT fail in-flight transactions (that would be an unbenched reliability change)")
        pending.cancel()   // cleanup: nothing resolves this pending tx by design, so cancel the awaiting task
    }

    // MARK: - debug pump-drop-no-reconnect: revoked .discovering must NOT hang silently until force-quit

    /// REGRESSION (debug `pump-drop-no-reconnect`, symptom 2.1). A post-`.ready` notify loss revokes to
    /// `.discovering` (pinned above), but the CX-T-05 comment's premise — that `.ready` is "re-declarable
    /// once the subscription is reconfirmed" — only holds if SOMETHING re-drives the subscription-ready
    /// barrier. On real hardware the pump/OS can drop a notify subscription after a long session WITHOUT a
    /// CB disconnect (the ATT link stays up), so `didDisconnectPeripheral` never fires and the reconnect
    /// ladder is never armed; the establishment watchdog was cancelled when `.ready` was first reached; and
    /// nothing re-issues `setNotifyValue(true)`. With the lost characteristic still in `requestedNotify` but
    /// gone from `confirmedNotifying`, `maybeBecomeReady()` can never re-pass — so the link latches in
    /// `.discovering` FOREVER, silently, until the app is force-quit (the reported bug).
    ///
    /// The recovery contract: a revoked `.discovering` MUST arm a bounded backstop (the establishment
    /// watchdog — the same mechanism every other pre-`.ready` establishment path uses) so it either
    /// re-declares `.ready` after re-subscription or escalates to the reconnect ladder (→ `.ready`, or a
    /// VISIBLE `.reconnectExhausted`). It must never sit in `.discovering` with no timer behind it.
    ///
    /// Oracle: `specified` (the required recovery invariant — "no non-`.ready`/non-terminal state without a
    /// deadline"). Boundary neighbor of the pinned `postReadyNotificationLoss…` cases: same trigger, asserts
    /// the MISSING half (recovery armed) rather than the immediate-values half (state/policy/in-flight).
    @MainActor @Test func postReadyNotificationLossArmsRecoverySoItCannotHangUntilForceQuit() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        #expect(!client.establishmentWatchdogArmedForTesting,
                "precondition: no establishment watchdog is armed while `.ready`")

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(client.state == .discovering,
                "a notify loss revokes to the re-declarable `.discovering` (unchanged contract)")
        #expect(client.establishmentWatchdogArmedForTesting,
                "a revoked `.discovering` MUST arm the establishment-watchdog backstop so it can never hang silently until force-quit (debug pump-drop-no-reconnect 2.1)")
    }

    /// Boundary: a notification CONFIRMATION while `.ready` must NOT arm the recovery backstop — the
    /// establishment watchdog belongs only to the LOSS path, not every notification-state callback (mirrors
    /// `postReadyNotificationConfirmationDoesNotRevokeReadiness`).
    @MainActor @Test func postReadyNotificationConfirmationDoesNotArmRecovery() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: true, error: nil)

        #expect(!client.establishmentWatchdogArmedForTesting,
                "a notify confirmation on a healthy `.ready` link must not arm the establishment watchdog")
    }
}
