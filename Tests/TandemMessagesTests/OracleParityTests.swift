import Testing
@testable import TandemMessages

/// Byte-exact parity tests against the cliparser oracle. Every ported outgoing message must
/// serialize to the same packet bytes the upstream library produces. These are the tests
/// that make the hand-port trustworthy. Gated on the oracle being built (see OracleRunner).
@Suite(.enabled(if: OracleRunner.isAvailable))
struct OracleParityTests {

    /// Serializes `message` at `txId` via Swift Packetize and returns lowercase packet hex,
    /// matching the oracle's `packets` format.
    private func swiftPackets(_ message: Message, txId: UInt8) throws -> [String] {
        try Packetize.packetize(message, txId: txId).map { Hex.encode($0.build()) }
    }

    @Test(arguments: [UInt8(0), 5, 42, 255])
    func apiVersionRequestMatchesOracle(txId: UInt8) throws {
        let oracle = try OracleRunner.encodePackets(txId: txId, messageName: "ApiVersionRequest")
        let swift = try swiftPackets(ApiVersionRequest(), txId: txId)
        #expect(swift == oracle, "txId=\(txId): swift=\(swift) oracle=\(oracle)")
    }

    /// Sanity: the oracle also reports the characteristic our props declare.
    @Test func apiVersionRequestCharacteristic() throws {
        let result = try OracleRunner.encode(txId: 0, messageName: "ApiVersionRequest")
        #expect(result.characteristicName == ApiVersionRequest.props.characteristic.name)
        #expect(result.characteristic.lowercased()
            == ApiVersionRequest.props.characteristic.uuidString.lowercased())
    }

    // MARK: - Empty-cargo status reads

    /// (oracle message name, Swift instance) pairs for the empty-cargo CURRENT_STATUS reads.
    static let statusReads: [(String, Message)] = [
        ("ControlIQIOBRequest", ControlIQIOBRequest()),
        ("NonControlIQIOBRequest", NonControlIQIOBRequest()),
        ("InsulinStatusRequest", InsulinStatusRequest()),
        ("CurrentBatteryV2Request", CurrentBatteryV2Request()),
        ("CurrentBasalStatusRequest", CurrentBasalStatusRequest()),
        ("HomeScreenMirrorRequest", HomeScreenMirrorRequest()),
        ("PumpVersionRequest", PumpVersionRequest()),
        ("TimeSinceResetRequest", TimeSinceResetRequest()),
        ("CurrentBolusStatusRequest", CurrentBolusStatusRequest()),
        ("LastBolusStatusV2Request", LastBolusStatusV2Request()),
        ("ControlIQInfoV2Request", ControlIQInfoV2Request()),
        ("LastBGRequest", LastBGRequest()),
        ("PumpGlobalsRequest", PumpGlobalsRequest()),
        ("PumpSettingsRequest", PumpSettingsRequest()),
        ("BolusCalcDataSnapshotRequest", BolusCalcDataSnapshotRequest()),
        ("AlertStatusRequest", AlertStatusRequest()),
        ("AlarmStatusRequest", AlarmStatusRequest()),
        ("MalfunctionStatusRequest", MalfunctionStatusRequest()),
        ("HistoryLogStatusRequest", HistoryLogStatusRequest()),
        ("CGMAlertStatusRequest", CGMAlertStatusRequest()),
        ("ProfileStatusRequest", ProfileStatusRequest()),
        ("CurrentActiveIdpValuesRequest", CurrentActiveIdpValuesRequest()),
        ("GlobalMaxBolusSettingsRequest", GlobalMaxBolusSettingsRequest()),
        ("BasalLimitSettingsRequest", BasalLimitSettingsRequest()),
        ("ControlIQInfoV1Request", ControlIQInfoV1Request()),
        ("PumpFeaturesV1Request", PumpFeaturesV1Request()),
        ("LoadStatusRequest", LoadStatusRequest()),
        ("CurrentBatteryV1Request", CurrentBatteryV1Request()),
        ("CurrentEGVGuiDataRequest", CurrentEGVGuiDataRequest()),
        ("ExtendedBolusStatusRequest", ExtendedBolusStatusRequest()),
        ("LastBolusStatusRequest", LastBolusStatusRequest()),
        ("LastBolusStatusV3Request", LastBolusStatusV3Request()),
        ("TempRateRequest", TempRateRequest()),
        ("TempRateStatusRequest", TempRateStatusRequest()),
        ("RemindersRequest", RemindersRequest()),
        ("ControlIQSleepScheduleRequest", ControlIQSleepScheduleRequest()),
        ("BasalIQStatusRequest", BasalIQStatusRequest()),
        ("BasalIQSettingsRequest", BasalIQSettingsRequest()),
        ("BasalIQAlertInfoRequest", BasalIQAlertInfoRequest()),
        ("CGMGlucoseAlertSettingsRequest", CGMGlucoseAlertSettingsRequest()),
        ("CGMRateAlertSettingsRequest", CGMRateAlertSettingsRequest()),
        ("CGMOORAlertSettingsRequest", CGMOORAlertSettingsRequest()),
        ("BleSoftwareInfoRequest", BleSoftwareInfoRequest()),
        ("GetG6TransmitterHardwareInfoRequest", GetG6TransmitterHardwareInfoRequest()),
        ("GetSavedG7PairingCodeRequest", GetSavedG7PairingCodeRequest()),
        ("HighestAamRequest", HighestAamRequest()),
        ("LocalizationRequest", LocalizationRequest()),
        ("PumpVersionBRequest", PumpVersionBRequest()),
        ("SecretMenuRequest", SecretMenuRequest()),
        ("UnknownMobiOpcode110Request", UnknownMobiOpcode110Request()),
        ("ExtendedBolusStatusV2Request", ExtendedBolusStatusV2Request()),
        ("CGMStatusRequest", CGMStatusRequest()),
        ("CgmStatusV2Request", CgmStatusV2Request()),
        ("CGMHardwareInfoRequest", CGMHardwareInfoRequest()),
    ]

    @Test(arguments: statusReads)
    func statusReadMatchesOracle(name: String, message: Message) throws {
        let txId: UInt8 = 11
        let oracle = try OracleRunner.encodePackets(txId: txId, messageName: name)
        let swift = try swiftPackets(message, txId: txId)
        #expect(swift == oracle, "\(name): swift=\(swift) oracle=\(oracle)")
    }

    /// HistoryLogRequest carries a 5-byte cargo (startLog uint32 + numberOfLogs byte).
    @Test func historyLogRequestMatchesOracle() throws {
        let oracle = try OracleRunner.encode(
            txId: 8, messageName: "HistoryLogRequest", json: "[1000, 10]").packets
        let swift = try swiftPackets(HistoryLogRequest(startLog: 1000, numberOfLogs: 10), txId: 8)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    /// IDPSettingsRequest carries a 1-byte idpId cargo.
    @Test func idpSettingsRequestMatchesOracle() throws {
        let oracle = try OracleRunner.encode(txId: 9, messageName: "IDPSettingsRequest", json: "[4]").packets
        let swift = try swiftPackets(IDPSettingsRequest(idpId: 4), txId: 9)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    /// IDPSegmentRequest carries a 2-byte [idpId, segmentIndex] cargo.
    @Test func idpSegmentRequestMatchesOracle() throws {
        let oracle = try OracleRunner.encode(txId: 10, messageName: "IDPSegmentRequest", json: "[4, 2]").packets
        let swift = try swiftPackets(IDPSegmentRequest(idpId: 4, segmentIndex: 2), txId: 10)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // MARK: - Authentication messages

    @Test func centralChallengeRequestMatchesOracle() throws {
        let challenge = try Hex.decode("00112233445566778899") // 10 bytes; first 8 used
        let msg = CentralChallengeRequest(appInstanceId: 0, centralChallenge: challenge)
        let oracle = try OracleRunner.encode(
            txId: 1, messageName: "CentralChallengeRequest",
            json: "{\"appInstanceId\":0,\"centralChallenge\":\"00112233445566778899\"}"
        ).packets
        #expect(try swiftPackets(msg, txId: 1) == oracle)
    }

    /// PumpChallengeRequest's 22-byte cargo spans two BLE packets — exercises chunking.
    @Test func pumpChallengeRequestMatchesOracleMultiPacket() throws {
        let hash = try Hex.decode("0102030405060708090a0b0c0d0e0f1011121314") // 20 bytes
        let msg = PumpChallengeRequest(appInstanceId: 0, pumpChallengeHash: hash)
        let oracle = try OracleRunner.encode(
            txId: 2, messageName: "PumpChallengeRequest",
            json: "{\"appInstanceId\":0,\"pumpChallengeHash\":\"0102030405060708090a0b0c0d0e0f1011121314\"}"
        ).packets
        #expect(oracle.count == 2)          // sanity: really multi-packet
        #expect(try swiftPackets(msg, txId: 2) == oracle)
    }

    // MARK: - JPAKE wire messages (framing only; EC-JPAKE bytes are non-deterministic)

    @Test func jpake1aRequestMatchesOracle() throws {
        let challenge = (0..<165).map { UInt8($0 & 0xFF) }
        let hex = Hex.encode(challenge)
        let msg = Jpake1aRequest(appInstanceId: 0, centralChallenge: challenge)
        let oracle = try OracleRunner.encode(
            txId: 0, messageName: "Jpake1aRequest",
            json: "{\"appInstanceId\":0,\"centralChallenge\":\"\(hex)\"}").packets
        #expect(try swiftPackets(msg, txId: 0) == oracle)
    }

    // Jpake3's two 1-arg constructors are ambiguous to the oracle's reflection encoder, so
    // assert its cargo directly (Packetize framing is validated by the other oracle tests).
    @Test func jpake3SessionKeyRequestCargo() {
        #expect(Jpake3SessionKeyRequest(challengeParam: 1).cargo == [0x01, 0x00])
        #expect(Jpake3SessionKeyRequest.props.opCode == 38)
    }

    @Test func jpake4KeyConfirmationRequestMatchesOracle() throws {
        let nonce = (0..<8).map { UInt8($0) }
        let reserved = [UInt8](repeating: 0, count: 8)
        let hashDigest = (0..<32).map { UInt8($0 + 100) }
        let msg = Jpake4KeyConfirmationRequest(appInstanceId: 0, nonce: nonce, reserved: reserved, hashDigest: hashDigest)
        let json = "{\"appInstanceId\":0,\"nonce\":\"\(Hex.encode(nonce))\",\"reserved\":\"\(Hex.encode(reserved))\",\"hashDigest\":\"\(Hex.encode(hashDigest))\"}"
        let oracle = try OracleRunner.encode(txId: 6, messageName: "Jpake4KeyConfirmationRequest", json: json).packets
        #expect(try swiftPackets(msg, txId: 6) == oracle)
    }

    // MARK: - Signed bolus flow

    /// Serializes a signed `message` with the shared test pairing code / pump time, matching
    /// the oracle env, and returns lowercase packet hex.
    private func swiftSignedPackets(_ message: Message, txId: UInt8) throws -> [String] {
        try Packetize.packetize(
            message,
            authenticationKey: Array(OracleRunner.testPairingCode.utf8),
            txId: txId,
            pumpTimeSinceReset: OracleRunner.testPumpTimeSinceReset,
            actionsAffectingInsulinDeliveryEnabled: true
        ).map { Hex.encode($0.build()) }
    }

    private func oracleSignedPackets(_ name: String, txId: UInt8, json: String = "{}") throws -> [String] {
        try OracleRunner.encode(
            txId: txId, messageName: name, json: json,
            pairingCode: OracleRunner.testPairingCode,
            pumpTimeSinceReset: OracleRunner.testPumpTimeSinceReset
        ).packets
    }

    @Test(arguments: [UInt8(0), 7, 200])
    func bolusPermissionRequestMatchesOracle(txId: UInt8) throws {
        let oracle = try oracleSignedPackets("BolusPermissionRequest", txId: txId)
        let swift = try swiftSignedPackets(BolusPermissionRequest(), txId: txId)
        #expect(swift == oracle, "txId=\(txId): swift=\(swift) oracle=\(oracle)")
    }

    @Test func cancelBolusRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("CancelBolusRequest", txId: 3, json: "[10650]")
        let swift = try swiftSignedPackets(CancelBolusRequest(bolusId: 10650), txId: 3)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func bolusPermissionReleaseRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("BolusPermissionReleaseRequest", txId: 4, json: "[10650]")
        let swift = try swiftSignedPackets(BolusPermissionReleaseRequest(bolusID: 10650), txId: 4)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func suspendPumpingRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SuspendPumpingRequest", txId: 5)
        let swift = try swiftSignedPackets(SuspendPumpingRequest(), txId: 5)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func resumePumpingRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("ResumePumpingRequest", txId: 6)
        let swift = try swiftSignedPackets(ResumePumpingRequest(), txId: 6)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setTempRateRequestMatchesOracle() throws {
        // 30 minutes at 150% — cargo: uint32 ms (30*60000) + LE uint16 percent.
        let oracle = try oracleSignedPackets("SetTempRateRequest", txId: 7, json: "[30, 150]")
        let swift = try swiftSignedPackets(try SetTempRateRequest(minutes: 30, percent: 150), txId: 7)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func stopTempRateRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("StopTempRateRequest", txId: 8)
        let swift = try swiftSignedPackets(StopTempRateRequest(), txId: 8)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func startG6SensorSessionRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("StartDexcomG6SensorSessionRequest", txId: 9, json: "[1234]")
        let swift = try swiftSignedPackets(StartDexcomG6SensorSessionRequest(sensorCode: 1234), txId: 9)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func stopCGMSensorSessionRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("StopDexcomCGMSensorSessionRequest", txId: 10)
        let swift = try swiftSignedPackets(StopDexcomCGMSensorSessionRequest(), txId: 10)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // SetSensorTypeRequest is cargo-asserted directly: upstream has ambiguous (int)/(CgmSensorType)
    // constructors, so the oracle's reflection encoder nondeterministically ClassCast-fails on it
    // (Java getConstructors() order). The signed-packetize path is covered by the other signed tests.
    @Test func setSensorTypeRequestCargo() {
        #expect(SetSensorTypeRequest(cgmSensorType: 2).cargo == [2])
        #expect(SetSensorTypeRequest.props.opCode == 0xC0 && SetSensorTypeRequest.props.signed)
    }

    @Test func setG7PairingCodeRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetDexcomG7PairingCodeRequest", txId: 12, json: "[9876]")
        let swift = try swiftSignedPackets(SetDexcomG7PairingCodeRequest(pairingCode: 9876), txId: 12)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func remoteCarbEntryRequestMatchesOracle() throws {
        // positional: carbs, unknown, pumpTimeSecondsSinceBoot, bolusId
        let oracle = try oracleSignedPackets("RemoteCarbEntryRequest", txId: 13, json: "[45, 0, 461500000, 10650]")
        let swift = try swiftSignedPackets(
            RemoteCarbEntryRequest(carbs: 45, unknown: 0, pumpTimeSecondsSinceBoot: 461_500_000, bolusId: 10650), txId: 13)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func remoteBgEntryRequestMatchesOracle() throws {
        // positional: bg, useForCgmCalibration, isAutopopBg, pumpTimeSecondsSinceBoot, bolusId
        let oracle = try oracleSignedPackets("RemoteBgEntryRequest", txId: 14, json: "[120, false, false, 461500000, 10650]")
        let swift = try swiftSignedPackets(
            RemoteBgEntryRequest(bg: 120, useForCgmCalibration: false, isAutopopBg: false,
                                 pumpTimeSecondsSinceBoot: 461_500_000, bolusId: 10650), txId: 14)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func playSoundRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("PlaySoundRequest", txId: 15)
        let swift = try swiftSignedPackets(PlaySoundRequest(), txId: 15)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setPumpSoundsRequestMatchesOracle() throws {
        // 8-arg: quickBolus, general, reminder, alert, alarm, cgmA, cgmB, changeBitmask
        let oracle = try oracleSignedPackets("SetPumpSoundsRequest", txId: 16, json: "[0, 1, 2, 3, 0, 1, 2, 4]")
        let swift = try swiftSignedPackets(
            SetPumpSoundsRequest(quickBolusAnnunRaw: 0, generalAnnunRaw: 1, reminderAnnunRaw: 2,
                                 alertAnnunRaw: 3, alarmAnnunRaw: 0, cgmAlertAnnunA: 1,
                                 cgmAlertAnnunB: 2, changeBitmaskRaw: 4), txId: 16)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // ChangeTimeDate / CgmSupportPackageStatus are cargo-asserted: upstream has multiple/ enum ctors
    // (long/Instant/byte[]; DeviceType) that make the oracle's reflection encoder nondeterministic.
    @Test func changeTimeDateAndCgmSupportCargos() {
        #expect(ChangeTimeDateRequest(tandemEpochTime: 461_500_000).cargo == [96, 238, 129, 27])
        #expect(CgmSupportPackageStatusRequest(deviceType: 1).cargo == [1])
    }

    @Test func setLowInsulinAlertRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetLowInsulinAlertRequest", txId: 18, json: "[20]")
        let swift = try swiftSignedPackets(SetLowInsulinAlertRequest(insulinThreshold: 20), txId: 18)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setAutoOffAlertRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetAutoOffAlertRequest", txId: 19, json: "[true, 720, 0]")
        let swift = try swiftSignedPackets(
            SetAutoOffAlertRequest(enableAutoOff: true, autoOffDuration: 720, bitmask: 0), txId: 19)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // SetModesRequest cargo-asserted: upstream (int)/(byte[]) ctors make oracle reflection
    // nondeterministically pick byte[] and ClassCast-fail.
    @Test func setModesRequestCargo() {
        #expect(SetModesRequest(bitmap: 2).cargo == [2])
        #expect(SetModesRequest.props.opCode == 0xCC && SetModesRequest.props.modifiesInsulinDelivery)
        // ModeCommand wire values must match the pump firmware / Tandem Source schema exactly.
        #expect(SetModesRequest.ModeCommand.sleepModeOn.bitmap == 1)
        #expect(SetModesRequest.ModeCommand.sleepModeOff.bitmap == 2)
        #expect(SetModesRequest.ModeCommand.exerciseModeOn.bitmap == 3)
        #expect(SetModesRequest.ModeCommand.exerciseModeOff.bitmap == 4)
        // The `mode:` convenience serializes the same cargo as the raw bitmap init.
        #expect(SetModesRequest(mode: .exerciseModeOn).cargo == [3])
        #expect(SetModesRequest(mode: .sleepModeOn).cargo == [1])
        // Round-trip: bitmap decodes back to the symbolic command.
        #expect(SetModesRequest(bitmap: 4).command == .exerciseModeOff)
        #expect(SetModesRequest.ModeCommand.fromBitmap(99) == nil)
    }

    @Test func setActiveIDPRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetActiveIDPRequest", txId: 21, json: "[4, 0]")
        let swift = try swiftSignedPackets(SetActiveIDPRequest(idpId: 4, profileIndex: 0), txId: 21)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setMaxBolusLimitRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetMaxBolusLimitRequest", txId: 22, json: "[25000]")
        let swift = try swiftSignedPackets(try SetMaxBolusLimitRequest(maxBolusMilliunits: 25000), txId: 22)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setMaxBasalLimitRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetMaxBasalLimitRequest", txId: 23, json: "[15000]")
        let swift = try swiftSignedPackets(try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 15000), txId: 23)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    /// Empty-cargo cartridge/fill workflow commands (signed).
    static let cartridgeFillEmpty: [(String, Message)] = [
        ("EnterChangeCartridgeModeRequest", EnterChangeCartridgeModeRequest()),
        ("ExitChangeCartridgeModeRequest", ExitChangeCartridgeModeRequest()),
        ("EnterFillTubingModeRequest", EnterFillTubingModeRequest()),
        ("ExitFillTubingModeRequest", ExitFillTubingModeRequest()),
        ("PrimeTubingSuspendRequest", PrimeTubingSuspendRequest()),
    ]
    @Test(arguments: cartridgeFillEmpty)
    func cartridgeFillEmptyRequestMatchesOracle(name: String, message: Message) throws {
        let oracle = try oracleSignedPackets(name, txId: 24)
        let swift = try swiftSignedPackets(message, txId: 24)
        #expect(swift == oracle, "\(name): swift=\(swift) oracle=\(oracle)")
    }

    @Test func fillCannulaRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("FillCannulaRequest", txId: 25, json: "[300]")
        let swift = try swiftSignedPackets(try FillCannulaRequest(primeSize: 300), txId: 25)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // MARK: - A2 settings / IDP CRUD / dangerous — byte-exact signed request parity

    @Test func cgmOutOfRangeAlertRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("CgmOutOfRangeAlertRequest", txId: 26, json: "[true, 20, 0]")
        let swift = try swiftSignedPackets(CgmOutOfRangeAlertRequest(enable: true, alertDelay: 20, bitmask: 0), txId: 26)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func cgmRiseFallAlertRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("CgmRiseFallAlertRequest", txId: 27, json: "[1, true, 3, 0]")
        let swift = try swiftSignedPackets(CgmRiseFallAlertRequest(alertType: 1, enable: true, mgPerDl: 3, bitmask: 0), txId: 27)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func changeControlIQSettingsRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("ChangeControlIQSettingsRequest", txId: 28, json: "[true, 150, 40]")
        let swift = try swiftSignedPackets(ChangeControlIQSettingsRequest(enabled: true, weightLbs: 150, totalDailyInsulinUnits: 40), txId: 28)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func additionalBolusRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("AdditionalBolusRequest", txId: 29, json: "[10650, 0]")
        let swift = try swiftSignedPackets(AdditionalBolusRequest(bolusID: 10650, reserve: 0), txId: 29)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setSiteChangeReminderRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetSiteChangeReminderRequest", txId: 30, json: "[true, 3, 480, 0]")
        let swift = try swiftSignedPackets(SetSiteChangeReminderRequest(enable: true, dayCount: 3, timeOfDayMinutes: 480, bitmask: 0), txId: 30)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func setPumpAlertSnoozeRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SetPumpAlertSnoozeRequest", txId: 31, json: "[true, 30]")
        let swift = try swiftSignedPackets(SetPumpAlertSnoozeRequest(snoozeEnabled: true, snoozeDurationMins: 30), txId: 31)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func deleteIDPRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("DeleteIDPRequest", txId: 32, json: "[4, 0]")
        let swift = try swiftSignedPackets(DeleteIDPRequest(idpId: 4, profileIndex: 0), txId: 32)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func renameIDPRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("RenameIDPRequest", txId: 33, json: "[4, 0, \"Weekend\"]")
        let swift = try swiftSignedPackets(RenameIDPRequest(idpId: 4, profileIndex: 0, profileName: "Weekend"), txId: 33)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // --- Mobi-workflow messages that previously lacked any test (Plan A / A1) ---

    // SetG6TransmitterIdRequest: 6-char id written into a 16-byte field (6 chars + 10 pad). The
    // oracle's reflection is unreliable for the String ctor here, so assert the cargo layout directly.
    @Test func setG6TransmitterIdRequestCargo() {
        let m = SetG6TransmitterIdRequest(txId: "123456")
        #expect(m.cargo == Array("123456".utf8) + [UInt8](repeating: 0, count: 10))
        #expect(SetG6TransmitterIdRequest.props.opCode == 0xB0 && SetG6TransmitterIdRequest.props.signed)
        #expect(SetG6TransmitterIdRequest.props.size == 16)
    }

    @Test func cgmHighLowAlertRequestMatchesOracle() throws {
        // ctor: alertType, threshold, repeatDurationMinutes, enableAlert, bitmask
        let oracle = try oracleSignedPackets("CgmHighLowAlertRequest", txId: 40, json: "[1, 200, 30, true, 0]")
        let swift = try swiftSignedPackets(
            CgmHighLowAlertRequest(alertType: 1, threshold: 200, repeatDurationMinutes: 30,
                                   enableAlert: true, bitmask: 0), txId: 40)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // CreateIDPRequest / SetIDPSegmentRequest have many positional args (incl. a name string and a
    // UInt32 carb ratio); the oracle's reflection ctor is nondeterministic for them, so assert the
    // built cargo's shape + key fields + props instead (locks the byte layout as a change-detector).
    @Test func createIDPRequestShape() {
        let m = CreateIDPRequest(name: "Test", firstSegmentProfileCarbRatio: 12000,
                                 firstSegmentProfileBasalRate: 100, firstSegmentProfileTargetBG: 110,
                                 firstSegmentProfileISF: 50, profileInsulinDuration: 300,
                                 timeSegmentBitmask: 1, bolusSettingsBitmask: 0, carbEntry: 1, idpSourceId: 0)
        #expect(m.cargo.count == 35)                                  // matches props.size
        #expect(Array(m.cargo.prefix(4)) == Array("Test".utf8))       // name in the first 17 bytes
        #expect(CreateIDPRequest.props.opCode == 0xE6)
        #expect(CreateIDPRequest.props.signed && CreateIDPRequest.props.modifiesInsulinDelivery)
    }

    @Test func setIDPSegmentRequestShape() {
        let m = SetIDPSegmentRequest(idpId: 4, profileIndex: 0, segmentIndex: 1, operationId: 2,
                                     profileStartTime: 0, profileBasalRate: 100, profileCarbRatio: 12000,
                                     profileTargetBG: 110, profileISF: 50, idpStatusId: 0)
        #expect(m.cargo.count == 17)                                  // matches props.size
        #expect(Array(m.cargo.prefix(4)) == [4, 0, 1, 2])             // idpId, profileIndex, segIdx, opId
        #expect(SetIDPSegmentRequest.props.opCode == 0xAA && SetIDPSegmentRequest.props.signed)
    }

    // SetIDPSettingsRequest's upstream ctor takes a ChangeType enum → oracle can't build it from an
    // int; assert cargo directly. [idpId, profileIndex] + LE u16 duration + [carbEntry, changeTypeId].
    @Test func setIDPSettingsRequestCargo() {
        #expect(SetIDPSettingsRequest(idpId: 4, profileIndex: 0, profileInsulinDuration: 300,
                                      profileCarbEntry: 1, changeTypeId: 0).cargo == [4, 0, 44, 1, 1, 0])
    }

    @Test func factoryResetRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("FactoryResetRequest", txId: 35, json: "[12345, 67890]")
        let swift = try swiftSignedPackets(FactoryResetRequest(key: 12345, serialNumber: 67890), txId: 35)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    @Test func factoryResetBRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("FactoryResetBRequest", txId: 36, json: "[12345, 67890, false]")
        let swift = try swiftSignedPackets(FactoryResetBRequest(key: 12345, serialNumber: 67890, enableShelfMode: false), txId: 36)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    static let emptyDangerous: [(String, Message)] = [
        ("ActivateShelfModeRequest", ActivateShelfModeRequest()),
        ("DisconnectPumpRequest", DisconnectPumpRequest()),
        ("UserInteractionRequest", UserInteractionRequest()),
    ]
    @Test(arguments: emptyDangerous)
    func emptyDangerousRequestMatchesOracle(name: String, message: Message) throws {
        let oracle = try oracleSignedPackets(name, txId: 37)
        let swift = try swiftSignedPackets(message, txId: 37)
        #expect(swift == oracle, "\(name): swift=\(swift) oracle=\(oracle)")
    }

    @Test func sendTipsControlGenericTestRequestMatchesOracle() throws {
        let oracle = try oracleSignedPackets("SendTipsControlGenericTestRequest", txId: 38, json: "[1, 2, 3, 4, 5, 6]")
        let swift = try swiftSignedPackets(SendTipsControlGenericTestRequest(param1: 1, param2: 2, param3: 3, param4: 4, param5: 5, param6: 6), txId: 38)
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }

    // Parameterized CURRENT_STATUS reads — cargo-asserted directly. Several have enum constructors
    // (DeviceType, mcuType, SupportedFeatureIndex) that make the oracle's reflection encoder
    // nondeterministically ClassCast-fail; the packetize framing is covered by the signed/empty tests.
    @Test func paramStatusReadCargos() {
        #expect(BolusPermissionChangeReasonRequest(bolusId: 10650).cargo == [154, 41])   // LE 0x299A
        #expect(CommonSoftwareInfoRequest(mcuType: 0).cargo == [0])
        #expect(CreateHistoryLogRequest(numberOfLogs: 100).cargo == [100, 0, 0, 0])
        #expect(StreamDataReadinessRequest(streamDataType: 1).cargo == [1])
        #expect(PumpFeaturesV2Request(input: 2).cargo == [2])
    }

    /// byte[]-param requests are cargo-asserted directly (oracle reflection can't take opaque arrays).
    @Test func opaqueArrayRequestCargos() {
        #expect(SetQuickBolusSettingsRequest(enabled: true, modeRaw: 1, magic: [1, 2, 3, 4, 5]).cargo == [1, 1, 1, 2, 3, 4, 5])
        #expect(SetSleepScheduleRequest(slot: 0, schedule: [1, 2, 3, 4, 5, 6], flag: 1).cargo == [0, 1, 2, 3, 4, 5, 6, 1])
        #expect(StreamDataPreflightRequest(streamType: 2, length: 16, hmac: [9, 9]).cargo == [2, 16, 0, 9, 9])
    }

    /// The crown jewel: a 1.0u standard bolus initiate, signed, byte-exact vs the oracle.
    @Test func initiateBolusRequestMatchesOracle() throws {
        // positional args: totalVolume, bolusID, bolusTypeBitmask, foodVolume,
        // correctionVolume, bolusCarbs, bolusBG, bolusIOB
        let json = "[1000, 42, 1, 0, 0, 0, 0, 0]"
        let oracle = try oracleSignedPackets("InitiateBolusRequest", txId: 9, json: json)
        let swift = try swiftSignedPackets(
            InitiateBolusRequest(totalVolume: 1000, bolusID: 42, bolusTypeBitmask: 1),
            txId: 9
        )
        #expect(swift == oracle, "swift=\(swift) oracle=\(oracle)")
    }
}
