import Foundation
import TandemMessages
import Testing

@testable import TandemBench

/// The decoders behind the harness's bench commands. None of this needs a pump: each test feeds the
/// bytes a reply would carry and checks what the command prints or concludes.
@Suite struct BenchFeatureSetTests {
    @Test func mainSetNamesTheRemoteControlAndControlIQBits() {
        let mask: UInt64 = (1 << 28) | (1 << 10) | (1 << 1)
        let report = BenchFeatureReport(set: .main, bitmask: mask)
        #expect(report.bits.map(\.position) == [1, 10, 28])
        #expect(
            report.bits.map(\.name) == ["DEXCOM_G6_SUPPORTED", "CONTROL_IQ_SUPPORTED", "BLE_PUMP_CONTROL_SUPPORTED"])
        #expect(
            report.callouts == [
                "MAIN bit 28 BLE_PUMP_CONTROL_SUPPORTED: SET", "MAIN bit 10 CONTROL_IQ_SUPPORTED: SET"
            ])
    }

    @Test func clearBitsAreStatedClear() {
        let report = BenchFeatureReport(set: .main, bitmask: 1 << 2)
        #expect(
            report.callouts == [
                "MAIN bit 28 BLE_PUMP_CONTROL_SUPPORTED: CLEAR", "MAIN bit 10 CONTROL_IQ_SUPPORTED: CLEAR"
            ])
    }

    /// Bit 28 of the control set is a different feature; the line says so, so the two aren't confused.
    @Test func controlSetBit28IsFeatureManagement() {
        let report = BenchFeatureReport(set: .control, bitmask: 1 << 28)
        #expect(report.bits == [BenchFeatureBit(position: 28, name: "FEATURE_MANAGEMENT")])
        #expect(report.callouts.count == 1)
        #expect(report.callouts[0].contains("FEATURE_MANAGEMENT (set)"))
    }

    @Test func aBitPumpX2DoesntNameIsPrintedByPosition() {
        let report = BenchFeatureReport(set: .main, bitmask: 1 << 7)
        #expect(report.lines == ["bit 7  (no pumpX2 name)"])
        #expect(BenchFeatureReport(set: .dexcom, bitmask: 0).lines == ["no bits set"])
    }

    /// The main-set names agree with the library's own PumpFeaturesV1 accessors.
    @Test func mainNamesAgreeWithTheLibraryDecoder() {
        for (position, _) in BenchFeatureSet.mainBits {
            let mask = UInt64(1) << UInt64(position)
            let v1 = PumpFeaturesV1Response(cargo: Bytes.toUint64(mask))
            let report = BenchFeatureReport(set: .main, bitmask: v1.featureBitmask)
            #expect(report.isSet(28) == v1.blePumpControlSupported)
            #expect(report.isSet(10) == v1.controlIQSupported)
            #expect(report.isSet(2) == v1.basalIQSupported)
            #expect(report.isSet(18) == v1.basalLimitSupported)
        }
    }

    /// The library's PumpFeaturesV2 decode (status@0, index@1, uint32 LE@2) feeds the report for the
    /// set the pump echoed.
    @Test func v2ReplyBuildsTheReportForTheEchoedIndex() throws {
        let reply = PumpFeaturesV2Response(cargo: [0, 0, 0x00, 0x04, 0x00, 0x10])
        let report = try #require(BenchFeatureReport(reply))
        #expect(report.set == .main)
        #expect(report.bitmask == 0x1000_0400)
        #expect(report.isSet(28) && report.isSet(10))
        let control = try #require(BenchFeatureReport(PumpFeaturesV2Response(cargo: [0, 2, 0, 0, 0, 0x10])))
        #expect(control.set == .control)
        #expect(control.bits.map(\.name) == ["FEATURE_MANAGEMENT"])
        // The top bit survives the library's Int field.
        let top = try #require(BenchFeatureReport(PumpFeaturesV2Response(cargo: [0, 4, 0, 0, 0, 0x80])))
        #expect(top.bits.map(\.position) == [31])
    }

    @Test func anUnnamedIndexHasNoReport() {
        #expect(BenchFeatureReport(PumpFeaturesV2Response(cargo: [0, 9, 1, 0, 0, 0])) == nil)
        #expect(BenchFeatureReport.positionLines(0b101) == ["bit 0", "bit 2"])
    }

    @Test func defaultOrderReadsMainFirstAndEveryIndexIsReachable() {
        #expect(BenchFeatureSet.defaultOrder.first == .main)
        let all = BenchFeatureSet.defaultOrder + BenchFeatureSet.extraOrder
        #expect(Set(all) == Set(BenchFeatureSet.allCases))
        #expect(all.count == BenchFeatureSet.allCases.count)
    }
}

