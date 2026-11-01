import Testing
@testable import TandemMessages

/// Real pump records with upstream's expected values, from the captured-record tests pumpx2 added
/// with these fields (PumpingSuspended/Resumed state, BolusActivated selectedIob, the Dexcom CGM
/// alert fields, Control-IQ PCM and user-mode changes). `HistoryLogFieldParityTests` checks every
/// field against the oracle on random records; these pin the same decode on bytes a pump wrote.
/// First ported on TandemKit's experimental branch, before the oracle carried these fields.
@Suite struct HistoryLogCapturedRecordTests {
    // MARK: op 11 PumpingSuspended / op 12 PumpingResumed

    @Test func pumpingSuspendedAlarmWithRpaTimeout() throws {
        let rec = try Hex.decode("0b1009b90123765b0b006a0000009600010f0000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingSuspendedHistoryLog)
        #expect(m.pumpTimeSec == 587_315_465)
        #expect(m.sequenceNum == 744_310)
        #expect(m.preSuspendState == 106)   // uint32 @10
        #expect(m.insulinAmount == 150)
        #expect(m.reasonId == 1)
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
        #expect(m.insulinAmount == 150)
    }

    @Test func pumpingResumedAfterUserSuspend() throws {
        let rec = try Hex.decode("0c102bd80223066d0b0064000000690000000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? PumpingResumedHistoryLog)
        #expect(m.pumpTimeSec == 587_388_971)
        #expect(m.sequenceNum == 748_806)
        #expect(m.preResumeState == 100)
        #expect(m.insulinAmount == 105)
    }

    // MARK: BolusActivated selectedIob

    @Test func bolusActivatedSelectedIob1() throws {
        let rec = try Hex.decode("370071ef951adfc902000d04010000000000cdcc8c3f00000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? BolusActivatedHistoryLog)
        #expect(m.pumpTimeSec == 446_033_777)
        #expect(m.sequenceNum == 182_751)
        #expect(m.bolusId == 1037)
        #expect(m.selectedIob == 1)         // byte @12
        #expect(m.iob == 0.0)
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

    // MARK: CGM Dex alert logs
    // alertId is a single byte @10 and sensorType is byte 11 (a 4-byte alertId read used to swallow it).

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

    // MARK: Control-IQ logs

    @Test func controlIQPcmChange1() throws {
        let rec = try Hex.decode("e6107ce59d22897d070000030101010101000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQPcmChangeHistoryLog)
        #expect(m.pumpTimeSec == 580_773_244)
        #expect(m.sequenceNum == 490_889)
        #expect(m.currentPcmId == 0)
        #expect(m.previousPcmId == 3)
        #expect(m.pumpSuspendedRaw == 1)       // byte @12
        #expect(m.calculationAvailableRaw == 1) // byte @13
        #expect(m.cgmAvailableRaw == 1)        // byte @14
        #expect(m.closedLoopPreferredRaw == 1) // byte @15
        #expect(m.sufficientClosedLoopParamsRaw == 1) // byte @16
    }

    @Test func controlIQPcmChange2() throws {
        let rec = try Hex.decode("e61077189d22ba74070003020001010101000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQPcmChangeHistoryLog)
        #expect(m.pumpTimeSec == 580_720_759)
        #expect(m.sequenceNum == 488_634)
        #expect(m.currentPcmId == 3)
        #expect(m.previousPcmId == 2)
        #expect(m.pumpSuspendedRaw == 0)
        #expect(m.calculationAvailableRaw == 1)
        #expect(m.cgmAvailableRaw == 1)
        #expect(m.closedLoopPreferredRaw == 1)
        #expect(m.sufficientClosedLoopParamsRaw == 1)
    }

    @Test func controlIQUserModeChange1() throws {
        let rec = try Hex.decode("e5105f65912205f9060001020400000100000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQUserModeChangeHistoryLog)
        #expect(m.pumpTimeSec == 579_954_015)
        #expect(m.sequenceNum == 456_965)
        #expect(m.currentUserMode == 1)
        #expect(m.previousUserMode == 2)
        #expect(m.requestedActionRaw == 4)     // byte @12
        #expect(m.sleepStartedByGuiRaw == 0)   // byte @14
        #expect(m.activeSleepSchedule == 1) // byte @15
        #expect(m.exerciseStoppedByTimerRaw == 0) // byte @18
        #expect(m.exerciseChoiceRaw == 0)      // byte @19
        #expect(m.exerciseTime == 0)        // uint16 @20
        #expect(m.eatingSoonStoppedByTimerRaw == 0) // byte @22
    }

    @Test func controlIQUserModeChange2() throws {
        let rec = try Hex.decode("e5104b659122f8f8060000010200010100000000000000000000")
        let m = try #require(HistoryLogParser.parse(record: rec) as? ControlIQUserModeChangeHistoryLog)
        #expect(m.pumpTimeSec == 579_953_995)
        #expect(m.sequenceNum == 456_952)
        #expect(m.currentUserMode == 0)
        #expect(m.previousUserMode == 1)
        #expect(m.requestedActionRaw == 2)
        #expect(m.sleepStartedByGuiRaw == 1)
        #expect(m.activeSleepSchedule == 1)
        #expect(m.exerciseStoppedByTimerRaw == 0)
        #expect(m.exerciseChoiceRaw == 0)
        #expect(m.exerciseTime == 0)
        #expect(m.eatingSoonStoppedByTimerRaw == 0)
    }
}
