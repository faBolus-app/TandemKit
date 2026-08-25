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
}