@Suite struct BenchCgmDecoderTests {
    @Test func alertIconNames() {
        #expect(BenchCgmNames.alertIcon(255) == "NO_ERROR")
        #expect(BenchCgmNames.alertIcon(0) == "STARTUP_1")
        #expect(BenchCgmNames.alertIcon(15) == "TRIPLE_DASHES")
        // 9 and 10 aren't in pumpX2's enum, nor are 18 and up.
        #expect(BenchCgmNames.alertIcon(9) == "unknown(9)")
        #expect(BenchCgmNames.alertIcon(18) == "unknown(18)")
    }

    @Test func egvStatusTrendAndSessionNames() {
        #expect(
            (0...5).map(BenchCgmNames.egvStatus) == ["INVALID", "VALID", "LOW", "HIGH", "UNAVAILABLE", "unknown(5)"])
        #expect(BenchCgmNames.trendIcon(4) == "ARROW_FLAT")
        #expect(BenchCgmNames.trendIcon(8) == "unknown(8)")
        #expect(BenchCgmNames.sessionState(2) == "SESSION_ACTIVE")
    }

    @Test func aReadingWhileTheIconIsntNoErrorIsFlagged() {
        #expect(BenchCgmNames.readingDespiteIcon(alertIcon: 15, egvStatus: 1))
        #expect(BenchCgmNames.readingDespiteIcon(alertIcon: 16, egvStatus: 2))
        #expect(!BenchCgmNames.readingDespiteIcon(alertIcon: 255, egvStatus: 1))
        #expect(!BenchCgmNames.readingDespiteIcon(alertIcon: 15, egvStatus: 0))
        #expect(!BenchCgmNames.readingDespiteIcon(alertIcon: 15, egvStatus: 4))
    }
}

@Suite struct BenchSnapshotTests {
    /// A 46-byte snapshot with known fields, and a reading of 0x00b4 (180) at 28 and a timestamp at 30.
    private func cargo() -> [UInt8] {
        var c = [UInt8](repeating: 0, count: 46)
        c[0] = 1
        c[9] = 0xb4  // targetBg 180: the same number as the reading, in a decoded field
        c[13] = 1
        c[14] = 0x10
        c[15] = 0x27  // carbRatio 10000
        c[24] = 0
        c[25] = 1
        c[28] = 0xb4
        c[30] = 0x78
        c[31] = 0x56
        c[32] = 0x34
        c[33] = 0x12
        c[37] = 1
        return c
    }

    @Test func undecodedBytesAre26To36And38To45() {
        #expect(BenchSnapshot.undecodedOffsets == Array(26...36) + Array(38...45))
    }

    @Test func fieldsAgreeWithTheLibraryDecoder() {
        let c = cargo()
        let library = BenchCalcSnapshot(c)
        let lines = BenchSnapshot.lines(c)
        #expect(lines.contains("[0] isUnacked = 1 <-"))
        #expect(lines.contains("[13] carbEntryEnabled = \(library.carbEntryEnabled ? 1 : 0) <-"))
        #expect(lines.contains("[14-17] carbRatio (x1000) = \(library.carbRatio)"))
        #expect(lines.contains("[9-10] targetBg = \(library.targetBg)"))
        #expect(lines.contains("[25] maxIobEventsExceeded = 1 <-"))
        #expect(lines.contains("[37] isAutopopAllowed = 1 <-"))
        #expect(lines.contains("[26-36] not decoded by pumpX2: 00 00 b4 00 78 56 34 12 00 00 00"))
        #expect(lines.contains("[38-45] not decoded by pumpX2: 00 00 00 00 00 00 00 00"))
    }

    @Test func aShortSnapshotSaysSo() {
        #expect(BenchSnapshot.lines([1, 2, 3]) == ["snapshot is 3 bytes, expected 46"])
    }

