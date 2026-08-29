import Testing
@testable import TandemMessages

/// Direct (non-oracle) parse tests for responses whose oracle encoding is awkward (many
/// constructor args) or whose real firmware cargo is longer than the base size. Offsets mirror
/// upstream `parse()`.
@Suite struct ResponseDirectTests {
    /// BolusCalcDataSnapshotResponse: verify carbRatio / isf / targetBg / maxBolusHourlyTotal
    /// offsets.
    @Test func bolusCalcSnapshotOffsets() {
        var cargo = [UInt8](repeating: 0, count: 46)
        // targetBg (short @9) = 110
        let tb = Bytes.firstTwoBytesLittleEndian(110)
        cargo[9] = tb[0]
        cargo[10] = tb[1]
        // isf (short @11) = 40
        let isf = Bytes.firstTwoBytesLittleEndian(40)
        cargo[11] = isf[0]
        cargo[12] = isf[1]
        cargo[13] = 1  // carbEntryEnabled
        // carbRatio (uint32 @14) = 10000  (10 g/u ×1000)
        let cr = Bytes.toUint32(10000)
        for i in 0..<4 { cargo[14 + i] = cr[i] }
        // maxBolusAmount (short @18) = 25000 milliunits
        let mb = Bytes.firstTwoBytesLittleEndian(25000)
        cargo[18] = mb[0]
        cargo[19] = mb[1]
        // maxBolusHourlyTotal (uint32 @20) = 15000 milliunits
        let mbht = Bytes.toUint32(15000)
        for i in 0..<4 { cargo[20 + i] = mbht[i] }

        let m = BolusCalcDataSnapshotResponse(cargo: cargo)
        #expect(m.targetBg == 110)
        #expect(m.isf == 40)
        #expect(m.carbEntryEnabled)
        #expect(m.carbRatio == 10000)
        #expect(m.carbRatioGramsPerUnit == 10.0)
        #expect(m.maxBolusAmount == 25000)
        #expect(m.maxBolusHourlyTotal == 15000)
        // cargo left @24/@25 == 0 in this fixture, exercised explicitly by
        // bolusCalcSnapshotCeilingFlagsKnownFalse below.
        #expect(!m.maxBolusEventsExceeded)
        #expect(!m.maxIobEventsExceeded)
    }

    /// BolusCalcDataSnapshotResponse ceiling flags. This fixture asserts layout and the known-false
    /// case only — do not add a `true`-case assertion without a bench-captured fixture.
    @Test func bolusCalcSnapshotCeilingFlagsKnownFalse() {
        var cargo = [UInt8](repeating: 0, count: 46)
        // maxBolusHourlyTotal (uint32 @20) = 20000 milliunits, ceiling configured but not hit
        let mbht = Bytes.toUint32(20000)
        for i in 0..<4 { cargo[20 + i] = mbht[i] }
        cargo[24] = 0  // maxBolusEventsExceeded — known-false fixture
        cargo[25] = 0  // maxIobEventsExceeded — known-false fixture

        let m = BolusCalcDataSnapshotResponse(cargo: cargo)
        #expect(m.maxBolusHourlyTotal == 20000)
        #expect(!m.maxBolusEventsExceeded)
        #expect(!m.maxIobEventsExceeded)
    }

    /// TempRateStatusResponse: active/id/duration (offsets mirror upstream parse; oracle has no
    /// field constructor so this is a direct test). active@0, tempRateId short@1, start u32@4,
    /// secondsSincePumpReset u32@8, duration u32@12.
    @Test func tempRateStatusOffsets() {
        var cargo = [UInt8](repeating: 0, count: 16)
        cargo[0] = 1  // active
        let id = Bytes.firstTwoBytesLittleEndian(7)
        cargo[1] = id[0]
        cargo[2] = id[1]
        let dur = Bytes.toUint32(1800)
        for i in 0..<4 { cargo[12 + i] = dur[i] }
        let m = TempRateStatusResponse(cargo: cargo)
        #expect(m.active)
        #expect(m.tempRateId == 7)
        #expect(m.durationSeconds == 1800)
    }

