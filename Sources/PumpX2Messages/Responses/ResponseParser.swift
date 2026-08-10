import Foundation

/// Parses a reassembled inbound frame into a typed `ResponseMessage`.
///
/// Frame layout (produced by `Packetize`, reassembled by `PumpX2BLE.PacketReassembler`):
/// `[opcode, txId, length, cargo(length bytes), crc0, crc1]`. Validates the CRC-16 and cargo
/// length before dispatching.
///
/// **Dispatch is keyed by (characteristic, opcode), not opcode alone.** Tandem reuses opcodes
/// across BLE characteristics — e.g. opcode 165 is `LastBolusStatusV2Response` on CURRENT_STATUS
/// but `SetTempRateResponse` on CONTROL — so the caller must pass the characteristic the frame
/// arrived on (the BLE layer always knows it: `didReceiveFrame(_:on:)`).
public enum ResponseParser {
    public enum ParseError: Error, Equatable {
        case frameTooShort
        case crcMismatch(expected: [UInt8], actual: [UInt8])
        case unknownOpcode(UInt8)
        case cargoLengthMismatch(opcode: UInt8, expected: Int, got: Int)
    }

    public struct Parsed {
        public let opCode: UInt8
        public let txId: UInt8
        public let message: any Message
    }

    /// A response registered for dispatch. `signed`/`expectedSize` are derived from the type's
    /// `MessageProps`, so registration is a single `add(_:)` per response.
    struct Registration {
        let make: @Sendable ([UInt8]) -> any Message
        let expectedSize: Int?   // nil = variable-size / stream frame
        let signed: Bool
    }

    /// Composite dispatch key: opcodes are only unique per characteristic.
    struct Key: Hashable {
        let characteristic: Characteristic
        let opCode: UInt8
    }