    /// The reading is found in the undecoded bytes only, not in the target BG that holds the same number.
    @Test func locateFindsTheReadingAndTimestampInUndecodedBytes() {
        let found = BenchSnapshot.locate(reading: 180, timestamp: 0x1234_5678, in: cargo())
        #expect(found.reading == [28])
        #expect(found.timestamp == [30])
        let none = BenchSnapshot.locate(reading: 0, timestamp: 0, in: cargo())
        #expect(none.reading.isEmpty && none.timestamp.isEmpty)
    }

    @Test func consistentKeepsOffsetsSeenInEverySample() {
        #expect(BenchSnapshot.consistent([[28, 40], [28], [28, 30]]) == [28])
        #expect(BenchSnapshot.consistent([]) == [])
    }
}

/// The library's snapshot decode, for comparison.
private struct BenchCalcSnapshot {
    let carbEntryEnabled: Bool
    let carbRatio: UInt32
    let targetBg: Int
    init(_ cargo: [UInt8]) {
        let r = BolusCalcDataSnapshotResponse(cargo: cargo)
        carbEntryEnabled = r.carbEntryEnabled
        carbRatio = r.carbRatio
        targetBg = r.targetBg
    }
}

@Suite struct BenchHistoryProbeTests {
    /// pumpX2's 2023 capture of a t:slim at API 2.5: start 4572 count 5 gave 4572 down to 4568.
    @Test func theRecordedCaptureIsTopAnchored() {
        let p = BenchHistoryProbe(start: 4572, count: 5, received: [4572, 4571, 4570, 4569, 4568])
        #expect(p.anchoring == .top)
        #expect(p.newestFirst)
        #expect(p.topWindow == 4568...4572)
        #expect(p.summary.contains("fits: top"))
    }

    @Test func aLowAnchoredAnswer() {
        let p = BenchHistoryProbe(start: 100, count: 3, received: [100, 101, 102])
        #expect(p.anchoring == .low)
        #expect(!p.newestFirst)
    }

    @Test func oneRecordCantTellThemApart() {
        #expect(BenchHistoryProbe(start: 7, count: 1, received: [7]).anchoring == .ambiguous)
    }

    @Test func emptyAndPartialAnswers() {
        #expect(BenchHistoryProbe(start: 50, count: 5, received: []).anchoring == .empty)
        let partial = BenchHistoryProbe(start: 50, count: 5, received: [50, 49, 48])
        #expect(partial.anchoring == .neither)
        let dup = BenchHistoryProbe(start: 50, count: 2, received: [50, 49, 49])
        #expect(dup.duplicates == 1)
        #expect(dup.summary.contains("1 duplicate"))
    }

    @Test func windowsNearTheEndsDontWrap() {
        #expect(BenchHistoryProbe(start: 2, count: 5, received: []).topWindow == 0...2)
        let high = BenchHistoryProbe(start: UInt32.max - 1, count: 5, received: [UInt32.max])
        #expect(high.lowWindow == (UInt32.max - 1)...UInt32.max)
        #expect(high.anchoring == .neither)
    }

    @Test func capVerdicts() {
        #expect(BenchHistoryProbe.capVerdict(asked: 255, got: 255) == "full page: asked 255, got 255")
        #expect(BenchHistoryProbe.capVerdict(asked: 255, got: 250) == "capped at 250: asked 255, got 250")
        #expect(BenchHistoryProbe.capVerdict(asked: 250, got: 13) == "short page: asked 250, got 13")
    }

    @Test func frameTiming() {
        #expect(BenchFrameTiming(arrivals: []).summary == "no frames")
        #expect(BenchFrameTiming(arrivals: [1]).summary == "1 frame")
        let t = BenchFrameTiming(arrivals: [10, 10.1, 10.25, 10.4])
        #expect(t.gaps.count == 3)
        #expect(t.summary.hasPrefix("4 frames over 0.40 s"))
    }
}

@Suite struct BenchNoticeTests {
    /// Each named position is the library's `QualifyingEvent` bit of that name.
    @Test func bitNamesMatchTheLibrary() {
        let library: [String: QualifyingEvent] = [
            "alert": .alert, "bolusChange": .bolusChange, "cgmChange": .cgmChange,
            "pumpCommunicationsSuspended": .pumpCommunicationsSuspended, "heartbeat": .heartbeat,
            "bolusPermissionRevoked": .bolusPermissionRevoked, "remainingInsulin": .remainingInsulin,
            "pumpReset": .pumpReset
        ]
        for (name, event) in library {
            let position = BenchNoticeBits.names.first { $0.value == name }?.key
            #expect(position.map { UInt32(1) << UInt32($0) } == event.rawValue, "\(name)")
        }
        #expect(BenchNoticeBits.names.count == 30)
    }

