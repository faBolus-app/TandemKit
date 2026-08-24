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

/// Decode assertions for the history-log fields ported from pumpx2 `dev` (commits ea361236,
/// 319dace5, d3d209c2). These fields are NOT present in the oracle's pinned-`main` build, so the
/// oracle cannot cross-check them; instead we decode the exact captured-pump-record hex vectors
/// upstream added alongside those commits and assert the newly-decoded fields match upstream's
/// expected values. Not gated on the oracle — these always run.
@Suite struct HistoryLogDecodeCompletenessTests {
    // MARK: op 11 PumpingSuspended / op 12 PumpingResumed (upstream ea361236)

    @Test func pumpingSuspendedAlarmWithRpaTimeout() throws {
        let rec = try Hex.decode("0b1009b90123765b0b006a0000009600010f0000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingSuspendedHistoryLog)
        #expect(m.pumpTimeSec == 587_315_465)
        #expect(m.sequenceNum == 744_310)
        #expect(m.preSuspendState == 106)   // uint32 @10
        #expect(m.insulinAmount == 150)     // existing, unchanged
        #expect(m.reasonId == 1)            // existing, unchanged (ALARM)
        #expect(m.rpaTimeout == 15)         // byte @17
    }

    @Test func pumpingSuspendedUserAbortedWithRpaTimeout() throws {
        let rec = try Hex.decode("0b1030d20223d36c0b006a0000006900000f0000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingSuspendedHistoryLog)
        #expect(m.pumpTimeSec == 587_387_440)
        #expect(m.sequenceNum == 748_755)
        #expect(m.preSuspendState == 106)
        #expect(m.insulinAmount == 105)
        #expect(m.reasonId == 0)            // USER_ABORTED
        #expect(m.rpaTimeout == 15)
    }

    @Test func pumpingResumedAfterAlarmSuspend() throws {
        let rec = try Hex.decode("0c10c6ba0123945b0b0064000000960000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingResumedHistoryLog)
        #expect(m.pumpTimeSec == 587_315_910)
        #expect(m.sequenceNum == 744_340)
        #expect(m.preResumeState == 100)    // uint32 @10
        #expect(m.insulinAmount == 150)     // existing, unchanged
    }

    @Test func pumpingResumedAfterUserSuspend() throws {
        let rec = try Hex.decode("0c102bd80223066d0b0064000000690000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingResumedHistoryLog)
        #expect(m.pumpTimeSec == 587_388_971)
        #expect(m.sequenceNum == 748_806)
        #expect(m.preResumeState == 100)
        #expect(m.insulinAmount == 105)
    }

    // MARK: BolusActivated selectedIob (upstream 319dace5, PR #104)

    @Test func bolusActivatedSelectedIob1() throws {
        let rec = try Hex.decode("370071ef951adfc902000d04010000000000cdcc8c3f00000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? BolusActivatedHistoryLog)
        #expect(m.pumpTimeSec == 446_033_777)
        #expect(m.sequenceNum == 182_751)
        #expect(m.bolusId == 1037)          // existing, unchanged
        #expect(m.selectedIob == 1)         // byte @12
        #expect(m.iob == 0.0)               // existing, unchanged
        #expect(abs(m.bolusSize - 1.1) < 0.0001) // existing, unchanged
    }

    @Test func bolusActivatedSelectedIob2() throws {
        let rec = try Hex.decode("37008393971a46d602001d04010011be00400000003f00000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? BolusActivatedHistoryLog)
        #expect(m.pumpTimeSec == 446_141_315)
        #expect(m.sequenceNum == 185_926)
        #expect(m.bolusId == 1053)
        #expect(m.selectedIob == 1)
        #expect(abs(m.iob - 2.0116007) < 0.0001)
        #expect(m.bolusSize == 0.5)
    }

    // MARK: CGM Dex alert logs (upstream d3d209c2, PR #119)
    // Note: alertId is corrected from a 4-byte read to a single byte @10 by this upstream commit;
    // sensorType @11 (and, for Ack/Activated, further fields) were previously swallowed.

    @Test func cgmAlertAckDex1() throws {
        let rec = try Hex.decode("7311a88c9d228379070002030000000000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertAckDexHistoryLog)
        #expect(m.pumpTimeSec == 580_750_504)
        #expect(m.sequenceNum == 489_859)
        #expect(m.alertId == 2)             // byte @10 (was 770 under the old 4-byte read)
        #expect(m.sensorType == 3)          // byte @11
        #expect(m.ackSource == 0)           // uint32 @14
    }

    @Test func cgmAlertAckDex2NonDefaultAckSource() throws {
        let rec = try Hex.decode("7311d4e18e22f8dc060020030000010000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertAckDexHistoryLog)
        #expect(m.pumpTimeSec == 579_789_268)
        #expect(m.sequenceNum == 449_784)
        #expect(m.alertId == 32)            // byte @10 (was 800 under the old 4-byte read)
        #expect(m.sensorType == 3)
        #expect(m.ackSource == 1)           // non-default source
    }

    @Test func cgmAlertActivatedDex1() throws {
        let rec = try Hex.decode("7111f8da9d22057d07000203000014210000d000000000004843")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertActivatedDexHistoryLog)
        #expect(m.pumpTimeSec == 580_770_552)
        #expect(m.sequenceNum == 490_757)
        #expect(m.alertId == 2)
        #expect(m.sensorType == 3)
        #expect(m.faultLocatorData == 8468) // uint32 @14
        #expect(m.param1 == 208)            // uint32 @18
        #expect(m.param2 == 200.0)          // float @22
    }

    @Test func cgmAlertActivatedDex2() throws {
        let rec = try Hex.decode("71114b179d22a77407000e0300000e2100001900000000406544")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertActivatedDexHistoryLog)
        #expect(m.pumpTimeSec == 580_720_459)
        #expect(m.sequenceNum == 488_615)
        #expect(m.alertId == 14)
        #expect(m.sensorType == 3)
        #expect(m.faultLocatorData == 8462)
        #expect(m.param1 == 25)
        #expect(m.param2 == 917.0)
    }

    @Test func cgmAlertClearedDex1() throws {
        let rec = try Hex.decode("721123f79d227e7e070002030000000000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertClearedDexHistoryLog)
        #expect(m.pumpTimeSec == 580_777_763)
        #expect(m.sequenceNum == 491_134)
        #expect(m.alertId == 2)
        #expect(m.sensorType == 3)
    }

    @Test func cgmAlertClearedDex2() throws {
        let rec = try Hex.decode("721172189d22af7407000e030000000000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? CgmAlertClearedDexHistoryLog)
        #expect(m.pumpTimeSec == 580_720_754)
        #expect(m.sequenceNum == 488_623)
        #expect(m.alertId == 14)
        #expect(m.sensorType == 3)
    }

    // MARK: Control-IQ logs (upstream d3d209c2, PR #119)

    @Test func controlIQPcmChange1() throws {
        let rec = try Hex.decode("e6107ce59d22897d070000030101010101000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQPcmChangeHistoryLog)
        #expect(m.pumpTimeSec == 580_773_244)
        #expect(m.sequenceNum == 490_889)
        #expect(m.currentPcmId == 0)        // existing, unchanged
        #expect(m.previousPcmId == 3)       // existing, unchanged
        #expect(m.pumpSuspended == 1)       // byte @12
        #expect(m.calculationAvailable == 1) // byte @13
        #expect(m.cgmAvailable == 1)        // byte @14
        #expect(m.closedLoopPreferred == 1) // byte @15
        #expect(m.sufficientClosedLoopParams == 1) // byte @16
    }

    @Test func controlIQPcmChange2() throws {
        let rec = try Hex.decode("e61077189d22ba74070003020001010101000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQPcmChangeHistoryLog)
        #expect(m.pumpTimeSec == 580_720_759)
        #expect(m.sequenceNum == 488_634)
        #expect(m.currentPcmId == 3)
        #expect(m.previousPcmId == 2)
        #expect(m.pumpSuspended == 0)
        #expect(m.calculationAvailable == 1)
        #expect(m.cgmAvailable == 1)
        #expect(m.closedLoopPreferred == 1)
        #expect(m.sufficientClosedLoopParams == 1)
    }

    @Test func controlIQUserModeChange1() throws {
        let rec = try Hex.decode("e5105f65912205f9060001020400000100000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQUserModeChangeHistoryLog)
        #expect(m.pumpTimeSec == 579_954_015)
        #expect(m.sequenceNum == 456_965)
        #expect(m.currentUserMode == 1)     // existing, unchanged
        #expect(m.previousUserMode == 2)    // existing, unchanged
        #expect(m.requestedAction == 4)     // byte @12
        #expect(m.sleepStartedByGui == 0)   // byte @14
        #expect(m.activeSleepSchedule == 1) // byte @15
        #expect(m.exerciseStoppedByTimer == 0) // byte @18
        #expect(m.exerciseChoice == 0)      // byte @19
        #expect(m.exerciseTime == 0)        // uint16 @20
        #expect(m.eatingSoonStoppedByTimer == 0) // byte @22
    }

    @Test func controlIQUserModeChange2() throws {
        let rec = try Hex.decode("e5104b659122f8f8060000010200010100000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQUserModeChangeHistoryLog)
        #expect(m.pumpTimeSec == 579_953_995)
        #expect(m.sequenceNum == 456_952)
        #expect(m.currentUserMode == 0)
        #expect(m.previousUserMode == 1)
        #expect(m.requestedAction == 2)
        #expect(m.sleepStartedByGui == 1)
        #expect(m.activeSleepSchedule == 1)
        #expect(m.exerciseStoppedByTimer == 0)
        #expect(m.exerciseChoice == 0)
        #expect(m.exerciseTime == 0)
        #expect(m.eatingSoonStoppedByTimer == 0)
    }
}
