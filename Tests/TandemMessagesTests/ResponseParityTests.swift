import Testing
@testable import TandemMessages

/// Validates response *parsing* byte-exact against the oracle: encode a response through the
/// cliparser (Java buildCargo), reassemble the packets into a frame, parse it in Swift, and
/// assert the fields round-trip.
@Suite(.enabled(if: OracleRunner.isAvailable)) struct ResponseParityTests {

    /// Reassemble oracle packet hex into a single frame (drop each packet's 2-byte header).
    private func frame(_ packets: [String]) throws -> [UInt8] {
        var out: [UInt8] = []
        for hex in packets {
            let bytes = try Hex.decode(hex)
            out.append(contentsOf: bytes.dropFirst(2))
        }
        return out
    }

    /// Reassemble + parse on a given characteristic (defaults to CURRENT_STATUS, where most reads
    /// arrive). Dispatch is now (characteristic, opcode)-keyed, so control responses pass `.control`.
    private func parse(_ packets: [String], on characteristic: Characteristic = .currentStatus) throws -> ResponseParser.Parsed {
        // Decode-parity fixtures: oracle-encoded without a pairing key, so signed trailers will not
        // verify. HMAC authenticity is covered by SignedResponseHmacVerifyTests.
        try ResponseParser.parse(frame: frame(packets), characteristic: characteristic, verifySignature: false)
    }

    @Test func apiVersionResponseParsesAndDetectsModel() throws {
        // Mobi = API 3.5+; t:slim X2 = 2.x–3.4.
        let mobi = try OracleRunner.encode(txId: 6, messageName: "ApiVersionResponse", json: "[3, 5]").packets
        let m = try #require(try parse(mobi).message as? ApiVersionResponse)
        #expect(m.majorVersion == 3 && m.minorVersion == 5)
        #expect(m.isMobi)
        let tslim = try OracleRunner.encode(txId: 6, messageName: "ApiVersionResponse", json: "[3, 2]").packets
        let t = try #require(try parse(tslim).message as? ApiVersionResponse)
        #expect(!t.isMobi)
    }

    @Test func nonControlIQIOBResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 8, messageName: "NonControlIQIOBResponse", json: "[240, 17940, 240]").packets
        let msg = try #require(try parse(packets).message as? NonControlIQIOBResponse)
        #expect(msg.iob == 240)
        #expect(msg.timeRemainingSeconds == 17940)
        #expect(msg.iobUnits == 0.240)
    }

    @Test func controlIQInfoV2ResponseParses() throws {
        // [closedLoop, weight, weightUnit, TDI, userMode, b6, b7, b8, controlState, exChoice, exDur, exRem]
        let packets = try OracleRunner.encode(
            txId: 9, messageName: "ControlIQInfoV2Response", json: "[true, 70, 0, 40, 2, 0, 0, 0, 1, 0, 0, 0]").packets
        let msg = try #require(try parse(packets).message as? ControlIQInfoV2Response)
        #expect(msg.closedLoopEnabled)
        #expect(msg.currentUserModeType == 2)
        #expect(msg.controlStateType == 1)
    }

    // NOTE: LastBGResponse is verified in ResponseDirectTests — its upstream class has two 3-arg
    // constructors ((long,int,int) and (long,int,BgSource)) and the oracle's reflection picks
    // between them nondeterministically (Java getConstructors() order), so oracle encoding flakes.

    @Test func pumpVersionResponseParses() throws {
        // [armSwVer, mspSwVer, configA, configB, serialNum, partNum, pumpRev, pcbaSN, pcbaRev, modelNum]
        let packets = try OracleRunner.encode(
            txId: 11, messageName: "PumpVersionResponse",
            json: "[1, 2, 0, 0, 123456, 7890, \"abc\", 111, \"def\", 1001]").packets
        let msg = try #require(try parse(packets).message as? PumpVersionResponse)
        #expect(msg.serialNum == 123456)
        #expect(msg.partNum == 7890)
        #expect(msg.pumpRev == "abc")
        #expect(msg.modelNum == 1001)
    }

    @Test func homeScreenMirrorResponseParses() throws {
        // [cgmTrend, cgmAlert, statusIcon0, statusIcon1, bolusStatus, basalStatus, apControlState, remInsulinPlus, cgmDisplay]
        let packets = try OracleRunner.encode(
            txId: 12, messageName: "HomeScreenMirrorResponse", json: "[1, 2, 3, 4, 5, 6, 7, true, false]").packets
        let msg = try #require(try parse(packets).message as? HomeScreenMirrorResponse)
        #expect(msg.cgmTrendIconId == 1)
        #expect(msg.cgmAlertIconId == 2)
        #expect(msg.bolusStatusIconId == 5)
        #expect(msg.apControlStateIconId == 7)
        #expect(msg.remainingInsulinPlusIcon)
        #expect(!msg.cgmDisplayData)
    }

    @Test func pumpSettingsResponseParses() throws {
        // [lowInsulinThreshold, cannulaPrimeSize, autoShutdownEnabled, autoShutdownDuration,
        //  featureLock, oledTimeout, status]
        let packets = try OracleRunner.encode(
            txId: 19, messageName: "PumpSettingsResponse", json: "[20, 30, 1, 720, 0, 30, 0]").packets
        let msg = try #require(try parse(packets).message as? PumpSettingsResponse)
        #expect(msg.lowInsulinThreshold == 20)
        #expect(msg.cannulaPrimeSize == 30)
        #expect(msg.autoShutdownEnabled == 1)
        #expect(msg.autoShutdownDuration == 720)
        #expect(msg.oledTimeout == 30)
    }

    @Test func pumpGlobalsResponseParses() throws {
        // [quickBolusEnabled, incUnits, incCarbs, entryType, status, buttonAnnun, quickBolusAnnun,
        //  bolusAnnun, reminderAnnun, alertAnnun, alarmAnnun, fillTubingAnnun]
        let packets = try OracleRunner.encode(
            txId: 20, messageName: "PumpGlobalsResponse", json: "[1, 1000, 0, 0, 0, 0, 1, 2, 3, 0, 1, 2]").packets
        let msg = try #require(try parse(packets).message as? PumpGlobalsResponse)
        #expect(msg.quickBolusEnabled)
        #expect(msg.quickBolusIncrementUnits == 1000)
        #expect(msg.quickBolusAnnun == 1)
        #expect(msg.bolusAnnun == 2)
        #expect(msg.fillTubingAnnun == 2)
    }

    @Test func cancelBolusResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 21, messageName: "CancelBolusResponse", json: "[0, 10650, 0]").packets
        let msg = try #require(try parse(packets, on: .control).message as? CancelBolusResponse)
        #expect(msg.bolusId == 10650)
        #expect(msg.wasCancelled)
        // A non-zero reason marks a failed cancel (e.g. already delivered).
        let failed = try OracleRunner.encode(
            txId: 22, messageName: "CancelBolusResponse", json: "[1, 10650, 2]").packets
        let fm = try #require(try parse(failed, on: .control).message as? CancelBolusResponse)
        #expect(!fm.wasCancelled)
    }

    @Test func bolusPermissionReleaseResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 23, messageName: "BolusPermissionReleaseResponse", json: "[0]").packets
        let msg = try #require(try parse(packets, on: .control).message as? BolusPermissionReleaseResponse)
        #expect(msg.released)
    }

    @Test func profileStatusResponseParses() throws {
        // [numberOfProfiles, slot0, slot1, slot2, slot3, slot4, slot5, activeSegmentIndex]
        let packets = try OracleRunner.encode(
            txId: 24, messageName: "ProfileStatusResponse", json: "[2, 4, 7, -1, -1, -1, -1, 1]").packets
        let msg = try #require(try parse(packets).message as? ProfileStatusResponse)
        #expect(msg.numberOfProfiles == 2)
        #expect(msg.activeIdpId == 4)
        #expect(msg.activeSegmentIndex == 1)
        #expect(msg.presentIdpIds == [4, 7])
    }

    /// targetBg is deferred to `ResponseDirectTests.currentActiveIdpValuesCaptureTargetBgAtByte4`.
    /// The cliparser oracle writes targetBg at byte 5; the capture-backed decode reads byte 4, so this
    /// oracle vector cannot validate targetBg. carbRatio / insulinDuration / ISF are still asserted here.
    @Test func currentActiveIdpValuesResponseParses() throws {
        // [carbRatio(1000-inc), targetBg, insulinDuration(min), isf]
        let packets = try OracleRunner.encode(
            txId: 25, messageName: "CurrentActiveIdpValuesResponse", json: "[10000, 110, 300, 30]").packets
        let msg = try #require(try parse(packets).message as? CurrentActiveIdpValuesResponse)
        #expect(msg.currentCarbRatio == 10000)
        #expect(msg.carbRatioGramsPerUnit == 10.0)
        // targetBg NOT asserted here — defective oracle encoding; see ResponseDirectTests capture test.
        #expect(msg.currentInsulinDuration == 300)
        #expect(msg.currentIsf == 30)
    }

    /// Second vector with insulinDuration crossing the byte-6 boundary. Confirms duration/ISF decode
    /// independently of targetBg under the pinned oracle's byte-writing scheme. targetBg stays deferred
    /// to the capture-based `ResponseDirectTests` pin.
    @Test func currentActiveIdpValuesResponseParsesAcrossDurationByteBoundary() throws {
        let packets = try OracleRunner.encode(
            txId: 25, messageName: "CurrentActiveIdpValuesResponse", json: "[6000, 200, 400, 45]").packets
        let msg = try #require(try parse(packets).message as? CurrentActiveIdpValuesResponse)
        #expect(msg.currentCarbRatio == 6000)
        // targetBg NOT asserted here — defective oracle encoding; see ResponseDirectTests capture test.
        #expect(msg.currentInsulinDuration == 400)
        #expect(msg.currentIsf == 45)
    }

    @Test func globalMaxBolusSettingsResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 26, messageName: "GlobalMaxBolusSettingsResponse", json: "[25000, 25000]").packets
        let msg = try #require(try parse(packets).message as? GlobalMaxBolusSettingsResponse)
        #expect(msg.maxBolus == 25000)
        #expect(msg.maxBolusUnits == 25.0)
    }

    @Test func basalLimitSettingsResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 27, messageName: "BasalLimitSettingsResponse", json: "[15000, 15000]").packets
        let msg = try #require(try parse(packets).message as? BasalLimitSettingsResponse)
        #expect(msg.basalLimit == 15000)
        #expect(msg.basalLimitUnitsPerHour == 15.0)
    }

    @Test func idpSettingsResponseParses() throws {
        // [idpId, name, numberOfProfileSegments, insulinDuration, maxBolus, carbEntry]
        let packets = try OracleRunner.encode(
            txId: 29, messageName: "IDPSettingsResponse", json: "[4, \"Default\", 3, 300, 25000, true]").packets
        let msg = try #require(try parse(packets).message as? IDPSettingsResponse)
        #expect(msg.idpId == 4)
        #expect(msg.name == "Default")
        #expect(msg.numberOfProfileSegments == 3)
        #expect(msg.insulinDuration == 300)
        #expect(msg.maxBolusUnits == 25.0)
        #expect(msg.carbEntry)
    }

    @Test func idpSegmentResponseParses() throws {
        // [idpId, segmentIndex, startTime, basalRate, carbRatio, targetBG, isf, statusId]
        let packets = try OracleRunner.encode(
            txId: 30, messageName: "IDPSegmentResponse", json: "[4, 0, 0, 850, 10000, 110, 30, 1]").packets
        let msg = try #require(try parse(packets).message as? IDPSegmentResponse)
        #expect(msg.idpId == 4)
        #expect(msg.profileBasalRate == 850)
        #expect(msg.basalRateUnitsPerHour == 0.85)
        #expect(msg.carbRatioGramsPerUnit == 10.0)
        #expect(msg.profileTargetBG == 110)
        #expect(msg.profileISF == 30)
    }

    @Test func extendedBolusStatusV2ResponseParses() throws {
        // [bolusStatus, bolusId, timestamp, requestedVolume, duration, bolusSource, secsSinceReset]
        let packets = try OracleRunner.encode(
            txId: 31, messageName: "ExtendedBolusStatusV2Response",
            json: "[1, 10650, 461510714, 2000, 3600, 8, 461500000]").packets
        let msg = try #require(try parse(packets).message as? ExtendedBolusStatusV2Response)
        #expect(msg.bolusId == 10650)
        #expect(msg.requestedVolume == 2000)
        #expect(msg.requestedUnits == 2.0)
        #expect(msg.duration == 3600)
    }

    @Test func cgmStatusResponseParses() throws {
        // [sessionStateId, lastCalibrationTimestamp, sensorStartedTimestamp, transmitterBatteryStatusId]
        let packets = try OracleRunner.encode(
            txId: 32, messageName: "CGMStatusResponse", json: "[1, 461500000, 461400000, 2]").packets
        let msg = try #require(try parse(packets).message as? CGMStatusResponse)
        #expect(msg.sessionStateId == 1)
        #expect(msg.sessionActive)
        #expect(msg.transmitterBatteryStatusId == 2)
    }

    @Test func cgmStatusV2ResponseParses() throws {
        // [sessionState, lastCal, sensorStarted, batteryStatus, duration, timeRemaining, sensorType, gracePeriod]
        let packets = try OracleRunner.encode(
            txId: 33, messageName: "CgmStatusV2Response",
            json: "[1, 461500000, 461400000, 2, 864000, 432000, 1, true]").packets
        let msg = try #require(try parse(packets).message as? CgmStatusV2Response)
        #expect(msg.sessionActive)
        #expect(msg.sessionDurationSeconds == 864000)
        #expect(msg.cgmSensorTypeId == 1)
        #expect(msg.gracePeriod)
    }

    @Test func cgmHardwareInfoResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 34, messageName: "CGMHardwareInfoResponse", json: "[\"G6ABC123\", 0]").packets
        let msg = try #require(try parse(packets).message as? CGMHardwareInfoResponse)
        #expect(msg.hardwareInfoString == "G6ABC123")
    }

    @Test func controlIQInfoV1ResponseParses() throws {
        // [closedLoop, weight, weightUnit, TDI, userMode, b6, b7, b8, controlState]
        let packets = try OracleRunner.encode(
            txId: 28, messageName: "ControlIQInfoV1Response", json: "[true, 70, 0, 40, 2, 0, 0, 0, 1]").packets
        let msg = try #require(try parse(packets).message as? ControlIQInfoV1Response)
        #expect(msg.closedLoopEnabled)
        #expect(msg.weight == 70)
        #expect(msg.totalDailyInsulin == 40)
        #expect(msg.currentUserModeType == 2)
        #expect(msg.controlStateType == 1)
    }

    @Test func cartridgeFillControlResponsesParse() throws {
        // status-ack responses (oracle-constructable via int status ctor)
        for (name, tid) in [("EnterChangeCartridgeModeResponse", 52), ("ExitChangeCartridgeModeResponse", 53),
                            ("EnterFillTubingModeResponse", 54), ("ExitFillTubingModeResponse", 55),
                            ("FillCannulaResponse", 56)] {
            let p = try OracleRunner.encode(txId: UInt8(tid), messageName: name, json: "[0]").packets
            #expect(try parse(p, on: .control).opCode != 0, "\(name) parsed")
        }
        // PrimeTubingSuspendResponse is direct-tested (oracle can't build it) — see ResponseDirectTests.
        let enter = try OracleRunner.encode(txId: 57, messageName: "FillCannulaResponse", json: "[0]").packets
        #expect(try #require(try parse(enter, on: .control).message as? FillCannulaResponse).accepted)
    }

    @Test func limitsControlResponsesParse() throws {
        let bolus = try OracleRunner.encode(txId: 50, messageName: "SetMaxBolusLimitResponse", json: "[0]").packets
        #expect(try #require(try parse(bolus, on: .control).message as? SetMaxBolusLimitResponse).accepted)
        let basal = try OracleRunner.encode(txId: 51, messageName: "SetMaxBasalLimitResponse", json: "[0]").packets
        #expect(try #require(try parse(basal, on: .control).message as? SetMaxBasalLimitResponse).accepted)
    }

    @Test func alertIdpControlResponsesParse() throws {
        // SetModesResponse is byte[]-only (oracle can't build it) — see ResponseDirectTests.
        let low = try OracleRunner.encode(txId: 44, messageName: "SetLowInsulinAlertResponse", json: "[0]").packets
        #expect(try #require(try parse(low, on: .control).message as? SetLowInsulinAlertResponse).accepted)
        let auto = try OracleRunner.encode(txId: 45, messageName: "SetAutoOffAlertResponse", json: "[0]").packets
        #expect(try #require(try parse(auto, on: .control).message as? SetAutoOffAlertResponse).accepted)
        let idp = try OracleRunner.encode(txId: 47, messageName: "SetActiveIDPResponse", json: "[0]").packets
        #expect(try #require(try parse(idp, on: .control).message as? SetActiveIDPResponse).accepted)
    }

    @Test func soundsTimeControlResponsesParse() throws {
        // PlaySoundResponse has no field constructor the oracle can use (byte[]-only) — see
        // ResponseDirectTests.playSoundResponseOffsets.
        let sounds = try OracleRunner.encode(txId: 42, messageName: "SetPumpSoundsResponse", json: "[0]").packets
        #expect(try #require(try parse(sounds, on: .control).message as? SetPumpSoundsResponse).accepted)
        let time = try OracleRunner.encode(txId: 43, messageName: "ChangeTimeDateResponse", json: "[0]").packets
        #expect(try #require(try parse(time, on: .control).message as? ChangeTimeDateResponse).accepted)
    }

    @Test func remoteEntryControlResponsesParse() throws {
        let carb = try OracleRunner.encode(txId: 39, messageName: "RemoteCarbEntryResponse", json: "[0]").packets
        #expect(try #require(try parse(carb, on: .control).message as? RemoteCarbEntryResponse).accepted)
        let bg = try OracleRunner.encode(txId: 40, messageName: "RemoteBgEntryResponse", json: "[0]").packets
        #expect(try #require(try parse(bg, on: .control).message as? RemoteBgEntryResponse).accepted)
    }

    @Test func cgmSessionControlResponsesParse() throws {
        let start = try OracleRunner.encode(txId: 35, messageName: "StartDexcomG6SensorSessionResponse", json: "[0]").packets
        #expect(try #require(try parse(start, on: .control).message as? StartDexcomG6SensorSessionResponse).accepted)
        let stop = try OracleRunner.encode(txId: 36, messageName: "StopDexcomCGMSensorSessionResponse", json: "[0]").packets
        #expect(try #require(try parse(stop, on: .control).message as? StopDexcomCGMSensorSessionResponse).accepted)
        let sensor = try OracleRunner.encode(txId: 37, messageName: "SetSensorTypeResponse", json: "[0, 1]").packets
        let sm = try #require(try parse(sensor, on: .control).message as? SetSensorTypeResponse)
        #expect(sm.accepted && sm.statusAcknowledgement == 1)
        let g7 = try OracleRunner.encode(txId: 38, messageName: "SetDexcomG7PairingCodeResponse", json: "[0]").packets
        #expect(try #require(try parse(g7, on: .control).message as? SetDexcomG7PairingCodeResponse).accepted)
    }

    @Test func currentBatteryV1ResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 13, messageName: "CurrentBatteryV1Response", json: "[50, 78]").packets
        let msg = try #require(try parse(packets).message as? CurrentBatteryV1Response)
        #expect(msg.currentBatteryAbc == 50)
        #expect(msg.batteryPercent == 78)
    }

    @Test func suspendResumePumpingResponsesParse() throws {
        let s = try OracleRunner.encode(txId: 14, messageName: "SuspendPumpingResponse", json: "[0]").packets
        let sm = try #require(try parse(s, on: .control).message as? SuspendPumpingResponse)
        #expect(sm.status == 0 && sm.accepted)
        let r = try OracleRunner.encode(txId: 15, messageName: "ResumePumpingResponse", json: "[0]").packets
        let rm = try #require(try parse(r, on: .control).message as? ResumePumpingResponse)
        #expect(rm.status == 0 && rm.accepted)
    }

    @Test func controlIQIOBResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 1, messageName: "ControlIQIOBResponse", json: "[240, 17940, 240, 240, 0]").packets
        let parsed = try parse(packets)
        let msg = try #require(parsed.message as? ControlIQIOBResponse)
        #expect(msg.mudaliarIOB == 240)
        #expect(msg.timeRemainingSeconds == 17940)
        #expect(msg.iobType == 0)
        #expect(msg.iobUnits == 0.240)
    }

    @Test func insulinStatusResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 2, messageName: "InsulinStatusResponse", json: "[142, 0, 0]").packets
        let msg = try #require(try parse(packets).message as? InsulinStatusResponse)
        #expect(msg.currentInsulinAmount == 142)
    }

    @Test func currentBatteryV2ResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 3, messageName: "CurrentBatteryV2Response", json: "[75, 78, 0, 0, 0, 0, 0]").packets
        let msg = try #require(try parse(packets).message as? CurrentBatteryV2Response)
        #expect(msg.batteryPercent == 78)
    }

    @Test func bolusPermissionResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 4, messageName: "BolusPermissionResponse", json: "[0, 10650, 0]").packets
        let msg = try #require(try parse(packets, on: .control).message as? BolusPermissionResponse)
        #expect(msg.granted)
        #expect(msg.bolusId == 10650)
    }

    @Test func initiateBolusResponseParses() throws {
        let packets = try OracleRunner.encode(
            txId: 5, messageName: "InitiateBolusResponse", json: "[0, 10650, 0]").packets
        let msg = try #require(try parse(packets, on: .control).message as? InitiateBolusResponse)
        #expect(msg.accepted)
        #expect(msg.bolusId == 10650)
    }

    /// R3-G decode-side guard: a short/garbage InitiateBolusResponse frame must be REJECTED by the parser
    /// (throwing `ParseError`), never trap. The typed `InitiateBolusResponse.init(cargo:)` reads absolute
    /// offsets 0/1/5, so this is the production invariant that guarantees it only ever sees ≥ 6 cargo bytes
    /// — the most safety-critical inbound message (the bolus ack) cannot be built from a truncated frame.
    @Test func truncatedInitiateBolusResponseRejectedNonTrapping() {
        let op = InitiateBolusResponse.props.opCode
        // (a) declared length 26 → after the 24-byte HMAC strip, cargo = 2 bytes (< the required 6);
        // (b) declared length 0 → cargo = 0 bytes. Both are internally consistent (valid length + CRC).
        let short = [op, 0, 26] as [UInt8] + [UInt8](repeating: 0, count: 26)
        let empty = [op, 0, 0] as [UInt8]
        for body in [short, empty] {
            let frame = body + Bytes.calculateCRC16(body)
            #expect(throws: ResponseParser.ParseError.self) {
                _ = try ResponseParser.parse(frame: frame, characteristic: .control)
            }
        }
    }

    @Test func egvGuiDataV2ResponseParses() throws {
        // [bgReadingTimestampSeconds, cgmReading, egvStatusId, trendRate]
        // egvStatusId 1 = VALID
        let packets = try OracleRunner.encode(
            txId: 7, messageName: "CurrentEgvGuiDataV2Response", json: "[461589432, 142, 1, 12]").packets
        let msg = try #require(try parse(packets).message as? CurrentEgvGuiDataV2Response)
        #expect(msg.cgmReading == 142)
        #expect(msg.trendRate == 12)
        #expect(msg.egvStatusId == 1)
        #expect(msg.hasValidReading)
    }

    @Test func basalStatusResponseParses() throws {
        // [profileBasalRate, currentBasalRate, basalModifiedBitmask] — milliunits/hr
        let packets = try OracleRunner.encode(
            txId: 8, messageName: "CurrentBasalStatusResponse", json: "[850, 850, 0]").packets
        let msg = try #require(try parse(packets).message as? CurrentBasalStatusResponse)
        #expect(msg.currentBasalRate == 850)
        #expect(msg.currentBasalUnitsPerHour == 0.85)
    }

    @Test func lastBolusStatusV2ResponseParses() throws {
        // [status, bolusId, timestamp, deliveredVolume, bolusStatusId, bolusSourceId,
        //  bolusTypeBitmask, extendedBolusDuration, requestedVolume]
        let packets = try OracleRunner.encode(
            txId: 9, messageName: "LastBolusStatusV2Response",
            json: "[1, 10650, 461510714, 1000, 3, 8, 8, 0, 1000]").packets
        let msg = try #require(try parse(packets).message as? LastBolusStatusV2Response)
        #expect(msg.bolusId == 10650)
        #expect(msg.deliveredVolume == 1000)
        #expect(msg.deliveredUnits == 1.0)
    }

    /// A corrupted CRC must be rejected.
    @Test func crcMismatchRejected() throws {
        let packets = try OracleRunner.encode(
            txId: 6, messageName: "InsulinStatusResponse", json: "[142, 0, 0]").packets
        var f = try frame(packets)
        f[f.count - 1] ^= 0xFF   // corrupt CRC
        #expect(throws: ResponseParser.ParseError.self) {
            try ResponseParser.parse(frame: f, characteristic: .currentStatus)
        }
    }
}
