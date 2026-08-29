import Testing
import TandemMessages
@testable import TandemBLE

@Suite struct WritePolicyInterlockTests {

    /// Assert the pure authorization decision, not `send()`. `send()` also fails with `.notReady`
    /// (no connection in a unit test), which would mask a wrongly-allowed command.
    @MainActor private func assertBlocked(
        _ client: PumpBLEClient, _ msg: Message,
        by policy: PumpBLEClient.WritePolicy,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            client.authorizationError(for: msg) == .writeBlocked(policy: policy, opcode: msg.opCode),
            "expected \(msg) blocked under \(policy)", sourceLocation: sourceLocation)
    }
    @MainActor private func assertAllowed(
        _ client: PumpBLEClient, _ msg: Message,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            client.authorizationError(for: msg) == nil,
            "expected \(msg) permitted under \(client.writePolicy)", sourceLocation: sourceLocation)
    }

    /// Default policy is read-only: CONTROL / signed / insulin-affecting messages are refused; reads pass.
    @MainActor @Test func readOnlyBlocksWritesAllowsReads() {
        let client = PumpBLEClient.forUnitTest()
        #expect(client.writePolicy == .readOnly)  // safe by default
        assertBlocked(client, InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1), by: .readOnly)
        assertBlocked(client, CancelBolusRequest(bolusId: 1), by: .readOnly)
        assertBlocked(client, BolusPermissionRequest(), by: .readOnly)
        assertAllowed(client, ControlIQIOBRequest())  // a read is never blocked
    }

    /// `.allowNonDelivery` permits therapy-significant CONTROL (BolusPermission) but still hard-blocks
    /// insulin delivery and destructive commands (settings-only).
    @MainActor @Test func allowNonDeliveryIsSettingsOnly() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        assertAllowed(client, BolusPermissionRequest())  // .settings ok
        assertBlocked(
            client, InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1), by: .allowNonDelivery)  // delivery
        assertBlocked(client, FactoryResetRequest(), by: .allowNonDelivery)  // destructive blocked
        assertBlocked(client, DisconnectPumpRequest(), by: .allowNonDelivery)
        assertBlocked(client, ActivateShelfModeRequest(), by: .allowNonDelivery)
    }

    /// Destructive commands require the explicit `.allowDestructive` tier, which still hard-blocks delivery.
    @MainActor @Test func allowDestructivePermitsDestructiveNotDelivery() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowDestructive
        assertAllowed(client, FactoryResetRequest())
        assertAllowed(client, DisconnectPumpRequest())
        assertAllowed(client, ActivateShelfModeRequest())
        assertAllowed(client, BolusPermissionRequest())  // settings ≤ destructive
        assertBlocked(
            client, InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1), by: .allowDestructive)
    }

    /// `.allowBenignControl` permits benign signed ops but blocks settings, destructive, and delivery.
    @MainActor @Test func allowBenignControlSeparatesBenignFromSettings() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowBenignControl
        assertAllowed(client, DismissNotificationRequest(kind: .alert, notificationId: 1))
        assertAllowed(client, PlaySoundRequest())
        assertBlocked(client, BolusPermissionRequest(), by: .allowBenignControl)  // .settings blocked
        assertBlocked(client, FactoryResetRequest(), by: .allowBenignControl)  // .destructive blocked
        assertBlocked(
            client, InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1), by: .allowBenignControl)
    }

    /// A remote BG entry is benign metadata, but the same message marked `useForCgmCalibration`
    /// recalibrates the CGM → therapy-significant, so it must be blocked under `.allowBenignControl`.
    @MainActor @Test func calibrationBgEntryIsNotBenign() {
        let plain = RemoteBgEntryRequest(
            bg: 120, useForCgmCalibration: false, entryTypeId: 0, sourceId: 1,
            pumpTimeSecondsSinceBoot: 1000, bolusId: 1)
        let calib = RemoteBgEntryRequest(
            bg: 120, useForCgmCalibration: true, entryTypeId: 0, sourceId: 1,
            pumpTimeSecondsSinceBoot: 1000, bolusId: 1)
        #expect(plain.operationRisk == .benign)
        #expect(calib.operationRisk == .settings)

        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowBenignControl
        assertAllowed(client, plain)
        assertBlocked(client, calib, by: .allowBenignControl)  // calibration can't ride the benign tier
        client.writePolicy = .allowNonDelivery
        assertAllowed(client, calib)  // but is permitted at the settings tier
    }

    // MARK: - Scoped one-operation policy elevation always restores `.readOnly`

    @MainActor @Test func withWritePolicyElevatesThenRestoresOnSuccess() async {
        let client = PumpBLEClient.forUnitTest()
        var sawInside: PumpBLEClient.WritePolicy?
        await client.withWritePolicy(.allowDelivery) { sawInside = client.writePolicy }
        #expect(sawInside == .allowDelivery)  // elevated inside the scope
        #expect(client.writePolicy == .readOnly)  // restored after
    }

    @MainActor @Test func withWritePolicyRestoresReadOnlyOnThrow() async {
        struct Boom: Error {}
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowBenignControl  // even a non-.readOnly prior must end at .readOnly
        try? await client.withWritePolicy(.allowDestructive) {
            #expect(client.writePolicy == .allowDestructive)
            throw Boom()
        }
        #expect(client.writePolicy == .readOnly)  // never left elevated after a throw
    }

    /// Cancellation surfaces to the scoped body as a thrown `CancellationError`; the restoring defer still
    /// runs, so the policy ends at .readOnly (same guarantee as any other throw — timeout/disconnect
    /// surface as `TxError` from the awaited send and are covered by the coordinator suite).
    @MainActor @Test func withWritePolicyRestoresReadOnlyWhenBodyCancelled() async {
        let client = PumpBLEClient.forUnitTest()
        try? await client.withWritePolicy(.allowDelivery) {
            throw CancellationError()
        }
        #expect(client.writePolicy == .readOnly)
    }

    /// The operation-risk taxonomy classifies representative messages as expected.
    @Test func operationRiskClassification() {
        #expect(InitiateBolusRequest(totalVolume: 1000, bolusID: 1, bolusTypeBitmask: 1).operationRisk == .delivery)
        #expect(SuspendPumpingRequest().operationRisk == .delivery)  // modifiesInsulinDelivery
        #expect(DismissNotificationRequest(kind: .alert, notificationId: 1).operationRisk == .benign)
        #expect(PlaySoundRequest().operationRisk == .benign)
        #expect(FactoryResetRequest().operationRisk == .destructive)
        #expect(BolusPermissionRequest().operationRisk == .settings)  // signed control, non-dispensing default
    }
}
