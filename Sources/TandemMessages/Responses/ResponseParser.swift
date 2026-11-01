import Foundation

/// Parses a reassembled inbound frame into a typed `ResponseMessage`.
///
/// Frame layout (produced by `Packetize`, reassembled by `TandemLink.PacketReassembler`):
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
        // Signed-response HMAC verification failures (fail-closed).
        case signatureMissing(opcode: UInt8)  // signed response but the 24-byte auth trailer is absent/short
        case signatureKeyUnavailable(opcode: UInt8)  // signed response but no session key to verify against
        case signatureInvalid(opcode: UInt8)  // trailer present but the HMAC-SHA1 does not verify
    }

    public struct Parsed {
        public let opCode: UInt8
        public let txId: UInt8
        public let message: any Message
        /// The pump time (seconds since reset) in a signed reply's trailer, set only when the trailer's
        /// HMAC verified. The pump writes its own current time there, not the request's, so the
        /// connection layer can tell an old authentic reply from a fresh one. Upstream doesn't read it.
        public let signedPumpTime: UInt32?

        init(opCode: UInt8, txId: UInt8, message: any Message, signedPumpTime: UInt32? = nil) {
            self.opCode = opCode
            self.txId = txId
            self.message = message
            self.signedPumpTime = signedPumpTime
        }
    }

    /// A response registered for dispatch. `signed`/`expectedSize` are derived from the type's
    /// `MessageProps`, so registration is a single `add(_:)` per response.
    struct Registration {
        let make: @Sendable ([UInt8]) -> any Message
        let expectedSize: Int?  // nil = variable-size / stream frame
        let signed: Bool
        /// Builds the reply's unverified form when its trailer doesn't verify, instead of throwing.
        /// Only the CONTROL op-77 error has one: a caller must still see that the pump answered,
        /// but never as a definite refusal.
        var unverified: (@Sendable ([UInt8], UnverifiedErrorResponse.Reason) -> any Message)?
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
        // The CONTROL op-77 error: the same cargo as the CURRENT_STATUS one, but it answers a signed
        // write and carries the 24-byte trailer (upstream `PacketArrayList` checks its HMAC whenever
        // the expected reply is signed; captured from P1 as `4d <txId> 1a 0000 <time(4)> <hmac(20)>`).
        func addSignedControlError() {
            let p = ErrorResponse.props
            r[Key(characteristic: .control, opCode: p.opCode)] = Registration(
                make: { ErrorResponse(cargo: $0) },
                expectedSize: p.size,
                signed: true,
                unverified: { UnverifiedErrorResponse(cargo: $0, reason: $1) })
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
        // Same op-77 error reply also arrives on CONTROL when a signed control write is NACKed
        // (echoing the failing request's txId). It is HMAC-verified like any signed reply; one that
        // doesn't verify parses as `UnverifiedErrorResponse`. Additive key — currentStatus untouched.
        addSignedControlError()
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
    /// - Parameters:
    ///   - authenticationKey: the per-session HMAC key (JPAKE-derived / legacy pairing code) used to
    ///     VERIFY a signed response's auth trailer. Defaults to empty — an empty key on a signed response
    ///     fails CLOSED (`.signatureKeyUnavailable`), never fail-open. Production MUST pass the real key.
    ///   - verifySignature: set false ONLY in decode/dispatch tests that use zero/placeholder HMACs; leave
    ///     true (the default) everywhere else so forged/absent signatures are rejected.
    public static func parse(
        frame: [UInt8], characteristic: Characteristic,
        authenticationKey: [UInt8] = [], verifySignature: Bool = true
    ) throws -> Parsed {
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
        // A signed response carries a 24-byte auth trailer (4-byte pumpTimeSinceReset + 20-byte
        // HMAC-SHA1). Upstream (PacketArrayList.validate) recomputes and compares that HMAC and REJECTS a
        // mismatch; the earlier Swift port dropped the check (CRC-16 alone is not cryptographic), so a
        // CRC-valid FORGED signed response — e.g. a forged InitiateBolus NACK — was accepted, releasing the
        // durable delivery lock and opening a double-dose window. Verify BEFORE stripping/trusting the cargo,
        // fail CLOSED, constant-time. Byte-exact with the oracle: the HMAC covers messageData
        // (`[opcode,txId,length] + cargo`) minus its last 20 bytes; the last 20 bytes are the expected mac.
        // Signed responses append a 24-byte HMAC to the cargo; strip it for field parsing. A frame
        // too short to hold one has nothing to strip (verification below rejects it).
        let cargoLen = reg.signed && length >= 24 ? length - 24 : length
        let cargo = Array(body[3..<(3 + cargoLen)])
        let messageData = Array(body[0..<(3 + length)])
        var signedPumpTime: UInt32?
        if reg.signed && verifySignature,
            let failure = signatureFailure(messageData: messageData, key: authenticationKey)
        {
            if let unverified = reg.unverified {
                return Parsed(opCode: opCode, txId: txId, message: unverified(cargo, failure))
            }
            switch failure {
            case .trailerMissing: throw ParseError.signatureMissing(opcode: opCode)
            case .keyUnavailable: throw ParseError.signatureKeyUnavailable(opcode: opCode)
            case .hmacMismatch: throw ParseError.signatureInvalid(opcode: opCode)
            }
        } else if reg.signed && verifySignature {
            // Verified: the trailer is the last 24 bytes, pump time (4, little-endian) then the HMAC.
            signedPumpTime = Bytes.readUint32(messageData, messageData.count - 24)
        }
        // Require at least the expected cargo, but tolerate extra trailing bytes: newer pump
        // firmware (e.g. Control-IQ+ 7.10.x EGV) appends fields we don't parse.
        if let expected = reg.expectedSize, cargo.count < expected {
            throw ParseError.cargoLengthMismatch(opcode: opCode, expected: expected, got: cargo.count)
        }
        return Parsed(opCode: opCode, txId: txId, message: reg.make(cargo), signedPumpTime: signedPumpTime)
    }

    /// Why a signed reply's trailer doesn't verify, or nil when it does. `messageData` is
    /// `[opcode, txId, length] + cargo`; the HMAC covers all of it but its last 20 bytes.
    static func signatureFailure(messageData: [UInt8], key: [UInt8]) -> UnverifiedErrorResponse.Reason? {
        guard messageData.count >= 3 + 24 else { return .trailerMissing }
        guard !key.isEmpty else { return .keyUnavailable }
        let signedOver = Array(messageData[0..<(messageData.count - 20)])
        let expected = Array(messageData[(messageData.count - 20)...])
        return Packetize.isValidHmacSha1(mac: expected, data: signedOver, key: key) ? nil : .hmacMismatch
    }
}
