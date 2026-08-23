import Testing
@testable import TandemMessages

/// Builds a 26-byte history-log record with the given header + a tail starting at offset 10.
private func record(typeId: Int, pumpTimeSec: UInt32, seq: UInt32, tail: [UInt8] = []) -> [UInt8] {
    var r = [UInt8](repeating: 0, count: 26)
    let t = Bytes.firstTwoBytesLittleEndian(typeId); r[0] = t[0]; r[1] = t[1]
    let pt = Bytes.toUint32(pumpTimeSec); for i in 0..<4 { r[2 + i] = pt[i] }
    let sq = Bytes.toUint32(seq); for i in 0..<4 { r[6 + i] = sq[i] }
    for (i, b) in tail.enumerated() where 10 + i < 26 { r[10 + i] = b }
    return r
}

/// Byte-exact **decode** parity for history-log events: for each ported typeId, build a record,
/// feed the same bytes to the upstream oracle (`cliparser historylog`) and to Swift
/// `HistoryLogParser`, and assert both agree on typeId + concrete class. History logs are
/// decode-only, so matching the upstream decode is the correctness property.
@Suite(.enabled(if: OracleRunner.isAvailable)) struct HistoryLogOracleParityTests {
    static let cases: [(Int, String)] = [
        (280, "BolusDeliveryHistoryLog"),
        (20, "BolusCompletedHistoryLog"),
        (55, "BolusActivatedHistoryLog"),
        (59, "BolexActivatedHistoryLog"),
        (21, "BolexCompletedHistoryLog"),
        (64, "BolusRequestedMsg1HistoryLog"),
        (65, "BolusRequestedMsg2HistoryLog"),
        (66, "BolusRequestedMsg3HistoryLog"),
        (3, "BasalRateChangeHistoryLog"),
        (81, "DailyBasalHistoryLog"),
        (2, "TempRateActivatedHistoryLog"),
        (15, "TempRateCompletedHistoryLog"),
        (48, "CarbEnteredHistoryLog"),
        (16, "BGHistoryLog"),
        (256, "DexcomG6CGMHistoryLog"),
        (5, "AlarmActivatedHistoryLog"),
        (4, "AlertActivatedHistoryLog"),
        (28, "AlarmClearedHistoryLog"),
        (12, "PumpingResumedHistoryLog"),
        (11, "PumpingSuspendedHistoryLog"),
        (33, "CartridgeFilledHistoryLog"),
        (61, "CannulaFilledHistoryLog"),
        (63, "TubingFilledHistoryLog"),
        (26, "AlertClearedHistoryLog"),
        (99, "ArmInitHistoryLog"),
        (279, "BasalDeliveryHistoryLog"),
        (371, "CgmAlertAckDexHistoryLog"),
        (369, "CgmAlertActivatedDexHistoryLog"),
        (460, "CgmAlertActivatedFsl2HistoryLog"),
        (370, "CgmAlertClearedDexHistoryLog"),
        (461, "CgmAlertClearedFsl2HistoryLog"),
        (372, "CgmDataFsl2HistoryLog"),
        (480, "CgmDataFsl3HistoryLog"),
        (406, "CgmJoinSessionFsl2HistoryLog"),
        (477, "CgmJoinSessionFsl3HistoryLog"),
        (394, "CgmJoinSessionG7HistoryLog"),
        (404, "CgmStartSessionFsl2HistoryLog"),
        (405, "CgmStopSessionFsl2HistoryLog"),
        (486, "CgmStopSessionFsl3HistoryLog"),
        (447, "CgmStopSessionG7HistoryLog"),
        (93, "CorrectionDeclinedHistoryLog"),
        (313, "DailyStatusHistoryLog"),
        (60, "DataLogCorruptionHistoryLog"),
        (14, "DateChangeHistoryLog"),
        (399, "DexcomG7CGMHistoryLog"),
        (82, "FactoryResetHistoryLog"),
        (69, "IdpActionHistoryLog"),
        (57, "IdpActionMsg2HistoryLog"),
        (70, "IdpBolusHistoryLog"),
        (71, "IdpListHistoryLog"),
        (68, "IdpTimeDependentSegmentHistoryLog"),
        (0, "LogErasedHistoryLog"),
        (6, "MalfunctionHistoryLog"),
        (90, "NewDayHistoryLog"),
        (74, "ParamChangeGlobalSettingsHistoryLog"),
        (73, "ParamChangePumpSettingsHistoryLog"),
        (97, "ParamChangeRemSettingsHistoryLog"),
        (96, "ParamChangeReminderHistoryLog"),
        (53, "ShelfModeHistoryLog"),
        (13, "TimeChangedHistoryLog"),
        (36, "UsbConnectedHistoryLog"),
        (37, "UsbDisconnectedHistoryLog"),
        (67, "UsbEnumeratedHistoryLog"),
        (307, "VersionsAHistoryLog"),
    ]

    @Test(arguments: cases)
    func decodeParity(typeId: Int, name: String) throws {
        let rec = record(typeId: typeId, pumpTimeSec: 461_500_000, seq: 42)
        let oracle = try OracleRunner.parseHistoryLog(hex: Hex.encode(rec))
        #expect(oracle.typeId == typeId, "oracle typeId \(oracle.typeId) != \(typeId)")
        #expect(oracle.className == name, "oracle class \(oracle.className) != \(name)")
        let event = HistoryLogParser.parse(record: rec)
        #expect(String(describing: type(of: event)) == name)
        #expect(event.typeId == typeId)
        #expect(event.pumpTimeSec == 461_500_000)
        #expect(event.sequenceNum == 42)
    }
}