    /// HistoryLogStatusResponse: count + first/last sequence numbers (uint32 LE @0/4/8).
    @Test func historyLogStatusOffsets() {
        var cargo = [UInt8](repeating: 0, count: 12)
        let n = Bytes.toUint32(50_000)
        for i in 0..<4 { cargo[0 + i] = n[i] }
        let f = Bytes.toUint32(1_000)
        for i in 0..<4 { cargo[4 + i] = f[i] }
        let l = Bytes.toUint32(50_999)
        for i in 0..<4 { cargo[8 + i] = l[i] }
        let m = HistoryLogStatusResponse(cargo: cargo)
        #expect(m.numEntries == 50_000)
        #expect(m.firstSequenceNum == 1_000)
        #expect(m.lastSequenceNum == 50_999)
    }

    /// HistoryLogStreamResponse: pull CGM readings out of a stream frame, skipping non-CGM
    /// records. Builds one Dexcom G6 CGM record (typeId 256) and one non-CGM record (typeId 1).
    @Test func historyLogStreamCgmParsing() {
        func record(typeId: Int, pumpTimeSec: UInt32, seq: UInt32, mgdl: Int) -> [UInt8] {
            var r = [UInt8](repeating: 0, count: 26)
            let t = Bytes.firstTwoBytesLittleEndian(typeId)
            r[0] = t[0]
            r[1] = t[1]
            let pt = Bytes.toUint32(pumpTimeSec)
            for i in 0..<4 { r[2 + i] = pt[i] }
            let sq = Bytes.toUint32(seq)
            for i in 0..<4 { r[6 + i] = sq[i] }
            let g = Bytes.firstTwoBytesLittleEndian(mgdl)
            r[16] = g[0]
            r[17] = g[1]
            return r
        }
        let cgm = record(typeId: 256, pumpTimeSec: 555_000, seq: 42, mgdl: 142)
        let other = record(typeId: 1, pumpTimeSec: 555_060, seq: 43, mgdl: 0)
        let cargo: [UInt8] = [2, 7] + cgm + other  // numberOfHistoryLogs=2, streamId=7

        let m = HistoryLogStreamResponse(cargo: cargo)
        #expect(m.numberOfHistoryLogs == 2)
        #expect(m.streamId == 7)
        #expect(m.records.count == 2)
        let readings = m.cgmReadings
        #expect(readings.count == 1)
        #expect(readings.first?.glucoseMgdl == 142)
        #expect(readings.first?.pumpTimeSec == 555_000)
        #expect(readings.first?.sequenceNum == 42)
    }