    /// Registry of known (characteristic, opcode) → how to build/parse it. Extend via `add(_:)`.
    static let registry: [Key: Registration] = {
        var r: [Key: Registration] = [:]
        func add<M: ResponseMessage>(_ type: M.Type) {
            let p = M.props
            r[Key(characteristic: p.characteristic, opCode: p.opCode)] = Registration(
                make: { M(cargo: $0) },
                expectedSize: (p.variableSize || p.stream) ? nil : p.size,
                signed: p.signed)
        }
        // Register a response under an OVERRIDDEN characteristic (its build/size/signed rules unchanged).
        // Used for an opcode the pump reuses across characteristics. Additive: a NEW (characteristic,
        // opcode) key that no existing dispatch or oracle vector reaches, so byte-parity is untouched.
        func add<M: ResponseMessage>(_ type: M.Type, on characteristic: Characteristic) {
            let p = M.props
            r[Key(characteristic: characteristic, opCode: p.opCode)] = Registration(
                make: { M(cargo: $0) },
                expectedSize: (p.variableSize || p.stream) ? nil : p.size,
                signed: p.signed)
        }
        // CURRENT_STATUS reads
        add(ApiVersionResponse.self)
        add(NonControlIQIOBResponse.self)
        add(ControlIQInfoV2Response.self)
        add(LastBGResponse.self)
        add(PumpVersionResponse.self)
        add(PumpSettingsResponse.self)
        add(PumpGlobalsResponse.self)
        add(ProfileStatusResponse.self)
        add(CurrentActiveIdpValuesResponse.self)
        add(GlobalMaxBolusSettingsResponse.self)
        add(BasalLimitSettingsResponse.self)
        add(ControlIQInfoV1Response.self)
        add(PumpFeaturesV1Response.self)
        add(LoadStatusResponse.self)
        add(IDPSettingsResponse.self)
        add(IDPSegmentResponse.self)
        add(ExtendedBolusStatusV2Response.self)
        add(CGMStatusResponse.self)
        add(CgmStatusV2Response.self)
        add(CGMHardwareInfoResponse.self)
        add(HomeScreenMirrorResponse.self)
        add(TempRateStatusResponse.self)
        add(CurrentBatteryV1Response.self)
        add(ControlIQIOBResponse.self)
        add(InsulinStatusResponse.self)
        add(CurrentBatteryV2Response.self)
        add(CurrentEgvGuiDataV2Response.self)
        add(CurrentBasalStatusResponse.self)
        add(LastBolusStatusV2Response.self)
        add(TimeSinceResetResponse.self)
        add(BolusCalcDataSnapshotResponse.self)
        add(HistoryLogStatusResponse.self)
        add(HistoryLogResponse.self)
        add(AlertStatusResponse.self)
        add(AlarmStatusResponse.self)
        add(CGMAlertStatusResponse.self)
        add(ReminderStatusResponse.self)
        add(MalfunctionBitmaskStatusResponse.self)
        add(CurrentBolusStatusResponse.self)
        add(ActiveAamBitsResponse.self)
        add(BasalIQAlertInfoResponse.self)
        add(BasalIQSettingsResponse.self)
        add(BasalIQStatusResponse.self)
        add(BleSoftwareInfoResponse.self)
        add(BolusPermissionChangeReasonResponse.self)
        add(CGMGlucoseAlertSettingsResponse.self)
        add(CGMOORAlertSettingsResponse.self)
        add(CGMRateAlertSettingsResponse.self)
        add(CgmSupportPackageStatusResponse.self)
        add(CommonSoftwareInfoResponse.self)
        add(ControlIQSleepScheduleResponse.self)
        add(CreateHistoryLogResponse.self)
        add(CurrentEGVGuiDataResponse.self)
        add(ExtendedBolusStatusResponse.self)
        add(GetG6TransmitterHardwareInfoResponse.self)
        add(GetSavedG7PairingCodeResponse.self)
        add(HighestAamResponse.self)
        add(LastBolusStatusResponse.self)
        add(LastBolusStatusV3Response.self)
        add(LocalizationResponse.self)
        add(PumpFeaturesV2Response.self)
        add(PumpVersionBResponse.self)
        add(RemindersResponse.self)
        add(SecretMenuResponse.self)
        add(StreamDataReadinessResponse.self)
        add(UnknownMobiOpcode110Response.self)
        add(TempRateResponse.self)
        add(ErrorResponse.self)
        // D2 (Addendum G): the same op-77 error reply also arrives on CONTROL when a signed control write
        // is NACKed (echoing the failing request's txId). Register the control variant so it decodes as an
        // ErrorResponse instead of `unknownOpcode`. Additive new key — the currentStatus variant is untouched.
        add(ErrorResponse.self, on: .control)
        // AUTHORIZATION — legacy (V1 / 16-char) pairing replies. The modern JPAKE pairing replies
        // (op 33/35/37/39/41) are parsed inline by PairingCoordinator and are intentionally NOT
        // registered here; these two are registered for oracle parity + reuse.
        add(CentralChallengeResponse.self)
        add(PumpChallengeResponse.self)
        // HISTORY_LOG (variable-size stream)
        add(HistoryLogStreamResponse.self)
        // CONTROL_STREAM state responses (A3) — one representative per opcode (upstream mirrors this)
        add(EnterChangeCartridgeModeStateStreamResponse.self)
        add(DetectingCartridgeStateStreamResponse.self)
        add(FillTubingStateStreamResponse.self)
        add(FillCannulaStateStreamResponse.self)
        add(ExitFillTubingModeStateStreamResponse.self)
        // CONTROL responses (signed)
        add(BolusPermissionResponse.self)
        add(InitiateBolusResponse.self)
        add(DismissNotificationResponse.self)
        add(SuspendPumpingResponse.self)
        add(ResumePumpingResponse.self)
        add(SetTempRateResponse.self)
        add(StopTempRateResponse.self)
        add(CancelBolusResponse.self)
        add(BolusPermissionReleaseResponse.self)
        add(RemoteCarbEntryResponse.self)
        add(RemoteBgEntryResponse.self)
        add(PlaySoundResponse.self)
        add(SetPumpSoundsResponse.self)
        add(ChangeTimeDateResponse.self)
        add(SetMaxBolusLimitResponse.self)
        add(SetMaxBasalLimitResponse.self)
        add(ActivateShelfModeResponse.self)
        add(AdditionalBolusResponse.self)
        add(CgmHighLowAlertResponse.self)
        add(CgmOutOfRangeAlertResponse.self)
        add(CgmRiseFallAlertResponse.self)
        add(ChangeControlIQSettingsResponse.self)
        add(CreateIDPResponse.self)
        add(DeleteIDPResponse.self)
        add(DisconnectPumpResponse.self)
        add(FactoryResetBResponse.self)
        add(FactoryResetResponse.self)
        add(RenameIDPResponse.self)
        add(SendTipsControlGenericTestResponse.self)
        add(SetBgReminderResponse.self)
        add(SetG6TransmitterIdResponse.self)
        add(SetIDPSegmentResponse.self)
        add(SetIDPSettingsResponse.self)
        add(SetMissedMealBolusReminderResponse.self)
        add(SetPumpAlertSnoozeResponse.self)
        add(SetQuickBolusSettingsResponse.self)
        add(SetSiteChangeReminderResponse.self)
        add(SetSleepScheduleResponse.self)
        add(StreamDataPreflightResponse.self)
        add(UserInteractionResponse.self)
        add(EnterChangeCartridgeModeResponse.self)
        add(ExitChangeCartridgeModeResponse.self)
        add(EnterFillTubingModeResponse.self)
        add(ExitFillTubingModeResponse.self)
        add(FillCannulaResponse.self)
        add(PrimeTubingSuspendResponse.self)
        add(SetLowInsulinAlertResponse.self)
        add(SetAutoOffAlertResponse.self)
        add(SetModesResponse.self)
        add(SetActiveIDPResponse.self)
        add(StartDexcomG6SensorSessionResponse.self)
        add(StopDexcomCGMSensorSessionResponse.self)
        add(SetSensorTypeResponse.self)
        add(SetDexcomG7PairingCodeResponse.self)
        return r
    }()