/// History-log types the oracle can't cross-check — NOT a stale-JAR problem (the vendored jar was
/// verified byte-identical to a fresh dad3eea build). Every typeId here is in 128–255, and upstream
/// `HistoryLog.parseBase` reads the typeId from a signed byte and adds 512 for negative values,
/// mis-decoding this whole range: most read as "unknown", and a couple collide with other types
/// (230→486, 191→447). Our Swift reads the typeId as a clean unsigned 12-bit value, so it's actually
/// *more* correct than the reference — which is why these can only be Swift-dispatch-verified here.
/// Promoting them to byte-exact parity needs an UPSTREAM parse() fix in a newer pumpx2 + a re-pin,
/// not a jar rebuild.
@Suite struct HistoryLogSwiftDispatchTests {
    static let cases: [(Int, String)] = [
        (171, "CgmAlertActivatedHistoryLog"),
        (172, "CgmAlertClearedHistoryLog"),
        (210, "CgmCalibrationGxHistoryLog"),
        (160, "CgmCalibrationHistoryLog"),
        (211, "CgmDataGxHistoryLog"),
        (151, "CgmDataSampleHistoryLog"),
        (213, "CgmJoinSessionHistoryLog"),
        (212, "CgmStartSessionHistoryLog"),
        (214, "CgmStopSessionHistoryLog"),
        (230, "ControlIQPcmChangeHistoryLog"),
        (229, "ControlIQUserModeChangeHistoryLog"),
        (199, "HypoMinimizerResumeHistoryLog"),
        (198, "HypoMinimizerSuspendHistoryLog"),
        (140, "PlgsPeriodicHistoryLog"),
        (203, "UpdateStatusHistoryLog"),
        (191, "VersionInfoHistoryLog"),
        (319, "AAExerciseChoiceChangeHistoryLog"),
        (318, "AAExerciseTimeChangeHistoryLog"),
        (332, "AATdiEstChangeHistoryLog"),
        (288, "AaAutoBolusRejectedHistoryLog"),
        (238, "AaDeliveryStatusChangeHistoryLog"),
        (244, "AaEnableSettingChangeHistoryLog"),
        (235, "AaSleepScheduleChangeHistoryLog"),
        (245, "AaTdiSettingChangeHistoryLog"),
        (246, "AaWeightSettingChangeHistoryLog"),
        (8, "AlarmAckHistoryLog"),
        (27, "AlertAckHistoryLog"),
        (142, "BasalIqSettingsChangeHistoryLog"),
        (32, "CartridgeInsertedHistoryLog"),
        (31, "CartridgeRemovedHistoryLog"),
        (173, "CgmAlertAckHistoryLog"),
        (157, "CgmAnnuSettingsHistoryLog"),
        (439, "CgmBleCalibrationEvtG7HistoryLog"),
        (438, "CgmCalibrationG7HistoryLog"),
        (168, "CgmFraSettingsHistoryLog"),
        (165, "CgmHgaSettingsHistoryLog"),
        (441, "CgmInactiveG7HistoryLog"),
        (215, "CgmInactiveGxHistoryLog"),
        (166, "CgmLgaSettingsHistoryLog"),
        (169, "CgmOorSettingsHistoryLog"),
        (395, "CgmPairingCodeG7HistoryLog"),
        (367, "CgmRejoinSessionHistoryLog"),
        (167, "CgmRraSettingsHistoryLog"),
        (368, "CgmSensorTypeChangeHistoryLog"),
        (267, "CgmSessionTypeChangeHistoryLog"),
        (390, "CgmStartSensorReqG7HistoryLog"),
        (217, "CgmStartSessionReqGxHistoryLog"),
        (162, "CgmStopSessionMsg1HistoryLog"),
        (163, "CgmStopSessionMsg2HistoryLog"),
        (443, "CgmStopSessionReqG7HistoryLog"),
        (218, "CgmStopSessionReqGxHistoryLog"),
        (216, "CgmTransmitterIdGxHistoryLog"),
        (156, "CgmTransmitterIdHistoryLog"),
        (220, "CgmTransmitterVersionGxHistoryLog"),
        (187, "CgmUnexpectedGeAlertHistoryLog"),
        (41, "ConfirmCartridgeFilledHistoryLog"),
        (98, "FillEstimateFinalHistoryLog"),
        (7, "MalfunctionAckHistoryLog"),
        (348, "PrimeInprocessHistoryLog"),
        (25, "ReminderActivatedHistoryLog"),
        (29, "ReminderDismissedHistoryLog"),
        (30, "ReminderSnoozedHistoryLog"),
        (286, "SnoozeActivatedHistoryLog"),
        (419, "TipsErrorHistoryLog"),
        (291, "TipscReqPrimeCannulaHistoryLog"),
        (301, "WumpCartridgeFilledHistoryLog"),
        (302, "WumpCartridgeRemovedHistoryLog"),
        (283, "WumpOcclusionDebugHistoryLog"),
    ]
    @Test(arguments: cases)
    func dispatch(typeId: Int, name: String) {
        var r = [UInt8](repeating: 0, count: 26)
        let t = Bytes.firstTwoBytesLittleEndian(typeId); r[0] = t[0]; r[1] = t[1]
        let event = HistoryLogParser.parse(record: r)
        #expect(String(describing: type(of: event)) == name)
        #expect(event.typeId == typeId)
    }
}