    @Test func describeNamesEveryBit() {
        #expect(BenchNoticeBits.describe(0x0008_0400) == "0x00080400 [10 bolusChange, 19 pumpCommunicationsSuspended]")
        #expect(BenchNoticeBits.describe(1 << 30) == "0x40000000 [30 unnamed]")
    }

    @Test func bit19EpisodeOpensRepeatsAndClears() {
        var log = BenchCommsSuspendedLog()
        let bit19: UInt32 = 1 << 19
        #expect(log.record(1 << 15, at: 0) == nil)
        #expect(log.record(bit19 | (1 << 10), at: 10) == "bit 19 SET (episode 1)")
        #expect(log.record(bit19, at: 14)?.hasPrefix("bit 19 again (2 in this episode, 4.0 s") == true)
        #expect(log.record(1 << 10, at: 20)?.hasPrefix("bit 19 cleared by a notice without it: 10.0 s") == true)
        #expect(log.open == nil)
        #expect(log.episodes.count == 1)
        #expect(log.episodes[0].otherBits == [10])
        #expect(log.summary[0].contains("2 notice(s) over 4.0 s, cleared 10.0 s after start; with: bolusChange"))
        #expect(log.record(bit19, at: 30) == "bit 19 SET (episode 2)")
        #expect(log.summary[1].contains("not cleared"))
    }

    @Test func noBit19SaysSo() {
        var log = BenchCommsSuspendedLog()
        _ = log.record(1, at: 0)
        #expect(log.summary == ["bit 19: never seen in 1 notice(s)"])
    }
}

@Suite struct BenchLinkTimelineTests {
    @Test func gapsRunFromTheDropToTheNextReady() {
        var log = BenchReconnectLog()
        #expect(log.ready(at: 0) == nil)
        log.dropped(at: 100, upFor: 100, held: true, reason: "linkLost")
        log.connecting(at: 101)
        log.connecting(at: 107)
        let line = log.ready(at: 112)
        #expect(line?.hasPrefix("reconnect: ready 12.0 s after the drop, 2 connect attempt(s)") == true)
        #expect(line?.hasSuffix("(held)") == true)
        log.dropped(at: 120, upFor: 3, held: false, reason: "linkLost")
        log.connecting(at: 121)
        _ = log.ready(at: 124)
        log.dropped(at: 200, upFor: 76, held: true, reason: "linkLost")
        #expect(
            log.summary == [
                "reconnects: 3 drop(s), 1 flap(s) before the hold, 2 after",
                "drop to ready: min 4.0 median 12.0 max 12.0 s over 2 reconnect(s)",
                "1 drop(s) not reconnected by the end of the run"
            ])
    }

    @Test func noDrops() {
        #expect(BenchReconnectLog().summary == ["reconnects: no drops"])
    }

    @Test func batteryRateIsALeastSquaresFit() throws {
        var trend = BenchBatteryTrend()
        #expect(trend.percentPerHour == nil)
        trend.add(80, at: 0)
        trend.add(79, at: 3600)
        trend.add(78, at: 7200)
        let rate = try #require(trend.percentPerHour)
        #expect(abs(rate - -1) < 1e-9)
        #expect(trend.summary == "battery: 80% -> 78% over 2.00 h (3 readings), fit -1.00 %/h")
        var same = BenchBatteryTrend()
        same.add(50, at: 5)
        same.add(50, at: 5)
        #expect(same.percentPerHour == nil)
    }

    @Test func requestRate() {
        var rate = BenchRequestRate(since: 0)
        for _ in 0..<30 { rate.wrote() }
        #expect(rate.perHour(at: 60) == 1800)
        #expect(rate.perHour(at: 0) == nil)
    }
}

@Suite struct BenchRechunkTests {
    private let key = [UInt8](repeating: 7, count: 16)