    /// HistoryLogStreamResponse: pull completed boluses out of a stream frame. Uses the upstream
    /// `BolusCompletedHistoryLogTest` wire vector (pumpTimeSec 446158750, delivered 1.7869551,
    /// iob 3.652852) to verify the record offsets byte-for-byte.
    @Test func historyLogStreamBolusParsing() {
        func hex(_ s: String) -> [UInt8] {
            var out: [UInt8] = []
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: 2)
                out.append(UInt8(s[i..<j], radix: 16)!)
                i = j
            }
            return out
        }
        let rec = hex("14009ed7971a70d802000300210454c86940f2bae43ff2bae43f")
        #expect(rec.count == 26)
        let cargo: [UInt8] = [1, 3] + rec  // numberOfHistoryLogs=1, streamId=3
        let m = HistoryLogStreamResponse(cargo: cargo)
        let boluses = m.bolusRecords
        #expect(boluses.count == 1)
        #expect(boluses.first?.pumpTimeSec == 446_158_750)
        #expect(boluses.first?.sequenceNum == 186_480)
        #expect(boluses.first?.completionStatusId == 3)
        #expect(abs((boluses.first?.deliveredUnits ?? 0) - 1.7869551) < 0.0001)
        #expect(abs((boluses.first?.iobUnits ?? 0) - 3.652852) < 0.0001)
        #expect(m.cgmReadings.isEmpty)  // a bolus record is not a CGM reading
    }

    /// Alert/alarm bitmaps decode to the right notifications. Bit 0 (Low insulin) + bit 11
    /// (Incomplete bolus) → uint64 with those bits set.
    @Test func alertBitmapDecodes() {
        let bits: UInt64 = (1 << 0) | (1 << 11)
        let m = AlertStatusResponse(cargo: Bytes.toUint64(bits))
        let ns = m.notifications
        #expect(ns.count == 2)
        #expect(ns.contains { $0.id == 0 && $0.kind == .alert && $0.title == "Low insulin" })
        #expect(ns.contains { $0.id == 11 && $0.title == "Incomplete bolus" })
    }

    @Test func alarmBitmapDecodesOcclusion() {
        let m = AlarmStatusResponse(cargo: Bytes.toUint64(1 << 2))
        #expect(m.notifications.count == 1)
        #expect(m.notifications.first?.id == 2)
        #expect(m.notifications.first?.kind == .alarm)
        #expect(m.notifications.first?.title == "Occlusion")
    }

    /// DismissNotificationRequest cargo: notificationId (uint32) + typeId + executeExtraAction.
    @Test func dismissNotificationCargo() {
        let m = DismissNotificationRequest(kind: .alert, notificationId: 21)
        #expect(m.cargo == [21, 0, 0, 0, 1, 0])  // id=21, type=alert(1), flag=0
        #expect(DismissNotificationRequest.props.signed)
        #expect(DismissNotificationRequest.props.characteristic == .control)
        let alarm = DismissNotificationRequest(kind: .alarm, notificationId: 2, executeExtraAction: true)
        #expect(alarm.cargo == [2, 0, 0, 0, 2, 1])
    }

    /// PumpFeaturesV1Response: uint64 feature bitmask @0. Direct test — upstream constructor takes a
    /// BigInteger the oracle's reflection can't build. Sets Control-IQ (1024) + G6 (2) + BLE pump
    /// control (268435456) bits.
    @Test func pumpFeaturesV1Bitmask() {
        let bits: UInt64 = 1024 | 2 | 268_435_456
        let m = PumpFeaturesV1Response(cargo: Bytes.toUint64(bits))
        #expect(m.featureBitmask == bits)
        #expect(m.controlIQSupported)
        #expect(m.dexcomG6Supported)
        #expect(m.blePumpControlSupported)
        #expect(!m.basalIQSupported)
        #expect(!m.controlIQProSupported)
    }

    /// LoadStatusResponse: isLoadingActive@0, loadStateId@1, primeStatusId@2. Direct test — upstream
    /// has multiple overlapping constructors that make oracle reflection ambiguous.
    @Test func loadStatusOffsets() {
        let m = LoadStatusResponse(cargo: [1, 3, 2])
        #expect(m.isLoadingActive)
        #expect(m.loadStateId == 3)
        #expect(m.primeStatusId == 2)
        #expect(!LoadStatusResponse(cargo: [0, 0, 0]).isLoadingActive)
    }

    /// LastBGResponse: bgTimestamp u32@0, bgValue short@4, bgSourceId@6. Direct test because the
    /// oracle can't deterministically construct it (two ambiguous 3-arg constructors upstream).
    @Test func lastBGResponseOffsets() {
        var cargo = [UInt8](repeating: 0, count: 7)
        let ts = Bytes.toUint32(461_589_432)
        for i in 0..<4 { cargo[i] = ts[i] }
        let bg = Bytes.firstTwoBytesLittleEndian(142)
        cargo[4] = bg[0]
        cargo[5] = bg[1]
        cargo[6] = 0  // MANUAL
        let m = LastBGResponse(cargo: cargo)
        #expect(m.bgValue == 142)
        #expect(m.bgSourceId == 0)
    }

    /// ErrorResponse: requestCodeId@0 (failing opcode), errorCodeId@1. Direct test — upstream uses an
    /// ErrorCode enum ctor the oracle reflection can't build from ints.
    @Test func errorResponseOffsets() {
        let m = ErrorResponse(cargo: [159, 3])
        #expect(m.requestCodeId == 159 && m.errorCodeId == 3 && m.isInvalidParameter)
    }

    /// The op-77 error reply also dispatches on `.control` as an additive `(characteristic, opcode)` key.
    /// A rejected control write is NACKed with op-77; the pre-existing `.currentStatus` variant still
    /// dispatches unchanged. Opcodes are not globally unique.
    @Test func op77ErrorDispatchesOnControlAndCurrentStatus() throws {
        func frame(_ op: UInt8, _ cargo: [UInt8]) -> [UInt8] {
            let body: [UInt8] = [op, 0x01, UInt8(cargo.count)] + cargo
            return body + Bytes.calculateCRC16(body)
        }
        // Control variant: failing opcode 0x1C, errorCodeId 3 (INVALID_PARAMETER), plus trailing control
        // context the tolerant size check ignores.
        let ctl = try ResponseParser.parse(
            frame: frame(77, [0x1C, 3] + [UInt8](repeating: 0, count: 24)),
            characteristic: .control)
        #expect((ctl.message as? ErrorResponse)?.requestCodeId == 0x1C)
        #expect((ctl.message as? ErrorResponse)?.isInvalidParameter == true)
        // Pre-existing currentStatus variant unchanged.
        let cs = try ResponseParser.parse(frame: frame(77, [159, 3]), characteristic: .currentStatus)
        #expect((cs.message as? ErrorResponse)?.requestCodeId == 159)
    }

    /// CONTROL_STREAM state responses dispatch on `.controlStream`. These opcodes declare `signed: true,
    /// stream: true`, so frames carry a placeholder (zero) trailer and `verifySignature: false` skips
    /// HMAC verification — this is decode/dispatch, not a signature test.
    @Test func controlStreamStateResponses() throws {
        func frame(_ op: UInt8, _ cargo: [UInt8]) -> [UInt8] {
            let payload = cargo + [UInt8](repeating: 0, count: 24)
            let body: [UInt8] = [op, 0x01, UInt8(payload.count)] + payload
            return body + Bytes.calculateCRC16(body)
        }
        // Detecting cartridge (0xE3): percentComplete short@0
        let det = try ResponseParser.parse(
            frame: frame(0xE3, [50, 0]), characteristic: .controlStream,
            verifySignature: false)
        #expect((det.message as? DetectingCartridgeStateStreamResponse)?.percentComplete == 50)
        // Fill cannula (0xE7): stateId@0
        let fc = try ResponseParser.parse(
            frame: frame(0xE7, [3]), characteristic: .controlStream,
            verifySignature: false)
        #expect((fc.message as? FillCannulaStateStreamResponse)?.stateId == 3)
        // Exit-fill-tubing (0xE9): representative for the -23 group
        let ex = try ResponseParser.parse(
            frame: frame(0xE9, [1]), characteristic: .controlStream,
            verifySignature: false)
        #expect(ex.message is ExitFillTubingModeStateStreamResponse)
    }

    /// A2 control-ack responses: multi-field decode offsets (status@0 + extras), and dispatch of a
    /// representative one through the characteristic-aware ResponseParser on .control.
    @Test func a2ControlResponseOffsets() throws {
        #expect(AdditionalBolusResponse(cargo: [0, 0x9A, 0x29, 0, 0]).status == 0)  // bolusId short@1
        #expect(AdditionalBolusResponse(cargo: [0, 0x9A, 0x29, 0, 0]).bolusId == 10650)
        #expect(CreateIDPResponse(cargo: [0, 5]).newIdpId == 5)
        #expect(DeleteIDPResponse(cargo: [0, 4]).deletedIdpId == 4)
        #expect(RenameIDPResponse(cargo: [0, 3]).numberOfProfiles == 3)
        #expect(SetIDPSegmentResponse(cargo: [0, 1]).unknown == 1)
        #expect(StreamDataPreflightResponse(cargo: [0, 2, 3]).streamTypeId == 3)
        #expect(ChangeControlIQSettingsResponse(cargo: [0, 0, 0]).status == 0)
        #expect(CgmHighLowAlertResponse(cargo: [0]).status == 0)

        // Dispatch a signed CONTROL frame at AdditionalBolusResponse's opcode (0xFB) → correct type.
        let payload: [UInt8] = [0, 0x9A, 0x29, 0, 0] + [UInt8](repeating: 0, count: 24)
        let body: [UInt8] = [0xFB, 0x01, UInt8(payload.count)] + payload
        let frame = body + Bytes.calculateCRC16(body)
        // Dispatch/routing test with a placeholder (zero) HMAC → skip signature verification.
        #expect(
            try ResponseParser.parse(frame: frame, characteristic: .control, verifySignature: false).message
                is AdditionalBolusResponse)
    }

    /// PrimeTubingSuspendResponse: statusCode@0, reserve@2. Direct test — oracle can't build it.
    @Test func primeTubingSuspendResponseOffsets() {
        let m = PrimeTubingSuspendResponse(cargo: [0, 0, 0])
        #expect(m.accepted && m.reserve == 0)
        #expect(!PrimeTubingSuspendResponse(cargo: [2, 0, 0]).accepted)
    }

    /// SetModesResponse: status@0. Direct test — upstream has only a byte[] constructor.
    @Test func setModesResponseOffsets() {
        #expect(SetModesResponse(cargo: [0]).accepted)
        #expect(!SetModesResponse(cargo: [3]).accepted)
    }

    /// PlaySoundResponse: status@0. Direct test — upstream has only a byte[] constructor, so the
    /// oracle's reflection encoder can't build it from a JSON int.
    @Test func playSoundResponseOffsets() {
        #expect(PlaySoundResponse(cargo: [0]).accepted)
        #expect(!PlaySoundResponse(cargo: [1]).accepted)
    }

    /// SetTempRate / StopTempRate response offsets: status@0, tempRateId short@1. The oracle's own
    /// `SetTempRateResponse(int,int)` constructor is broken upstream (declares size=4 but buildCargo
    /// emits 3 bytes → Validate throws), so this is a direct offset test.
    @Test func tempRateResponseOffsets() {
        let set = SetTempRateResponse(cargo: [0x00, 0x05, 0x00, 0x00])
        #expect(set.accepted && set.tempRateId == 5)
        let stop = StopTempRateResponse(cargo: [0x00, 0x07, 0x00])
        #expect(stop.accepted && stop.tempRateId == 7)
        // Non-zero status = rejected.
        #expect(!SetTempRateResponse(cargo: [0x02, 0x00, 0x00, 0x00]).accepted)
    }

    /// The reason ResponseParser is characteristic-keyed: opcode 165 is `SetTempRateResponse` on
    /// CONTROL but `LastBolusStatusV2Response` on CURRENT_STATUS. Dispatch a hand-built signed
    /// CONTROL frame at opcode 165 and confirm it resolves to SetTempRateResponse, not the
    /// currentStatus type sharing that opcode.
    @Test func opcodeCollisionResolvesByCharacteristic() throws {
        #expect(SetTempRateResponse.props.opCode == LastBolusStatusV2Response.props.opCode)
        // Signed frame: cargo (4B) + 24B zero HMAC; length covers both.
        let cargo: [UInt8] = [0x00, 0x05, 0x00, 0x00]
        let payload = cargo + [UInt8](repeating: 0, count: 24)
        let body: [UInt8] = [0xA5, 0x01, UInt8(payload.count)] + payload
        let frame = body + Bytes.calculateCRC16(body)
        // Opcode/characteristic dispatch test with a placeholder (zero) HMAC → skip HMAC verification.
        let parsed = try ResponseParser.parse(frame: frame, characteristic: .control, verifySignature: false)
        #expect(parsed.message is SetTempRateResponse)
        let set = try #require(parsed.message as? SetTempRateResponse)
        #expect(set.accepted && set.tempRateId == 5)
    }

    /// CurrentActiveIdpValuesResponse: pin targetBg at byte 4 against a real hardware capture
    /// (`7017000073002c012800`). The cliparser oracle writes targetBg at byte 5, so no oracle-constructed
    /// vector can validate the correct offset.
    @Test func currentActiveIdpValuesCaptureTargetBgAtByte4() {
        func hex(_ s: String) -> [UInt8] {
            var out: [UInt8] = []
            var i = s.startIndex
            while i < s.endIndex {
                let j = s.index(i, offsetBy: 2)
                out.append(UInt8(s[i..<j], radix: 16)!)
                i = j
            }
            return out
        }
        let cargo = hex("7017000073002c012800")
        #expect(cargo.count == 10)
        let m = CurrentActiveIdpValuesResponse(cargo: cargo)
        #expect(m.currentTargetBg == 115)  // byte-4 decode; Int(raw[5]) would be 0
        #expect(m.currentInsulinDuration == 300)  // regression guard (byte 6-7, unaffected)
        #expect(m.currentIsf == 40)  // regression guard (byte 8-9, unaffected)
        #expect(m.currentCarbRatio == 6000)  // regression guard (byte 0-3, unaffected)
    }

    /// EGV V2 parses a 9-byte cargo (Control-IQ+ firmware appends a trailing byte); a VALID
    /// status (1) with an in-range reading is displayable.
    @Test func egvV2NineByteCargo() {
        // From a real pump frame c1 08 09 | c5 67 e2 22 9e 00 01 04 00 | crc
        let cargo: [UInt8] = [0xc5, 0x67, 0xe2, 0x22, 0x9e, 0x00, 0x01, 0x04, 0x00]
        let m = CurrentEgvGuiDataV2Response(cargo: cargo)
        #expect(m.cgmReading == 158)
        #expect(m.egvStatusId == 1)  // VALID
        #expect(m.trendRate == 4)
        #expect(m.hasValidReading)
    }

    /// A short buffer fed to a fixed-size pure-READ `init(cargo:)` must not trap and must zero-default
    /// every decoded field. Distinct from accept-bearing signed acks, which fail closed to a non-zero status.
    @Test func va20ShortBufferPureReadsZeroDefaultNoTrap() {
        // HistoryLogStatusResponse needs 12 bytes; feed 4.
        let hl = HistoryLogStatusResponse(cargo: [1, 2, 3, 4])
        #expect(hl.numEntries == 0 && hl.firstSequenceNum == 0 && hl.lastSequenceNum == 0)
        #expect(hl.cargo == [1, 2, 3, 4])  // raw retained

        // ControlIQIOBResponse needs 17 bytes; feed 3 (would trap on raw[16] without the guard).
        let iob = ControlIQIOBResponse(cargo: [9, 9, 9])
        #expect(iob.swan6hrIOB == 0 && iob.iobType == 0 && iob.iobUnits == 0.0)

        // CurrentEgvGuiDataV2Response needs 8 bytes; feed 2 (would trap on raw[7] without the guard).
        let egv = CurrentEgvGuiDataV2Response(cargo: [1, 2])
        #expect(egv.cgmReading == 0 && egv.trendRate == 0 && egv.egvStatusId == 0)

        // LastBolusStatusV2Response needs 24 bytes; feed 5 (would trap on readUint32 @20 without the guard).
        let lb = LastBolusStatusV2Response(cargo: [1, 2, 3, 4, 5])
        #expect(lb.status == 0 && lb.deliveredVolume == 0 && lb.requestedVolume == 0)

        // BolusCalcDataSnapshotResponse needs 46 bytes; feed 10 (would trap on raw[24]/raw[25]).
        let bc = BolusCalcDataSnapshotResponse(cargo: [UInt8](repeating: 7, count: 10))
        #expect(bc.carbRatio == 0 && bc.maxBolusAmount == 0 && !bc.maxBolusEventsExceeded)

        // Notifications-family bitmaps need 8 bytes; feed 3.
        #expect(AlertStatusResponse(cargo: [1, 2, 3]).bitmap == 0)
        #expect(MalfunctionBitmaskStatusResponse(cargo: [1, 2, 3]).bitmap == 0)
    }
}