/// Direct field-offset tests that don't need the oracle.
@Suite struct HistoryLogEventsTests {
    private func hex(_ s: String) -> [UInt8] {
        var out: [UInt8] = []; var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2)
            out.append(UInt8(s[i..<j], radix: 16)!); i = j }
        return out
    }

    /// Real BolusCompleted wire vector (from upstream BolusCompletedHistoryLogTest): typeId 20,
    /// delivered 1.7869551 u, iob 3.652852 u.
    @Test func bolusCompletedRealVector() {
        let rec = hex("14009ed7971a70d802000300210454c86940f2bae43ff2bae43f")
        #expect(rec.count == 26)
        let event = HistoryLogParser.parse(record: rec)
        let m = try? #require(event as? BolusCompletedHistoryLog)
        #expect(m?.completionStatusId == 3)
        #expect(m?.bolusId == 1057)
        #expect(abs((m?.insulinDelivered ?? 0) - 1.7869551) < 0.0001)
        #expect(abs((m?.iob ?? 0) - 3.652852) < 0.0001)
        #expect(m?.pumpTimeSec == 446_158_750)
        #expect(m?.sequenceNum == 186_480)
    }

    /// An unknown typeId decodes to UnknownHistoryLog while preserving the header.
    @Test func unknownTypeIdFallsBack() {
        let rec = record(typeId: 4095, pumpTimeSec: 123, seq: 9)
        let event = HistoryLogParser.parse(record: rec)
        #expect(event is UnknownHistoryLog)
        #expect(event.pumpTimeSec == 123)
        #expect(event.sequenceNum == 9)
    }

    /// TempRateActivated: percent float@10, tempRateId short@20.
    @Test func tempRateActivatedFields() {
        var tail = [UInt8](repeating: 0, count: 16)
        let pct = Bytes.toFloat(150.0); for i in 0..<4 { tail[i] = pct[i] }         // offset 10
        let id = Bytes.firstTwoBytesLittleEndian(7); tail[10] = id[0]; tail[11] = id[1] // offset 20
        let rec = record(typeId: 2, pumpTimeSec: 500, seq: 1, tail: tail)
        let m = try? #require(HistoryLogParser.parse(record: rec) as? TempRateActivatedHistoryLog)
        #expect(m?.percent == 150.0)
        #expect(m?.tempRateId == 7)
    }

    // Regression (upstream dev d3d209c2, PR #119): the 3 Dexcom CGM-alert logs (369/370/371) decode
    // alertId as a SINGLE byte @10. The earlier 4-byte read swallowed sensorType@11 + padding, mis-
    // decoding e.g. alertId 2 as 770. Captured real-pump records. Non-oracle (the oracle doesn't
    // compare alertId). Only the alertId narrowing is ported to `main`; sensorType et al. stay on experimental.
    @Test func cgmDexAlertIdIsSingleByteAtOffset10() throws {
        let ack = try #require(HistoryLogParser.parse(
            record: Hex.decode("7311a88c9d228379070002030000000000000000000000000000")) as? CgmAlertAckDexHistoryLog)
        #expect(ack.pumpTimeSec == 580_750_504)
        #expect(ack.alertId == 2)   // byte @10 — was 770 under the old 4-byte read
        let activated = try #require(HistoryLogParser.parse(
            record: Hex.decode("7111f8da9d22057d07000203000014210000d000000000004843")) as? CgmAlertActivatedDexHistoryLog)
        #expect(activated.alertId == 2)
        let cleared = try #require(HistoryLogParser.parse(
            record: Hex.decode("721123f79d227e7e070002030000000000000000000000000000")) as? CgmAlertClearedDexHistoryLog)
        #expect(cleared.alertId == 2)
    }
}