    /// Validates CRC + length and dispatches to the matching response type for the characteristic
    /// the frame arrived on.
    public static func parse(frame: [UInt8], characteristic: Characteristic) throws -> Parsed {
        guard frame.count >= 5 else { throw ParseError.frameTooShort }
        let body = Array(frame[0..<(frame.count - 2)])
        let crc = Array(frame[(frame.count - 2)...])
        let expectedCRC = Bytes.calculateCRC16(body)
        guard crc == expectedCRC else { throw ParseError.crcMismatch(expected: expectedCRC, actual: crc) }

        let opCode = frame[0]
        let txId = frame[1]
        let length = Int(frame[2])
        guard 3 + length <= body.count else {
            throw ParseError.cargoLengthMismatch(opcode: opCode, expected: length, got: body.count - 3)
        }
        guard let reg = registry[Key(characteristic: characteristic, opCode: opCode)] else {
            throw ParseError.unknownOpcode(opCode)
        }
        // Signed responses append a 24-byte HMAC to the cargo; strip it for field parsing.
        let cargoLen = reg.signed ? max(0, length - 24) : length
        let cargo = Array(body[3..<(3 + cargoLen)])
        // Require at least the expected cargo, but tolerate extra trailing bytes: newer pump
        // firmware (e.g. Control-IQ+ 7.10.x EGV) appends fields we don't parse.
        if let expected = reg.expectedSize, cargo.count < expected {
            throw ParseError.cargoLengthMismatch(opcode: opCode, expected: expected, got: cargo.count)
        }
        return Parsed(opCode: opCode, txId: txId, message: reg.make(cargo))
    }
}
