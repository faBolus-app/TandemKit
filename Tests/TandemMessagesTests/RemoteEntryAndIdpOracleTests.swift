import Testing
@testable import TandemMessages

/// Byte-locks for the carb/BG-metadata and IDP field VALUES that faBolus sends (audit C-07). The
/// encoders themselves are already parity-locked in OracleParityTests; these pin the specific argument
/// values that were previously best guesses to the reference's ground truth, so a regression that
/// reverts them fails here.
@Suite struct RemoteEntryAndIdpOracleTests {

    /// Ground truth from a captured real-app BLE payload (oracle `RemoteBgEntryRequestTest.ID10652`):
    /// a bolus-window BG is sent as entryType = MANUAL (byte 3 = 0) and source = REMOTE (byte 4 = 1) —
    /// "entered remotely via BLE". faBolus now sends exactly this (was source = PUMP/0). bg 142,
    /// pumpTime 1079274, bolusId 10652.
    @Test func remoteBgEntryManualRemoteMatchesCapture() {
        let req = RemoteBgEntryRequest(
            bg: 142, useForCgmCalibration: false, entryTypeId: 0, sourceId: 1,
            pumpTimeSecondsSinceBoot: 1_079_274, bolusId: 10652)
        // [bg LE][useForCgmCal][entryType][source][pumpTime uint32 LE][bolusId LE]
        let expected: [UInt8] = [142, 0, 0, 0, 1, 234, 119, 16, 0, 156, 41]
        #expect(req.cargo == expected)
        #expect(req.cargo[3] == 0)  // entryType MANUAL
        #expect(req.cargo[4] == 1)  // source REMOTE  ← the corrected value (was 0/PUMP)
    }

    /// The `isAutopopBg: false` convenience faBolus USED to call encodes source = PUMP(0) — i.e. NOT
    /// what any captured vector sends. This guards against regressing back to it.
    @Test func legacyIsAutopopFalseEncodesPumpSource() {
        let legacy = RemoteBgEntryRequest(
            bg: 142, useForCgmCalibration: false, isAutopopBg: false,
            pumpTimeSecondsSinceBoot: 1_079_274, bolusId: 10652)
        #expect(legacy.cargo[4] == 0)  // PUMP — contradicts the captures; must not be used for a remote entry
    }

    // MARK: - PX-05: full-byte IDP payload locks (create / modify / delete + one-bit mutation)
    //
    // The per-field checks above catch a reverted field value; these lock the COMPLETE 35-byte create and
    // 17-byte segment payloads so that a change to ANY byte (layout, offset, endianness, an adjacent
    // field) is caught, not just the four we happened to name. The encoders are independently proven
    // against the Java oracle in OracleParityTests; these pin the exact argument tuple faBolus sends.

    /// Full 35-byte create payload (name "testprofile", CR 3000, basal 1000, target 100, ISF 2,
    /// duration 300, timeSeg 31, bolusSettings 5, idpSource 255, carbEntry 1).
    @Test func createIdpFullByteLock() {
        let req = CreateIDPRequest(
            name: "testprofile", firstSegmentProfileCarbRatio: 3000,
            firstSegmentProfileBasalRate: 1000, firstSegmentProfileTargetBG: 100,
            firstSegmentProfileISF: 2, profileInsulinDuration: 300,
            timeSegmentBitmask: 31, bolusSettingsBitmask: 5, carbEntry: 1, idpSourceId: 255)
        let expected: [UInt8] = [
            116, 101, 115, 116, 112, 114, 111, 102, 105, 108, 101, 0, 0, 0, 0, 0, 0,
            184, 11, 0, 0, 0, 0, 232, 3, 100, 0, 2, 0, 44, 1, 31, 5, 255, 1
        ]
        #expect(req.cargo == expected)
        // Field callouts (offsets): [31]=timeSeg 31, [32]=bolusSettings 5, [33]=idpSource 255, [34]=carbEntry 1.
    }

    /// Full 17-byte segment MODIFY payload: idpStatusId = 31 (all fields changed). Byte 3 = operationId 1.
    @Test func setIdpSegmentModifyFullByteLock() {
        let req = SetIDPSegmentRequest(
            idpId: 1, profileIndex: 0, segmentIndex: 0, operationId: 1,
            profileStartTime: 0, profileBasalRate: 1000, profileCarbRatio: 3000,
            profileTargetBG: 100, profileISF: 2, idpStatusId: 31)
        #expect(req.cargo == [1, 0, 0, 1, 0, 0, 232, 3, 184, 11, 0, 0, 100, 0, 2, 0, 31])
        #expect(req.cargo[3] == 1)  // operationId = modify
        #expect(req.cargo[16] == 31)  // all-fields changed-mask
    }

    /// Full 17-byte segment DELETE payload: operationId 2, idpStatusId 0 ("nothing changed" is correct
    /// for a delete — it is the ONE case where 0 is right).
    @Test func setIdpSegmentDeleteFullByteLock() {
        let req = SetIDPSegmentRequest(
            idpId: 1, profileIndex: 0, segmentIndex: 0, operationId: 2,
            profileStartTime: 0, profileBasalRate: 1000, profileCarbRatio: 3000,
            profileTargetBG: 100, profileISF: 2, idpStatusId: 0)
        #expect(req.cargo == [1, 0, 0, 2, 0, 0, 232, 3, 184, 11, 0, 0, 100, 0, 2, 0, 0])
        #expect(req.cargo[3] == 2)  // operationId = delete
        #expect(req.cargo[16] == 0)  // changed-mask 0
    }

    /// One-bit mutation: flipping a single input changes exactly the expected byte(s) and nothing else —
    /// proving the full-byte lock is sensitive (a regression can't slip through an unchecked offset).
    @Test func idpSegmentOneBitMutationIsDetected() {
        let base = SetIDPSegmentRequest(
            idpId: 1, profileIndex: 0, segmentIndex: 0, operationId: 1,
            profileStartTime: 0, profileBasalRate: 1000, profileCarbRatio: 3000,
            profileTargetBG: 100, profileISF: 2, idpStatusId: 31)
        let mutated = SetIDPSegmentRequest(
            idpId: 1, profileIndex: 0, segmentIndex: 0, operationId: 1,
            profileStartTime: 0, profileBasalRate: 1000, profileCarbRatio: 3000,
            profileTargetBG: 100, profileISF: 2, idpStatusId: 30)  // 31→30
        #expect(base.cargo != mutated.cargo)
        let diffs = zip(base.cargo, mutated.cargo).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        #expect(diffs == [16])  // exactly the idpStatusId byte moved
    }
}