    /// Re-cut at 18, a control request is exactly what `Packetize` builds at 18.
    @Test func recutMatchesPacketizeAtTheSmallerSize() throws {
        let messages: [any Message] = [
            DismissNotificationRequest(kind: .reminder, notificationId: 3),
            RemoteCarbEntryRequest()
        ]
        for message in messages {
            let at40 = try Packetize.packetize(message, authenticationKey: key, txId: 9, pumpTimeSinceReset: 1234)
            let at18 = try Packetize.packetize(
                message, authenticationKey: key, txId: 9, pumpTimeSinceReset: 1234, maxChunkSize: 18)
            let cut = try #require(BenchRechunk.split(at40.map { $0.build() }, chunk: 18))
            #expect(cut == at18.map { $0.build() })
            #expect(cut.allSatisfy { $0.count <= 20 })
            #expect(cut.flatMap { $0.dropFirst(2) } == at40.flatMap { $0.build().dropFirst(2) })
        }
    }

    @Test func itRefusesWhatIsntOneRequest() {
        #expect(BenchRechunk.split([], chunk: 18) == nil)
        #expect(BenchRechunk.split([[0]], chunk: 18) == nil)
        #expect(BenchRechunk.split([[1, 5, 1, 2], [0, 6, 3]], chunk: 18) == nil)
        #expect(BenchRechunk.split([[0, 5]], chunk: 18) == nil)
        #expect(BenchRechunk.split([[0, 5, 1]], chunk: 0) == nil)
    }
}

@Suite struct BenchReadsTests {
    /// The bench's copy of form C is the library's request on the wire, keyed the same, minus the tag.
    @Test func lastBolusCIsTheLibraryRequestWithoutTheMobiTag() throws {
        let bench = try Packetize.packetize(BenchLastBolusStatusV3Request(), txId: 4).map { $0.build() }
        let library = try Packetize.packetize(LastBolusStatusV3Request(), txId: 4).map { $0.build() }
        #expect(bench == library)
        #expect(MessageKey(BenchLastBolusStatusV3Request()) == MessageKey(LastBolusStatusV3Request()))
        #expect(BenchLastBolusStatusV3Request.props.responseOpCode == 0xBB)
        #expect(BenchLastBolusStatusV3Request.props.supportedDevices == nil)
        #expect(LastBolusStatusV3Request.props.supportedDevices == [.mobi])
        #expect(!BenchLastBolusStatusV3Request.props.signed)
        #expect(BenchLastBolusStatusV3Request().operationRisk == .read)
    }
}

@Suite struct BenchMirrorTests {
    /// A suspended pump with Control-IQ's suspended state and a sensor fault, byte by byte.
    @Test func mirrorLinesNameEachIcon() {
        let lines = BenchMirror.lines([4, 15, 200, 1, 0, 4, 1, 1, 0])
        #expect(
            lines == [
                "[0] trend icon 4 ARROW_FLAT", "[1] CGM alert icon 15 TRIPLE_DASHES", "[2] status icon 0 200 HIDE_ICON",
                "[3] status icon 1 1 BLOOD_DROP", "[4] bolus icon 0 BOLUS", "[5] basal icon 4 SUSPEND",
                "[6] Control-IQ state 1 STATE_GRAY_RED_BIQ_CIQ_BASAL_SUSPENDED", "[7] remaining-insulin plus icon true",
                "[8] cgmDisplayData false"
            ])
    }

    /// The library decodes the same bytes at the same offsets.
    @Test func mirrorOffsetsAgreeWithTheLibrary() {
        let cargo: [UInt8] = [2, 255, 1, 0, 1, 6, 2, 0, 1]
        let library = HomeScreenMirrorResponse(cargo: cargo)
        let lines = BenchMirror.lines(cargo)
        #expect(lines[0].hasPrefix("[0] trend icon \(library.cgmTrendIconId) "))
        #expect(lines[1].hasPrefix("[1] CGM alert icon \(library.cgmAlertIconId) "))
        #expect(lines[4].hasPrefix("[4] bolus icon \(library.bolusStatusIconId) "))
        #expect(lines[5].hasPrefix("[5] basal icon \(library.basalStatusIconId) "))
        #expect(lines[6].hasPrefix("[6] Control-IQ state \(library.apControlStateIconId) "))
        #expect(lines[8] == "[8] cgmDisplayData \(library.cgmDisplayData)")
    }

    @Test func unknownAndShort() {
        #expect(BenchMirror.basalIcon(9) == "unknown(9)")
        #expect(BenchMirror.lines([1, 2]) == ["mirror is 2 bytes, expected 9"])
    }
}
