import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// A write-value error must `failClosed` (revoke `writePolicy`, resolve in-flight as `.connectionLost`),
/// matching the notify-state and value-update error branches. A post-ready notification loss with
/// `isNotifying == false` must revoke readiness. A notify-only loss must NOT reset writePolicy — that
/// gate is writePolicy + serialization, not connection state.
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

    // MARK: - Write-value error fails closed

    /// An async write error must resume any transaction awaiting that write's correlated response
    /// as `.connectionLost` and de-elevate `writePolicy` — never leave a caller hanging or the policy elevated.
    @MainActor @Test func writeErrorFailsClosedAndResumesPendingTransaction() async {
        let client = PumpBLEClient(central: FakeCentral())
        client.writePolicy = .allowDelivery  // elevate first, so the reset is observable
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

    // MARK: - Post-ready notification loss revokes readiness

    /// Once `.ready`, a notification-state update with no CB error but `isNotifying == false`
    /// (the pump/OS dropped the subscription) must revoke readiness rather than being silently absorbed —
    /// `maybeBecomeReady()` alone cannot do this since it no-ops once `state == .ready`.
    @MainActor @Test func postReadyNotificationLossRevokesReadiness() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(
            client.state != .ready,
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

    /// A notification-state error must still `failClosed` (revoke `writePolicy`, resolve in-flight).
    /// Notify-loss handling is additive to this error branch, not a replacement.
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

    /// A post-ready notification loss (no CB error) revokes readiness to `.discovering` but must NOT
    /// reset `writePolicy` and must NOT fail in-flight transactions. A notify-barrier flip is not a
    /// disconnect; the write gate is writePolicy + serialization, not `state == .ready` alone.
    @MainActor @Test func postReadyNotificationLossDoesNotResetWritePolicyOrFailPending() async {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready
        client.writePolicy = .allowDelivery  // elevated, so a spurious reset would be observable
        let pending = await launchAndRegister(client.transactions, on: .currentStatus, opCode: 0x01)

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(
            client.state == .discovering,
            "a notify-only loss revokes readiness to .discovering (re-declarable), not a full teardown")
        #expect(
            client.writePolicy == .allowDelivery,
            "a notify-only loss must NOT reset writePolicy — the gate is writePolicy + serialization, not state"
        )
        #expect(
            client.transactions.inFlightCount == 1,
            "a notify-only loss must NOT fail in-flight transactions (that would be an unbenched reliability change)"
        )
        pending.cancel()  // cleanup: nothing resolves this pending tx by design, so cancel the awaiting task
    }

    // MARK: - Revoked `.discovering` must not hang silently

    /// A post-ready notify loss can happen without a CB disconnect, so the reconnect ladder never arms.
    /// A revoked `.discovering` must arm the establishment watchdog so it either re-declares `.ready`
    /// or escalates — never sit with no timer behind it.
    @MainActor @Test func postReadyNotificationLossArmsRecoverySoItCannotHangUntilForceQuit() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        #expect(
            !client.establishmentWatchdogArmedForTesting,
            "precondition: no establishment watchdog is armed while `.ready`")

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: false, error: nil)

        #expect(
            client.state == .discovering,
            "a notify loss revokes to the re-declarable `.discovering` (unchanged contract)")
        #expect(
            client.establishmentWatchdogArmedForTesting,
            "a revoked `.discovering` MUST arm the establishment-watchdog backstop so it can never hang silently until force-quit"
        )
    }

    /// Boundary: a notification CONFIRMATION while `.ready` must NOT arm the recovery backstop — the
    /// establishment watchdog belongs only to the LOSS path, not every notification-state callback (mirrors
    /// `postReadyNotificationConfirmationDoesNotRevokeReadiness`).
    @MainActor @Test func postReadyNotificationConfirmationDoesNotArmRecovery() {
        let client = PumpBLEClient(central: FakeCentral())
        client.stateForTesting = .ready

        client.handleNotificationStateUpdate(mapped: .currentStatus, isNotifying: true, error: nil)

        #expect(
            !client.establishmentWatchdogArmedForTesting,
            "a notify confirmation on a healthy `.ready` link must not arm the establishment watchdog")
    }
}
