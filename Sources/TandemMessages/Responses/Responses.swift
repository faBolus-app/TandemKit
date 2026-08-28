import Foundation

/// Inbound (pump → app) response messages. Ports of `response/**`. Each parses its cargo in
/// `init(cargo:)`; parsing is validated byte-exact by encoding a response through the oracle
/// and round-tripping it back (see OracleParityTests).
public protocol ResponseMessage: Message {
    init(cargo: [UInt8])
}

/// Pump API version (major/minor). `response/currentStatus/ApiVersionResponse` (opcode 33, 4 bytes).
/// The API version identifies the pump family — t:slim X2 is 2.x–3.4, **Mobi is 3.5+** (mirrors
/// jwoglom `KnownApiVersion`), so this is a first-class pump-model signal.
public struct ApiVersionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 33, size: 4, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var majorVersion: Int = 0
    public private(set) var minorVersion: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 4 {
            majorVersion = Bytes.readShort(raw, 0)
            minorVersion = Bytes.readShort(raw, 2)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = ApiVersionResponse(cargo: raw) }
    /// True when the pump is a Tandem Mobi (API 3.5+); t:slim X2 is 2.x–3.4.
    public var isMobi: Bool { majorVersion > 3 || (majorVersion == 3 && minorVersion >= 5) }
}

/// IOB read for non-Control-IQ pumps. `response/currentStatus/NonControlIQIOBResponse` (op 39, 12B).
public struct NonControlIQIOBResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 39, size: 12, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var iob: UInt32 = 0                 // milliunits
    public private(set) var timeRemainingSeconds: UInt32 = 0
    public private(set) var totalIOB: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 12 {
            iob = Bytes.readUint32(raw, 0)
            timeRemainingSeconds = Bytes.readUint32(raw, 4)
            totalIOB = Bytes.readUint32(raw, 8)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = NonControlIQIOBResponse(cargo: raw) }
    public var iobUnits: Double { Double(iob) / 1000.0 }
}

/// Control-IQ info (closed-loop state, current user mode). `response/currentStatus/ControlIQInfoV2Response`
/// (op 179, 19B). `currentUserModeType`/`controlStateType` expose Sleep/Exercise + CIQ activity.
public struct ControlIQInfoV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 179, size: 19, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var closedLoopEnabled = false
    public private(set) var currentUserModeType = 0
    public private(set) var controlStateType = 0
    public private(set) var exerciseChoice = 0
    public private(set) var exerciseTimeRemainingSeconds: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 19 {
            closedLoopEnabled = raw[0] != 0
            currentUserModeType = Int(raw[5])
            controlStateType = Int(raw[9])
            exerciseChoice = Int(raw[10])
            exerciseTimeRemainingSeconds = Bytes.readUint32(raw, 15)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = ControlIQInfoV2Response(cargo: raw) }
}

/// Last fingerstick blood-glucose entered on the pump. `response/currentStatus/LastBGResponse` (op 51, 7B).
public struct LastBGResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 51, size: 7, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bgTimestamp: UInt32 = 0
    public private(set) var bgValue: Int = 0
    public private(set) var bgSourceId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 7 {
            bgTimestamp = Bytes.readUint32(raw, 0)
            bgValue = Bytes.readShort(raw, 4)
            bgSourceId = Int(raw[6])
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = LastBGResponse(cargo: raw) }
}

/// Ack for a suspend-pumping command (signed). `response/control/SuspendPumpingResponse` (op 0x9D, 1B).
public struct SuspendPumpingResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x9D, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never default to status 0 (== accepted). Unreachable
        // via ResponseParser (length-guarded + HMAC-verified first), but a direct caller must not decode
        // an empty/truncated frame as an ACCEPTED suspend.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SuspendPumpingResponse(cargo: raw) }
    /// status 0 = accepted.
    public var accepted: Bool { status == 0 }
}

/// Ack for a resume-pumping command (signed). `response/control/ResumePumpingResponse` (op 0x9B, 1B).
public struct ResumePumpingResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x9B, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never default to status 0 (== accepted). Unreachable
        // via ResponseParser (length-guarded + HMAC-verified first), but a direct caller must not decode
        // an empty/truncated frame as an ACCEPTED resume.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = ResumePumpingResponse(cargo: raw) }
    /// status 0 = accepted.
    public var accepted: Bool { status == 0 }
}

/// Ack for a set-temp-rate command (signed). `response/control/SetTempRateResponse` (op 0xA5, 4B).
/// `tempRateId` cross-references the `TempRateActivatedHistoryLog` event.
public struct SetTempRateResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xA5, size: 4, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public private(set) var tempRateId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — the status decode itself must be guarded, not just
        // tempRateId's partial (length-3) read, or an empty/truncated buffer defaults status to 0 (== accepted).
        // Unreachable via ResponseParser (length-guarded + HMAC-verified first), but a direct caller must
        // not decode an empty/truncated frame as an ACCEPTED temp-rate change.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
        tempRateId = Bytes.readShort(raw, 1)
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetTempRateResponse(cargo: raw) }
    /// status 0 = accepted.
    public var accepted: Bool { status == 0 }
}

/// Ack for a stop-temp-rate command (signed). `response/control/StopTempRateResponse` (op 0xA7, 3B).
/// `tempRateId` cross-references the `TempRateCompletedHistoryLog` event.
public struct StopTempRateResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xA7, size: 3, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public private(set) var tempRateId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — a truncated/empty ack must never decode status 0
        // (== accepted) for a delivery-affecting stop-temp-rate. Unreachable via ResponseParser
        // (length-guarded + HMAC-verified), but a direct caller must not read an ACCEPTED stop from an
        // empty/truncated frame. Mirrors the already-hardened SetTempRateResponse.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
        tempRateId = Bytes.readShort(raw, 1)
    }
    public mutating func parse(_ raw: [UInt8]) { self = StopTempRateResponse(cargo: raw) }
    /// status 0 = accepted.
    public var accepted: Bool { status == 0 }
}

/// Acks for the cartridge-change / fill-tubing / fill-cannula workflow (signed CONTROL, status@0).
public struct EnterChangeCartridgeModeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x91, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = EnterChangeCartridgeModeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}
public struct ExitChangeCartridgeModeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x93, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = ExitChangeCartridgeModeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}
public struct EnterFillTubingModeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x95, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = EnterFillTubingModeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}
public struct ExitFillTubingModeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x97, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = ExitFillTubingModeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}
public struct FillCannulaResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x99, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = FillCannulaResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for prime-tubing-suspend (signed CONTROL). `PrimeTubingSuspendResponse` (op 0xEF, 3B).
/// statusCode@0, reserve@2.
public struct PrimeTubingSuspendResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xEF, size: 3, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var statusCode = 0
    public private(set) var reserve = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never decode statusCode 0 (== accepted) from a
        // truncated/empty prime-tubing-suspend ack.
        guard raw.count >= Self.props.size else { statusCode = 1; return }
        statusCode = Int(raw[0])
        reserve = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = PrimeTubingSuspendResponse(cargo: raw) }
    public var accepted: Bool { statusCode == 0 }
}

/// Ack for set-max-bolus-limit (signed CONTROL). `SetMaxBolusLimitResponse` (op 0x87, 1B).
public struct SetMaxBolusLimitResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x87, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetMaxBolusLimitResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-max-basal-limit (signed CONTROL). `SetMaxBasalLimitResponse` (op 0x89, 1B).
public struct SetMaxBasalLimitResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x89, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetMaxBasalLimitResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-low-insulin-alert (signed CONTROL). `SetLowInsulinAlertResponse` (op 0xDF, 1B).
public struct SetLowInsulinAlertResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xDF, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetLowInsulinAlertResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-auto-off-alert (signed CONTROL). `SetAutoOffAlertResponse` (op 0xE1, 1B).
public struct SetAutoOffAlertResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE1, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetAutoOffAlertResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-modes (signed CONTROL). `SetModesResponse` (op 0xCD, 1B).
public struct SetModesResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xCD, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetModesResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-active-IDP (signed CONTROL). `SetActiveIDPResponse` (op 0xED, 1B).
public struct SetActiveIDPResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xED, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetActiveIDPResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for play-sound / find-my-pump (signed CONTROL). `PlaySoundResponse` (op 0xF5, 1B).
public struct PlaySoundResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xF5, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = PlaySoundResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-pump-sounds (signed CONTROL). `SetPumpSoundsResponse` (op 0xE5, 1B).
public struct SetPumpSoundsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE5, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetPumpSoundsResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for change-time-date (signed CONTROL). `ChangeTimeDateResponse` (op 0xD7, 1B).
public struct ChangeTimeDateResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xD7, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = ChangeTimeDateResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for a remote carb entry (signed CONTROL). `RemoteCarbEntryResponse` (op 0xF3, 1B).
public struct RemoteCarbEntryResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xF3, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = RemoteCarbEntryResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for a remote BG entry (signed CONTROL). `RemoteBgEntryResponse` (op 0xB7, 1B).
public struct RemoteBgEntryResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xB7, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = RemoteBgEntryResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for start-G6-sensor-session (signed CONTROL). `StartDexcomG6SensorSessionResponse` (op 0xB3, 1B).
public struct StartDexcomG6SensorSessionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xB3, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = StartDexcomG6SensorSessionResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for stop-CGM-sensor-session (signed CONTROL). `StopDexcomCGMSensorSessionResponse` (op 0xB5, 1B).
public struct StopDexcomCGMSensorSessionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xB5, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = StopDexcomCGMSensorSessionResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-sensor-type (signed CONTROL). `SetSensorTypeResponse` (op 0xC1, 2B).
/// status@0, statusAcknowledgement@1.
public struct SetSensorTypeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xC1, size: 2, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public private(set) var statusAcknowledgement = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never decode status 0 (== accepted) from a
        // truncated/empty set-sensor-type ack.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
        statusAcknowledgement = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetSensorTypeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for set-G7-pairing-code (signed CONTROL). `SetDexcomG7PairingCodeResponse` (op 0xFD, 2B).
public struct SetDexcomG7PairingCodeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xFD, size: 2, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = SetDexcomG7PairingCodeResponse(cargo: raw) }
    public var accepted: Bool { status == 0 }
}

/// Ack for a cancel-bolus command (a.k.a. BolusTermination) — signed.
/// `response/control/CancelBolusResponse` (op 0xA1, 5B). statusId@0, bolusId short@1, reasonId@3.
public struct CancelBolusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xA1, size: 5, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var statusId = 0
    public private(set) var bolusId = 0
    public private(set) var reasonId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer. `wasCancelled == (statusId == 0 && reasonId == 0)`,
        // so a fully-empty cargo would otherwise decode "your bolus was cancelled" from ZERO pump bytes.
        // Set BOTH statusId and reasonId to a non-success sentinel so `wasCancelled` can never be true from
        // a truncated/empty frame (unreachable via ResponseParser, but a direct caller must fail closed).
        guard raw.count >= Self.props.size else { statusId = 1; reasonId = 1; return }
        statusId = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        reasonId = Int(raw[3])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CancelBolusResponse(cargo: raw) }
    /// statusId 0 = SUCCESS, reasonId 0 = NO_ERROR (2 = invalid/already delivered).
    public var wasCancelled: Bool { statusId == 0 && reasonId == 0 }
}

/// Ack for releasing a pending bolus permission (signed). Closes out the potential bolus in the
/// history logs. `response/control/BolusPermissionReleaseResponse` (op 0xF1, 1B). status@0.
public struct BolusPermissionReleaseResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xF1, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; guard raw.count >= Self.props.size else { status = 1; return }; status = Int(raw[0]) }
    public mutating func parse(_ raw: [UInt8]) { self = BolusPermissionReleaseResponse(cargo: raw) }
    /// status 0 = SUCCESS.
    public var released: Bool { status == 0 }
}

/// Pump-wide settings: low-insulin threshold, cannula prime size, auto-shutdown, feature lock,
/// OLED timeout. `response/currentStatus/PumpSettingsResponse` (op 83, 9B).
/// lowInsulinThreshold@0, cannulaPrimeSize@1, autoShutdownEnabled@2, autoShutdownDuration short@3,
/// featureLock@5, oledTimeout@6, status short@7.
public struct PumpSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 83, size: 9, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var lowInsulinThreshold = 0
    public private(set) var cannulaPrimeSize = 0
    public private(set) var autoShutdownEnabled = 0
    public private(set) var autoShutdownDuration = 0
    public private(set) var featureLock = 0
    public private(set) var oledTimeout = 0
    public private(set) var status = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 9 else { return }
        lowInsulinThreshold = Int(raw[0])
        cannulaPrimeSize = Int(raw[1])
        autoShutdownEnabled = Int(raw[2])
        autoShutdownDuration = Bytes.readShort(raw, 3)
        featureLock = Int(raw[5])
        oledTimeout = Int(raw[6])
        status = Bytes.readShort(raw, 7)
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpSettingsResponse(cargo: raw) }
}

/// Global pump settings: quick-bolus config + per-category annunciation (audio/vibrate) modes.
/// `response/currentStatus/PumpGlobalsResponse` (op 87, 14B). quickBolusEnabled@0,
/// quickBolusIncrementUnits short@1, quickBolusIncrementCarbs short@3, quickBolusEntryType@5,
/// quickBolusStatus@6, then buttonAnnun@7…fillTubingAnnun@13.
public struct PumpGlobalsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 87, size: 14, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var quickBolusEnabledRaw = 0
    public private(set) var quickBolusIncrementUnits = 0
    public private(set) var quickBolusIncrementCarbs = 0
    public private(set) var quickBolusEntryType = 0
    public private(set) var quickBolusStatus = 0
    public private(set) var buttonAnnun = 0
    public private(set) var quickBolusAnnun = 0
    public private(set) var bolusAnnun = 0
    public private(set) var reminderAnnun = 0
    public private(set) var alertAnnun = 0
    public private(set) var alarmAnnun = 0
    public private(set) var fillTubingAnnun = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 14 else { return }
        quickBolusEnabledRaw = Int(raw[0])
        quickBolusIncrementUnits = Bytes.readShort(raw, 1)
        quickBolusIncrementCarbs = Bytes.readShort(raw, 3)
        quickBolusEntryType = Int(raw[5])
        quickBolusStatus = Int(raw[6])
        buttonAnnun = Int(raw[7])
        quickBolusAnnun = Int(raw[8])
        bolusAnnun = Int(raw[9])
        reminderAnnun = Int(raw[10])
        alertAnnun = Int(raw[11])
        alarmAnnun = Int(raw[12])
        fillTubingAnnun = Int(raw[13])
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpGlobalsResponse(cargo: raw) }
    public var quickBolusEnabled: Bool { quickBolusEnabledRaw == 1 }
}

/// Extended (dual/square-wave) bolus status. `response/currentStatus/ExtendedBolusStatusV2Response`
/// (op 183, 22B). bolusStatus@0, bolusId short@1, timestamp uint32@5, requestedVolume uint32@9
/// (mU), duration uint32@13, bolusSource@17, secondsSincePumpReset uint32@18.
public struct ExtendedBolusStatusV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 183, size: 22, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bolusStatus = 0
    public private(set) var bolusId = 0
    public private(set) var timestamp = 0
    public private(set) var requestedVolume = 0
    public private(set) var duration = 0
    public private(set) var bolusSource = 0
    public private(set) var secondsSincePumpReset = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 22 else { return }
        bolusStatus = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        timestamp = Int(Bytes.readUint32(raw, 5))
        requestedVolume = Int(Bytes.readUint32(raw, 9))
        duration = Int(Bytes.readUint32(raw, 13))
        bolusSource = Int(raw[17])
        secondsSincePumpReset = Int(Bytes.readUint32(raw, 18))
    }
    public mutating func parse(_ raw: [UInt8]) { self = ExtendedBolusStatusV2Response(cargo: raw) }
    public var requestedUnits: Double { Double(requestedVolume) / 1000.0 }
}

/// CGM session status. `response/currentStatus/CGMStatusResponse` (op 81, 10B). sessionStateId@0,
/// lastCalibrationTimestamp uint32@1, sensorStartedTimestamp uint32@5, transmitterBatteryStatusId@9.
public struct CGMStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 81, size: 10, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var sessionStateId = 0
    public private(set) var lastCalibrationTimestamp = 0
    public private(set) var sensorStartedTimestamp = 0
    public private(set) var transmitterBatteryStatusId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 10 else { return }
        sessionStateId = Int(raw[0])
        lastCalibrationTimestamp = Int(Bytes.readUint32(raw, 1))
        sensorStartedTimestamp = Int(Bytes.readUint32(raw, 5))
        transmitterBatteryStatusId = Int(raw[9])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CGMStatusResponse(cargo: raw) }
    /// sessionStateId 1 = active (per upstream SessionState).
    public var sessionActive: Bool { sessionStateId == 1 }
}

/// CGM session status, v2 (adds session duration/remaining, sensor type, grace period).
/// `response/currentStatus/CgmStatusV2Response` (op 191, 20B). sessionStateId@0,
/// lastCalibrationTimestamp uint32@1, sensorStartedTimestamp uint32@5, transmitterBatteryStatusId@9,
/// sessionDurationSeconds uint32@10, sessionTimeRemainingSeconds uint32@14, cgmSensorTypeId@18,
/// gracePeriod@19.
public struct CgmStatusV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 191, size: 20, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var sessionStateId = 0
    public private(set) var lastCalibrationTimestamp = 0
    public private(set) var sensorStartedTimestamp = 0
    public private(set) var transmitterBatteryStatusId = 0
    public private(set) var sessionDurationSeconds = 0
    public private(set) var sessionTimeRemainingSeconds = 0
    public private(set) var cgmSensorTypeId = 0
    public private(set) var gracePeriod = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 20 else { return }
        sessionStateId = Int(raw[0])
        lastCalibrationTimestamp = Int(Bytes.readUint32(raw, 1))
        sensorStartedTimestamp = Int(Bytes.readUint32(raw, 5))
        transmitterBatteryStatusId = Int(raw[9])
        sessionDurationSeconds = Int(Bytes.readUint32(raw, 10))
        sessionTimeRemainingSeconds = Int(Bytes.readUint32(raw, 14))
        cgmSensorTypeId = Int(raw[18])
        gracePeriod = (raw[19] & 0xFF) != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = CgmStatusV2Response(cargo: raw) }
    public var sessionActive: Bool { sessionStateId == 1 }
}

/// CGM transmitter/sensor hardware identifier string. `response/currentStatus/CGMHardwareInfoResponse`
/// (op 97, 17B). hardwareInfoString = 16-byte string@0, lastByte@16.
public struct CGMHardwareInfoResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 97, size: 17, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var hardwareInfoString = ""
    public private(set) var lastByte = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 17 else { return }
        hardwareInfoString = Bytes.readString(raw, 0, 16)
        lastByte = Int(raw[16])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CGMHardwareInfoResponse(cargo: raw) }
}

/// Settings for one insulin-delivery profile. `response/currentStatus/IDPSettingsResponse`
/// (op 65, 23B). idpId@0, name=16-byte string@1, numberOfProfileSegments@17,
/// insulinDuration short@18 (min), maxBolus short@20 (mU), carbEntry@22.
public struct IDPSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 65, size: 23, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var idpId = 0
    public private(set) var name = ""
    public private(set) var numberOfProfileSegments = 0
    public private(set) var insulinDuration = 0             // minutes
    public private(set) var maxBolus = 0                    // milliunits
    public private(set) var carbEntry = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 23 else { return }
        idpId = Int(raw[0])
        name = Bytes.readString(raw, 1, 16)
        numberOfProfileSegments = Int(raw[17])
        insulinDuration = Bytes.readShort(raw, 18)
        maxBolus = Bytes.readShort(raw, 20)
        carbEntry = raw[22] != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = IDPSettingsResponse(cargo: raw) }
    public var maxBolusUnits: Double { Double(maxBolus) / 1000.0 }
}

/// One time-segment of an insulin-delivery profile. `response/currentStatus/IDPSegmentResponse`
/// (op 67, 15B). idpId@0, segmentIndex@1, profileStartTime short@2 (min-of-day),
/// profileBasalRate short@4 (mU/hr), profileCarbRatio uint32@6 (1000-inc), profileTargetBG
/// short@10 (mg/dL), profileISF short@12 (mg/dL/U), idpStatusId@14.
public struct IDPSegmentResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 67, size: 15, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var idpId = 0
    public private(set) var segmentIndex = 0
    public private(set) var profileStartTime = 0            // minutes past midnight
    public private(set) var profileBasalRate = 0            // milliunits/hr
    public private(set) var profileCarbRatio = 0            // 1000-increments
    public private(set) var profileTargetBG = 0             // mg/dL
    public private(set) var profileISF = 0                  // mg/dL per unit
    public private(set) var idpStatusId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 15 else { return }
        idpId = Int(raw[0])
        segmentIndex = Int(raw[1])
        profileStartTime = Bytes.readShort(raw, 2)
        profileBasalRate = Bytes.readShort(raw, 4)
        profileCarbRatio = Int(Bytes.readUint32(raw, 6))
        profileTargetBG = Bytes.readShort(raw, 10)
        profileISF = Bytes.readShort(raw, 12)
        idpStatusId = Int(raw[14])
    }
    public mutating func parse(_ raw: [UInt8]) { self = IDPSegmentResponse(cargo: raw) }
    public var basalRateUnitsPerHour: Double { Double(profileBasalRate) / 1000.0 }
    public var carbRatioGramsPerUnit: Double { Double(profileCarbRatio) / 1000.0 }
}

/// Control-IQ info, v1 firmware. `response/currentStatus/ControlIQInfoV1Response` (op 105, 10B).
/// closedLoop@0, weight short@1, weightUnit@3, totalDailyInsulin@4, currentUserModeType@5,
/// controlStateType@9. (V2 at op 179 carries exercise fields; this is the older layout.)
public struct ControlIQInfoV1Response: ResponseMessage {
    public static let props = MessageProps(opCode: 105, size: 10, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var closedLoopEnabled = false
    public private(set) var weight = 0
    public private(set) var weightUnit = 0
    public private(set) var totalDailyInsulin = 0
    public private(set) var currentUserModeType = 0
    public private(set) var controlStateType = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 10 else { return }
        closedLoopEnabled = raw[0] != 0
        weight = Bytes.readShort(raw, 1)
        weightUnit = Int(raw[3])
        totalDailyInsulin = Int(raw[4])
        currentUserModeType = Int(raw[5])
        controlStateType = Int(raw[9])
    }
    public mutating func parse(_ raw: [UInt8]) { self = ControlIQInfoV1Response(cargo: raw) }
}

/// Pump feature bitmask (which capabilities the pump firmware supports).
/// `response/currentStatus/PumpFeaturesV1Response` (op 79, 8B). uint64 bitmask@0.
public struct PumpFeaturesV1Response: ResponseMessage {
    public static let props = MessageProps(opCode: 79, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var featureBitmask: UInt64 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 8 { featureBitmask = Bytes.readUint64(raw, 0) }
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpFeaturesV1Response(cargo: raw) }
    private func has(_ bit: UInt64) -> Bool { featureBitmask & bit != 0 }
    public var dexcomG5Supported: Bool { has(1) }
    public var dexcomG6Supported: Bool { has(2) }
    public var basalIQSupported: Bool { has(4) }
    public var controlIQSupported: Bool { has(1024) }
    public var basalLimitSupported: Bool { has(262144) }
    public var controlIQProSupported: Bool { has(8388608) }
    public var blePumpControlSupported: Bool { has(268435456) }
    public var pumpSettingsInIdpGuiSupported: Bool { has(536870912) }
}

/// Cartridge-load / prime-tubing status. `response/currentStatus/LoadStatusResponse` (op 21, 3B).
/// isLoadingActive@0, loadStateId@1, primeStatusId@2.
public struct LoadStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 21, size: 3, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var isLoadingActiveId = 0
    public private(set) var loadStateId = 0
    public private(set) var primeStatusId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 3 else { return }
        isLoadingActiveId = Int(raw[0])
        loadStateId = Int(raw[1])
        primeStatusId = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = LoadStatusResponse(cargo: raw) }
    public var isLoadingActive: Bool { isLoadingActiveId != 0 }
}

/// Insulin-delivery-profile (IDP) slot overview. `response/currentStatus/ProfileStatusResponse`
/// (op 63, 8B). Slot 0 is always the active profile; a slot value of -1 (0xFF) means empty.
/// numberOfProfiles@0, then slot0..slot5 @1..6, activeSegmentIndex@7. Query slot details with
/// an IDPSettingsRequest for that id.
public struct ProfileStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 63, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var numberOfProfiles = 0
    public private(set) var idpSlotIds: [Int] = []        // all six raw slot ids (may be -1)
    public private(set) var activeSegmentIndex = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 8 else { return }
        numberOfProfiles = Int(Int8(bitPattern: raw[0]))
        idpSlotIds = (1...6).map { Int(Int8(bitPattern: raw[$0])) }   // -1 sentinel for empty slots
        activeSegmentIndex = Int(Int8(bitPattern: raw[7]))
    }
    public mutating func parse(_ raw: [UInt8]) { self = ProfileStatusResponse(cargo: raw) }
    /// The active profile id (always slot 0), or -1 if no profiles exist.
    public var activeIdpId: Int { idpSlotIds.first ?? -1 }
    /// Present slot ids restricted to numberOfProfiles.
    public var presentIdpIds: [Int] { Array(idpSlotIds.prefix(max(0, numberOfProfiles))) }
}

/// Currently-active IDP parameter values for the active time segment.
/// `response/currentStatus/CurrentActiveIdpValuesResponse` (op 0x97, 10B). Capture-backed layout:
/// carbRatio uint32@0 (1000-increments), targetBg uint16@4 (mg/dL), insulinDuration uint16@6 (min),
/// ISF uint16@8. Byte 5 is the targetBg high byte (0 for real-world targets < 256).
///
/// Ground truth is the real hardware capture `7017000073002c012800` (present in upstream's own
/// test suite, cited in `gh pr diff 102 --repo jwoglom/pumpx2`): bytes `73 00` at offset 4 decode
/// to targetBg == 115 (a sane IDP target). Independently re-derived by Codex (OWNER-DECISIONS.md
/// 2026-08-16, HIGH confidence for the observed 10-byte layout). The earlier byte@5 read decoded
/// this capture as 0 (garbage); the old overlapping upstream `readShort(raw,5)` decoded it as 11264.
/// `Bytes.readShort(raw, 4)` (not `Int(raw[4])`) is used so a future targetBg > 255 is not truncated.
///
/// NO CLEAN ORACLE BACKING (owner-acknowledged, deliberate): the pinned cliparser oracle is itself
/// DEFECTIVE for this field — its `buildCargo` writes targetBg at byte 5 with byte 4 = padding and
/// its parse reads `readShort(raw,5)` (asserting 11264) — so no OracleRunner vector can validate the
/// byte-4 offset by construction. The capture-based `ResponseDirectTests.currentActiveIdpValuesCaptureTargetBgAtByte4`
/// is the substitute ground truth; the oracle-derived parity vectors defer targetBg to that test.
///
/// Unverified against a pump capture: the byte-4 offset is confirmed only on the primary pinned
/// pump (`t:slim X2 · Control-IQ+ 7.10.2`). An unverified decompiled-Mobi rationale reads targetBg
/// at byte 5, and the wire layout may differ by t:slim SOFTWARE VERSION as well as by pump family
/// (t:slim vs Mobi). Byte-4 trust is GATED — not asserted — until confirmed live per (pump family,
/// firmware version) at the Phase-11 saline bench (see TandemKit/docs/BENCH-SESSION-PLAN.md and
/// faBolus docs/UNVERIFIED-GUESSES.md); if a genuine byte-5 variant is captured, decoding must
/// become variant-aware keyed on (pump family, firmware version). Experimental-only; not cleared for
/// real insulin until the bench confirms it.
public struct CurrentActiveIdpValuesResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x97, size: 10, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var currentCarbRatio = 0            // 1000-increments (10000 = 10 g/U)
    public private(set) var currentTargetBg = 0             // mg/dL (uint16 LE @4; capture-backed, bench-gated)
    public private(set) var currentInsulinDuration = 0      // minutes
    public private(set) var currentIsf = 0                  // mg/dL per unit
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 10 else { return }
        currentCarbRatio = Int(Bytes.readUint32(raw, 0))
        currentTargetBg = Bytes.readShort(raw, 4)
        currentInsulinDuration = Bytes.readShort(raw, 6)
        currentIsf = Bytes.readShort(raw, 8)
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentActiveIdpValuesResponse(cargo: raw) }
    /// Carb ratio in grams per unit.
    public var carbRatioGramsPerUnit: Double { Double(currentCarbRatio) / 1000.0 }
}

/// Global max-bolus limit + factory default (milliunits). `GlobalMaxBolusSettingsResponse`
/// (op 0x8D, 4B). maxBolus short@0, maxBolusDefault short@2.
public struct GlobalMaxBolusSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x8D, size: 4, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var maxBolus = 0                    // milliunits
    public private(set) var maxBolusDefault = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 4 else { return }
        maxBolus = Bytes.readShort(raw, 0)
        maxBolusDefault = Bytes.readShort(raw, 2)
    }
    public mutating func parse(_ raw: [UInt8]) { self = GlobalMaxBolusSettingsResponse(cargo: raw) }
    public var maxBolusUnits: Double { Double(maxBolus) / 1000.0 }
}

/// Max basal-rate limit + factory default (milliunits/hr). `BasalLimitSettingsResponse`
/// (op 0x8B, 8B). basalLimit uint32@0, basalLimitDefault uint32@4.
public struct BasalLimitSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0x8B, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var basalLimit = 0                  // milliunits/hr
    public private(set) var basalLimitDefault = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 8 else { return }
        basalLimit = Int(Bytes.readUint32(raw, 0))
        basalLimitDefault = Int(Bytes.readUint32(raw, 4))
    }
    public mutating func parse(_ raw: [UInt8]) { self = BasalLimitSettingsResponse(cargo: raw) }
    public var basalLimitUnitsPerHour: Double { Double(basalLimit) / 1000.0 }
}

/// Pump firmware/hardware version + identifiers. `response/currentStatus/PumpVersionResponse`
/// (op 85, 48B).
public struct PumpVersionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 85, size: 48, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var armSwVer: UInt32 = 0
    public private(set) var mspSwVer: UInt32 = 0
    public private(set) var serialNum: UInt32 = 0
    public private(set) var partNum: UInt32 = 0
    public private(set) var pumpRev = ""
    public private(set) var modelNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 48 {
            armSwVer = Bytes.readUint32(raw, 0)
            mspSwVer = Bytes.readUint32(raw, 4)
            serialNum = Bytes.readUint32(raw, 16)
            partNum = Bytes.readUint32(raw, 20)
            pumpRev = Bytes.readString(raw, 24, 8)
            modelNum = Bytes.readUint32(raw, 44)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpVersionResponse(cargo: raw) }
}

/// What the pump home screen is showing (icon ids + CGM display flags).
/// `response/currentStatus/HomeScreenMirrorResponse` (op 57, 9B).
public struct HomeScreenMirrorResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 57, size: 9, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var cgmTrendIconId = 0
    public private(set) var cgmAlertIconId = 0
    public private(set) var bolusStatusIconId = 0
    public private(set) var basalStatusIconId = 0
    public private(set) var apControlStateIconId = 0
    public private(set) var remainingInsulinPlusIcon = false
    public private(set) var cgmDisplayData = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 9 {
            cgmTrendIconId = Int(raw[0])
            cgmAlertIconId = Int(raw[1])
            bolusStatusIconId = Int(raw[4])
            basalStatusIconId = Int(raw[5])
            apControlStateIconId = Int(raw[6])
            remainingInsulinPlusIcon = raw[7] != 0
            cgmDisplayData = raw[8] != 0
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = HomeScreenMirrorResponse(cargo: raw) }

    /// The **pump's own** CGM trend icon. This is the authoritative trend: it is the glyph the pump is
    /// displaying on its home screen, so rendering it cannot disagree with the pump.
    ///
    /// Prefer this over deriving an arrow from `CurrentEgvGuiDataV2Response.trendRate`: a client-side
    /// derivation has to guess Tandem's bucket boundaries, and — critically — has no way to express
    /// `noArrow`, which the pump uses whenever it has no trend to show. Ids match upstream
    /// `HomeScreenMirrorResponse.CGMTrendIcon`.
    public enum CGMTrendIcon: Int, Sendable {
        case noArrow = 0, doubleUp = 1, up = 2, upRight = 3, flat = 4, downRight = 5, down = 6, doubleDown = 7
    }
    public var cgmTrendIcon: CGMTrendIcon? { CGMTrendIcon(rawValue: cgmTrendIconId) }

    /// The pump's trend as a Unicode arrow, or `""` when the pump is showing **no arrow** — including
    /// for an unrecognized icon id, because inventing a direction is worse than showing none.
    public var cgmTrendArrow: String {
        switch cgmTrendIcon {
        case .doubleUp:   return "⇈"
        case .up:         return "↑"
        case .upRight:    return "↗"
        case .flat:       return "→"
        case .downRight:  return "↘"
        case .down:       return "↓"
        case .doubleDown: return "⇊"
        case .noArrow, .none: return ""
        }
    }
}

/// Temp-basal-rate status. `response/currentStatus/TempRateStatusResponse` (op 31, 16B).
public struct TempRateStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 31, size: 16, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var active = false
    public private(set) var tempRateId = 0
    public private(set) var startTimeRaw: UInt32 = 0
    public private(set) var secondsSincePumpReset: UInt32 = 0
    public private(set) var durationSeconds: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 16 {
            active = raw[0] != 0
            tempRateId = Bytes.readShort(raw, 1)
            startTimeRaw = Bytes.readUint32(raw, 4)
            secondsSincePumpReset = Bytes.readUint32(raw, 8)
            durationSeconds = Bytes.readUint32(raw, 12)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = TempRateStatusResponse(cargo: raw) }
}

/// Battery read for older (non-V2) pumps. `response/currentStatus/CurrentBatteryV1Response` (op 53, 2B).
public struct CurrentBatteryV1Response: ResponseMessage {
    public static let props = MessageProps(opCode: 53, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var currentBatteryAbc = 0
    public private(set) var currentBatteryIbc = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 2 { currentBatteryAbc = Int(raw[0]); currentBatteryIbc = Int(raw[1]) }
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentBatteryV1Response(cargo: raw) }
    public var batteryPercent: Int { currentBatteryIbc }
}

/// IOB read (Control-IQ). `response/currentStatus/ControlIQIOBResponse` (opcode 109, 17 bytes).
public struct ControlIQIOBResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 109, size: 17, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var mudaliarIOB: UInt32 = 0        // milliunits
    public private(set) var timeRemainingSeconds: UInt32 = 0
    public private(set) var mudaliarTotalIOB: UInt32 = 0
    public private(set) var swan6hrIOB: UInt32 = 0
    public private(set) var iobType: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        mudaliarIOB = Bytes.readUint32(raw, 0)
        timeRemainingSeconds = Bytes.readUint32(raw, 4)
        mudaliarTotalIOB = Bytes.readUint32(raw, 8)
        swan6hrIOB = Bytes.readUint32(raw, 12)
        iobType = Int(raw[16])
    }
    public mutating func parse(_ raw: [UInt8]) { self = ControlIQIOBResponse(cargo: raw) }
    /// IOB in insulin units. Uses `swan6hrIOB` — verified on hardware (t:slim X2, Control-IQ+
    /// 7.10.2) to match the value the pump displays, unlike `mudaliarIOB`.
    public var iobUnits: Double { Double(swan6hrIOB) / 1000.0 }
}

/// In-progress bolus status. `response/currentStatus/CurrentBolusStatusResponse` (opcode 45,
/// 15 bytes). `statusId`: 0 = already delivered / invalid (none active), 1 = delivering,
/// 2 = requesting. Used to detect when a bolus finishes so the UI can keep a live cancel window.
public struct CurrentBolusStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 45, size: 15, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var statusId: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var requestedVolume: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 15 {
            statusId = Int(raw[0])
            bolusId = Bytes.readShort(raw, 1)
            requestedVolume = Bytes.readUint32(raw, 9)
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentBolusStatusResponse(cargo: raw) }
    /// True while the pump is still requesting or delivering this bolus.
    public var isActive: Bool { statusId == 1 || statusId == 2 }
}

/// Insulin remaining. `response/currentStatus/InsulinStatusResponse` (opcode 37, 4 bytes).
public struct InsulinStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 37, size: 4, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var currentInsulinAmount: Int = 0   // units remaining
    public private(set) var isEstimate: Int = 0
    public private(set) var insulinLowAmount: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        currentInsulinAmount = Bytes.readShort(raw, 0)
        isEstimate = Int(raw[2])
        insulinLowAmount = Int(raw[3])
    }
    public mutating func parse(_ raw: [UInt8]) { self = InsulinStatusResponse(cargo: raw) }
}

/// Battery. `response/currentStatus/CurrentBatteryV2Response` (opcode 145, 11 bytes).
public struct CurrentBatteryV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 145, size: 11, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var currentBatteryAbc: Int = 0
    public private(set) var currentBatteryIbc: Int = 0      // battery percent
    public private(set) var chargingStatus: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        currentBatteryAbc = Int(raw[0])
        currentBatteryIbc = Int(raw[1])
        chargingStatus = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentBatteryV2Response(cargo: raw) }
    public var batteryPercent: Int { currentBatteryIbc }
}

/// Current CGM reading + trend (GUI data, V2). `response/currentStatus/CurrentEgvGuiDataV2Response`
/// (opcode 193, 8 bytes). `cgmReading` is mg/dL; `trendRate` is a signed rate (sign → arrow).
public struct CurrentEgvGuiDataV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 193, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bgReadingTimestampSeconds: UInt32 = 0
    public private(set) var cgmReading: Int = 0        // mg/dL
    public private(set) var egvStatusId: Int = 0
    public private(set) var trendRate: Int = 0         // signed (Int8)
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        bgReadingTimestampSeconds = Bytes.readUint32(raw, 0)
        cgmReading = Bytes.readShort(raw, 4)
        egvStatusId = Int(raw[6])
        trendRate = Int(Int8(bitPattern: raw[7]))
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentEgvGuiDataV2Response(cargo: raw) }
    /// `trendRate` is a signed byte in 0.1 mg/dL/min units (matches the pump's ±12.7 range).
    public var trendRateMgDlPerMin: Double { Double(trendRate) / 10.0 }
    /// `true` when `trendRate` is a **sentinel** rather than a real rate.
    ///
    /// Dexcom-family encodings reserve the extreme signed-byte values for "rate unavailable"; this
    /// project's own G6 decoder guards for exactly that (`DexcomG6Kit.GlucoseRxMessage`:
    /// `guard glucose.trend > Int8.min, glucose.trend < Int8.max`). Without this guard `0x7f` decodes
    /// as +12.7 mg/dL/min and reads as a rapid rise — the mechanism behind the reported "app shows
    /// double-up when the pump shows no arrow" defect.
    ///
    /// Unverified against a pump capture: the sentinel value is inferred from the sibling Dexcom
    /// decoder and from the upstream reference, not confirmed on hardware.
    public var trendRateIsUnavailable: Bool {
        trendRate >= Int(Int8.max) || trendRate <= Int(Int8.min)
    }

    /// The trend rate, or `nil` when the pump has no usable rate — either the EGV frame itself is not
    /// valid (`hasValidReading` is false for status INVALID/UNAVAILABLE) or the rate is a sentinel.
    public var trendRateIfKnown: Double? {
        guard hasValidReading, !trendRateIsUnavailable else { return nil }
        return trendRateMgDlPerMin
    }

    /// A trend arrow derived client-side from `trendRate`, or `nil` when the rate is unknown.
    ///
    /// **Prefer `HomeScreenMirrorResponse.cgmTrendArrow`** — the pump's own home-screen icon, which by
    /// construction agrees with the pump display and can say "no arrow". This derivation has to guess
    /// Tandem's bucket boundaries, so it can disagree with the pump. Retained only so a caller that has
    /// not yet polled `HomeScreenMirrorRequest` has something to fall back on, and it returns `nil`
    /// rather than a fabricated direction whenever the rate is not known.
    public var trendArrow: String? { EgvTrend.arrow(forRate: trendRateIfKnown) }
    /// EGV status per upstream: 0=INVALID, 1=VALID, 2=LOW, 3=HIGH, 4=UNAVAILABLE.
    public var hasValidReading: Bool {
        (egvStatusId == 1 || egvStatusId == 2 || egvStatusId == 3) && cgmReading > 0 && cgmReading < 600
    }
}

/// Shared trend-arrow derivation for the V1/V2 EGV responses, which carry identical `trendRate`
/// semantics. Extracted so the two cannot drift — the bucket boundaries are a guess at Tandem's own,
/// and having one copy per response struct is exactly how the previously-fixed asymmetric-band defect
/// (see `CurrentEgvGuiDataV2Response.trendArrow`) got introduced.
public enum EgvTrend {
    /// A trend arrow derived client-side from a known trend rate (0.1 mg/dL/min units, already
    /// validated), or `nil` when the rate is not known — never a fabricated direction.
    public static func arrow(forRate rate: Double?) -> String? {
        guard let r = rate else { return nil }
        // Symmetric bands, and no catch-all: a `default` here previously swallowed everything on the
        // rising side, so any unclassifiable value became a double-up.
        // |r| >= 3 is "rapid" in BOTH directions. It previously was not: -3.0 matched the single-arrow
        // band while +3.0 fell through to the catch-all double-up.
        switch r {
        case ...(-3):      return "⇊"   // falling rapidly
        case (-3)..<(-2):  return "↓"   // falling
        case (-2)..<(-1):  return "↘"   // falling slightly
        case (-1)...1:     return "→"   // steady
        case 1..<2:        return "↗"   // rising slightly
        case 2..<3:        return "↑"   // rising
        case 3...:         return "⇈"   // rising rapidly
        default:           return nil   // unreachable for a finite rate; never guess
        }
    }
}

/// Pump clock. `response/currentStatus/TimeSinceResetResponse` (opcode 55, 8 bytes).
/// `currentTime` is what the Android reference embeds into signed-message HMACs, so it's the
/// value to use as `pumpTimeSinceReset` when signing (verified against upstream TandemBluetoothHandler).
public struct TimeSinceResetResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 55, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var currentTime: UInt32 = 0
    public private(set) var pumpTimeSinceReset: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        currentTime = Bytes.readUint32(raw, 0)
        pumpTimeSinceReset = Bytes.readUint32(raw, 4)
    }
    public mutating func parse(_ raw: [UInt8]) { self = TimeSinceResetResponse(cargo: raw) }
    /// The timestamp to embed when signing (matches the Android app, which uses currentTime).
    public var signingTimestamp: UInt32 { currentTime }
}

/// Basal rate. `response/currentStatus/CurrentBasalStatusResponse` (opcode 41, 9 bytes).
/// Rates are in milliunits/hour.
public struct CurrentBasalStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 41, size: 9, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var profileBasalRate: UInt32 = 0
    public private(set) var currentBasalRate: UInt32 = 0
    public private(set) var basalModifiedBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        profileBasalRate = Bytes.readUint32(raw, 0)
        currentBasalRate = Bytes.readUint32(raw, 4)
        basalModifiedBitmask = Int(raw[8])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentBasalStatusResponse(cargo: raw) }
    public var currentBasalUnitsPerHour: Double { Double(currentBasalRate) / 1000.0 }
}

/// Last completed bolus. `response/currentStatus/LastBolusStatusV2Response` (opcode 165, 24 bytes).
public struct LastBolusStatusV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 165, size: 24, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var timestamp: UInt32 = 0
    public private(set) var deliveredVolume: UInt32 = 0     // milliunits
    public private(set) var requestedVolume: UInt32 = 0     // milliunits
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        status = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        timestamp = Bytes.readUint32(raw, 5)
        deliveredVolume = Bytes.readUint32(raw, 9)
        requestedVolume = Bytes.readUint32(raw, 20)
    }
    public mutating func parse(_ raw: [UInt8]) { self = LastBolusStatusV2Response(cargo: raw) }
    public var deliveredUnits: Double { Double(deliveredVolume) / 1000.0 }
}

/// Bolus-calculator snapshot — the therapy settings needed to turn carbs/BG into units, the
/// way controlX2 does. `response/currentStatus/BolusCalcDataSnapshotResponse` (opcode 115).
/// `carbRatio` (uint32) and `isf`/`correctionFactor` (mg/dL per unit) + `targetBg` drive the
/// carb-entry bolus feature.
///
/// `maxBolusHourlyTotal`@20 / `maxBolusEventsExceeded`@24 / `maxIobEventsExceeded`@25 are
/// ADDITIVE (WIP-REGISTER.md Adoption Candidate #4, dose-path-adjacent, HIGH priority) — oracle
/// offsets confirmed against the vendored `vendor/pumpx2-oracle` Java source
/// (`BolusCalcDataSnapshotResponse.java:72-74`: `maxBolusHourlyTotal = Bytes.readUint32(raw, 20)`,
/// `maxBolusEventsExceeded = raw[24] != 0`, `maxIobEventsExceeded = raw[25] != 0`). Only the
/// LAYOUT and the KNOWN-FALSE case are oracle-backed here (`ResponseDirectTests`); the `true`
/// case for the two safety-relevant flags has never been observed in a first-party capture, so
/// it is NOT asserted anywhere and NOT marked verified — not a code gap. Two further upstream fields
/// (`isUnacked`@0, `isAutopopAllowed`@37) remain intentionally undecoded — out of this
/// additive-only change's scope; the full 46-byte `cargo` is retained regardless.
public struct BolusCalcDataSnapshotResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 115, size: 46, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var correctionFactor: Int = 0
    public private(set) var iob: UInt32 = 0
    public private(set) var cartridgeRemainingInsulin: Int = 0
    public private(set) var targetBg: Int = 0                // mg/dL
    public private(set) var isf: Int = 0                     // correction factor, mg/dL per unit
    public private(set) var carbEntryEnabled: Bool = false
    public private(set) var carbRatio: UInt32 = 0            // see carbRatioGramsPerUnit
    public private(set) var maxBolusAmount: Int = 0          // milliunits
    /// The configured hourly bolus ceiling, or 0 if unconfigured. Oracle @20 (uint32).
    public private(set) var maxBolusHourlyTotal: UInt32 = 0
    /// true if the maximum bolus has been exceeded for the interval. Oracle @24. LAYOUT +
    /// KNOWN-FALSE case oracle-backed only — the `true` case has never been observed
    /// NOT marked verified.
    public private(set) var maxBolusEventsExceeded: Bool = false
    /// true if the maximum iob has been reached for the interval. Oracle @25. LAYOUT +
    /// KNOWN-FALSE case oracle-backed only — the `true` case has never been observed
    /// NOT marked verified.
    public private(set) var maxIobEventsExceeded: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Length-guard a fixed-size pure READ — zero-defaults are safe (no accept/grant field).
        // Defense-in-depth for a direct/refactor caller; unreachable via ResponseParser (it length-gates).
        guard raw.count >= Self.props.size else { return }
        correctionFactor = Bytes.readShort(raw, 1)
        iob = Bytes.readUint32(raw, 3)
        cartridgeRemainingInsulin = Bytes.readShort(raw, 7)
        targetBg = Bytes.readShort(raw, 9)
        isf = Bytes.readShort(raw, 11)
        carbEntryEnabled = raw[13] != 0
        carbRatio = Bytes.readUint32(raw, 14)
        maxBolusAmount = Bytes.readShort(raw, 18)
        maxBolusHourlyTotal = Bytes.readUint32(raw, 20)
        maxBolusEventsExceeded = raw[24] != 0
        maxIobEventsExceeded = raw[25] != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = BolusCalcDataSnapshotResponse(cargo: raw) }
    /// Tandem stores carbRatio scaled ×1000 (e.g. 10 g/u → 10000). VERIFY against the pump
    /// screen before relying on it for dosing.
    public var carbRatioGramsPerUnit: Double { Double(carbRatio) / 1000.0 }
}

/// Bolus permission grant. `response/control/BolusPermissionResponse` (opcode 163, 6 bytes).
/// `status == 0` = granted; `bolusId` is used for InitiateBolus/Cancel.
public struct BolusPermissionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 163, size: 6, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var nackReasonId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never default to status 0 (== granted). Unreachable via
        // ResponseParser (length-guarded + HMAC-verified first), but a direct caller must neither
        // trap (precondition on raw[0]) nor decode a truncated frame as a GRANTED bolus permission.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        nackReasonId = Int(raw[5])
    }
    public mutating func parse(_ raw: [UInt8]) { self = BolusPermissionResponse(cargo: raw) }
    // status==0 alone is not sufficient — a nonzero nackReasonId is a denial the pump
    // is signaling via a secondary field. Gate on both so a status-0-but-denied response is not
    // mistaken for a grant.
    public var granted: Bool { status == 0 && nackReasonId == 0 }
}

/// Initiate-bolus ack. `response/control/InitiateBolusResponse` (opcode 159, 6 bytes).
public struct InitiateBolusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 159, size: 6, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var statusTypeId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // fail CLOSED on a short buffer — never default to status 0 (== accepted). Unreachable via
        // ResponseParser (length-guarded + HMAC-verified first), but a direct caller must neither
        // trap (precondition on raw[0]) nor decode a truncated frame as an ACCEPTED bolus.
        guard raw.count >= Self.props.size else { status = 1; return }
        status = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        statusTypeId = Int(raw[5])
    }
    public mutating func parse(_ raw: [UInt8]) { self = InitiateBolusResponse(cargo: raw) }
    // status==0 alone is not sufficient — a nonzero statusTypeId is a denial the pump
    // is signaling via a secondary field. Gate on both so a status-0-but-denied response is not
    // mistaken for an accept.
    public var accepted: Bool { status == 0 && statusTypeId == 0 }
}

// MARK: - A2 control-command acks (generated, oracle/direct-verified)

/// Control response. Ported from ActivateShelfModeResponse.java (opcode raw -69).
public struct ActivateShelfModeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 187, size: 0, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 0 else { return }
    }
    public mutating func parse(_ raw: [UInt8]) { self = ActivateShelfModeResponse(cargo: raw) }
}

/// Control response. Ported from AdditionalBolusResponse.java (opcode raw -5).
public struct AdditionalBolusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 251, size: 5, signed: true, type: .response, characteristic: .control, modifiesInsulinDelivery: true)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var reserve: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 5 else { return }
        status = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        reserve = Bytes.readShort(raw, 3)
    }
    public mutating func parse(_ raw: [UInt8]) { self = AdditionalBolusResponse(cargo: raw) }
}

/// Control response. Ported from CgmHighLowAlertResponse.java (opcode raw -61).
public struct CgmHighLowAlertResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 195, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CgmHighLowAlertResponse(cargo: raw) }
}

/// Control response. Ported from CgmOutOfRangeAlertResponse.java (opcode raw -57).
public struct CgmOutOfRangeAlertResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 199, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CgmOutOfRangeAlertResponse(cargo: raw) }
}

/// Control response. Ported from CgmRiseFallAlertResponse.java (opcode raw -59).
public struct CgmRiseFallAlertResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 197, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CgmRiseFallAlertResponse(cargo: raw) }
}

/// Control response. Ported from ChangeControlIQSettingsResponse.java (opcode raw -53).
public struct ChangeControlIQSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 203, size: 3, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 3 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = ChangeControlIQSettingsResponse(cargo: raw) }
}

/// Control response. Ported from CreateIDPResponse.java (opcode raw -25).
public struct CreateIDPResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 231, size: 2, signed: true, type: .response, characteristic: .control, modifiesInsulinDelivery: true)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var newIdpId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
        newIdpId = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CreateIDPResponse(cargo: raw) }
}

/// Control response. Ported from DeleteIDPResponse.java (opcode raw -81).
public struct DeleteIDPResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 175, size: 2, signed: true, type: .response, characteristic: .control, modifiesInsulinDelivery: true)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var deletedIdpId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
        deletedIdpId = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = DeleteIDPResponse(cargo: raw) }
}

/// Control response. Ported from DisconnectPumpResponse.java (opcode raw -65).
public struct DisconnectPumpResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 191, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = DisconnectPumpResponse(cargo: raw) }
}

/// Control response. Ported from FactoryResetBResponse.java.
public struct FactoryResetBResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 125, size: 0, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 0 else { return }
    }
    public mutating func parse(_ raw: [UInt8]) { self = FactoryResetBResponse(cargo: raw) }
}

/// Control response. Ported from FactoryResetResponse.java (opcode raw -23).
public struct FactoryResetResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 233, size: 0, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 0 else { return }
    }
    public mutating func parse(_ raw: [UInt8]) { self = FactoryResetResponse(cargo: raw) }
}

/// Control response. Ported from RenameIDPResponse.java (opcode raw -87).
public struct RenameIDPResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 169, size: 2, signed: true, type: .response, characteristic: .control, modifiesInsulinDelivery: true)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var numberOfProfiles: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
        numberOfProfiles = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = RenameIDPResponse(cargo: raw) }
}

/// Control response. Ported from SendTipsControlGenericTestResponse.java.
public struct SendTipsControlGenericTestResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 119, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SendTipsControlGenericTestResponse(cargo: raw) }
}

/// Control response. Ported from SetBgReminderResponse.java (opcode raw -39).
public struct SetBgReminderResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 217, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetBgReminderResponse(cargo: raw) }
}

/// Control response. Ported from SetG6TransmitterIdResponse.java (opcode raw -79).
public struct SetG6TransmitterIdResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 177, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetG6TransmitterIdResponse(cargo: raw) }
}

/// Control response. Ported from SetIDPSegmentResponse.java (opcode raw -85).
public struct SetIDPSegmentResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 171, size: 2, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var unknown: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
        unknown = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetIDPSegmentResponse(cargo: raw) }
}

/// Control response. Ported from SetIDPSettingsResponse.java (opcode raw -83).
public struct SetIDPSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 173, size: 2, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetIDPSettingsResponse(cargo: raw) }
}

/// Control response. Ported from SetMissedMealBolusReminderResponse.java (opcode raw -37).
public struct SetMissedMealBolusReminderResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 219, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetMissedMealBolusReminderResponse(cargo: raw) }
}

/// Control response. Ported from SetPumpAlertSnoozeResponse.java (opcode raw -43).
public struct SetPumpAlertSnoozeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 213, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetPumpAlertSnoozeResponse(cargo: raw) }
}

/// Control response. Ported from SetQuickBolusSettingsResponse.java (opcode raw -45).
public struct SetQuickBolusSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 211, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetQuickBolusSettingsResponse(cargo: raw) }
}

/// Control response. Ported from SetSiteChangeReminderResponse.java (opcode raw -35).
public struct SetSiteChangeReminderResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 221, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetSiteChangeReminderResponse(cargo: raw) }
}

/// Control response. Ported from SetSleepScheduleResponse.java (opcode raw -49).
public struct SetSleepScheduleResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 207, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = SetSleepScheduleResponse(cargo: raw) }
}

/// Control response. Ported from StreamDataPreflightResponse.java (opcode raw -125).
public struct StreamDataPreflightResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 131, size: 3, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var statusTypeId: Int = 0
    public private(set) var streamTypeId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 3 else { return }
        status = Int(raw[0])
        statusTypeId = Int(raw[1])
        streamTypeId = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = StreamDataPreflightResponse(cargo: raw) }
}

/// Control response. Ported from UserInteractionResponse.java (opcode raw -123).
public struct UserInteractionResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 133, size: 1, signed: true, type: .response, characteristic: .control)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = UserInteractionResponse(cargo: raw) }
}

/// Generic pump error reply (op 77). Sent when a request fails: `requestCodeId` = the failing
/// request's opcode, `errorCodeId` = why. Cargo is 2 bytes (currentStatus) or 26 (control/signed).
/// `response/ErrorResponse`.
public struct ErrorResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 77, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var requestCodeId = 0
    public private(set) var errorCodeId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 2 { requestCodeId = Int(raw[0]); errorCodeId = Int(raw[1]) }
    }
    public mutating func parse(_ raw: [UInt8]) { self = ErrorResponse(cargo: raw) }
    /// errorCodeId 3 = INVALID_PARAMETER (then requestCodeId is the opcode that failed).
    public var isInvalidParameter: Bool { errorCodeId == 3 }
    /// errorCodeId 6 = BAD_OPCODE (reference `ErrorResponse.java`'s `ErrorCode` enum,
    /// `BAD_OPCODE(6)`) — the pump doesn't recognize/support `requestCodeId`. Added for the
    /// pump-pairing-loop debug session's op192 (`CurrentEgvGuiDataV2Request`) fix: an older
    /// t:slim X2 (API < 3.x) replies with this exact error to the newer V2 EGV GUI-data request
    /// and then tears the BLE link down — see `.planning/debug/pump-pairing-loop.md`.
    public var isBadOpcode: Bool { errorCodeId == 6 }
}

// MARK: - Remaining A1 read responses (generated)

/// Read response. Ported from ActiveAamBitsResponse.java (opcode raw -109).
public struct ActiveAamBitsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 147, size: 17, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var unacknowledgedBitmask: UInt64 = 0
    public private(set) var activeBitmask: UInt64 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 17 else { return }
        unacknowledgedBitmask = Bytes.readUint64(raw, 0)
        activeBitmask = Bytes.readUint64(raw, 8)
    }
    public mutating func parse(_ raw: [UInt8]) { self = ActiveAamBitsResponse(cargo: raw) }
}

/// Read response. Ported from BasalIQAlertInfoResponse.java.
public struct BasalIQAlertInfoResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 103, size: 4, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 4 else { return }
        alertId = Int(Bytes.readUint32(raw, 0))
    }
    public mutating func parse(_ raw: [UInt8]) { self = BasalIQAlertInfoResponse(cargo: raw) }
}

/// Read response. Ported from BasalIQSettingsResponse.java.
public struct BasalIQSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 99, size: 3, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var hypoMinimization: Int = 0
    public private(set) var suspendAlert: Int = 0
    public private(set) var resumeAlert: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 3 else { return }
        hypoMinimization = Int(raw[0])
        suspendAlert = Int(raw[1])
        resumeAlert = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = BasalIQSettingsResponse(cargo: raw) }
}

/// Read response. Ported from BasalIQStatusResponse.java.
public struct BasalIQStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 113, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var basalIQStatusState: Int = 0
    public private(set) var deliveringTherapy: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        basalIQStatusState = Int(raw[0])
        deliveringTherapy = raw[1] != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = BasalIQStatusResponse(cargo: raw) }
}

/// Read response. Ported from BleSoftwareInfoResponse.java (opcode raw -119).
public struct BleSoftwareInfoResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 137, size: 14, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var softDeviceId: Int = 0
    public private(set) var softDeviceMajorVersion: Int = 0
    public private(set) var softDeviceMinorVersion: Int = 0
    public private(set) var softDeviceBugfixVersion: Int = 0
    public private(set) var softDeviceVersion: Int = 0
    public private(set) var softDeviceSubVersion: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 14 else { return }
        softDeviceId = Bytes.readShort(raw, 0)
        softDeviceMajorVersion = Bytes.readShort(raw, 2)
        softDeviceMinorVersion = Bytes.readShort(raw, 4)
        softDeviceBugfixVersion = Bytes.readShort(raw, 6)
        softDeviceVersion = Int(Bytes.readUint32(raw, 8))
        softDeviceSubVersion = Bytes.readShort(raw, 12)
    }
    public mutating func parse(_ raw: [UInt8]) { self = BleSoftwareInfoResponse(cargo: raw) }
}

/// Read response. Ported from BolusPermissionChangeReasonResponse.java (opcode raw -87).
public struct BolusPermissionChangeReasonResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 169, size: 5, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bolusId: Int = 0
    public private(set) var isAcked: Bool = false
    public private(set) var lastChangeReasonId: Int = 0
    public private(set) var currentPermissionHolder: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 5 else { return }
        bolusId = Bytes.readShort(raw, 0)
        isAcked = raw[2] != 0
        lastChangeReasonId = Int(raw[3])
        currentPermissionHolder = raw[4] != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = BolusPermissionChangeReasonResponse(cargo: raw) }
}

/// Read response. Ported from CGMGlucoseAlertSettingsResponse.java.
public struct CGMGlucoseAlertSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 91, size: 12, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var highGlucoseAlertThreshold: Int = 0
    public private(set) var highGlucoseAlertEnabled: Int = 0
    public private(set) var highGlucoseRepeatDuration: Int = 0
    public private(set) var highGlucoseAlertDefaultBitmask: Int = 0
    public private(set) var lowGlucoseAlertThreshold: Int = 0
    public private(set) var lowGlucoseAlertEnabled: Int = 0
    public private(set) var lowGlucoseRepeatDuration: Int = 0
    public private(set) var lowGlucoseAlertDefaultBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 12 else { return }
        highGlucoseAlertThreshold = Bytes.readShort(raw, 0)
        highGlucoseAlertEnabled = Int(raw[2])
        highGlucoseRepeatDuration = Bytes.readShort(raw, 3)
        highGlucoseAlertDefaultBitmask = Int(raw[5])
        lowGlucoseAlertThreshold = Bytes.readShort(raw, 6)
        lowGlucoseAlertEnabled = Int(raw[8])
        lowGlucoseRepeatDuration = Bytes.readShort(raw, 9)
        lowGlucoseAlertDefaultBitmask = Int(raw[11])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CGMGlucoseAlertSettingsResponse(cargo: raw) }
}

/// Read response. Ported from CGMOORAlertSettingsResponse.java.
public struct CGMOORAlertSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 95, size: 3, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var sensorTimeoutAlertThreshold: Int = 0
    public private(set) var sensorTimeoutAlertEnabled: Int = 0
    public private(set) var sensorTimeoutDefaultBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 3 else { return }
        sensorTimeoutAlertThreshold = Int(raw[0])
        sensorTimeoutAlertEnabled = Int(raw[1])
        sensorTimeoutDefaultBitmask = Int(raw[2])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CGMOORAlertSettingsResponse(cargo: raw) }
}

/// Read response. Ported from CGMRateAlertSettingsResponse.java.
public struct CGMRateAlertSettingsResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 93, size: 6, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var riseRateThreshold: Int = 0
    public private(set) var riseRateEnabled: Int = 0
    public private(set) var riseRateDefaultBitmask: Int = 0
    public private(set) var fallRateThreshold: Int = 0
    public private(set) var fallRateEnabled: Int = 0
    public private(set) var fallRateDefaultBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 6 else { return }
        riseRateThreshold = Int(raw[0])
        riseRateEnabled = Int(raw[1])
        riseRateDefaultBitmask = Int(raw[2])
        fallRateThreshold = Int(raw[3])
        fallRateEnabled = Int(raw[4])
        fallRateDefaultBitmask = Int(raw[5])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CGMRateAlertSettingsResponse(cargo: raw) }
}

/// Read response. Ported from CgmSupportPackageStatusResponse.java (opcode raw -55).
public struct CgmSupportPackageStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 201, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var validity: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        status = Int(raw[0])
        validity = raw[1] != 0
    }
    public mutating func parse(_ raw: [UInt8]) { self = CgmSupportPackageStatusResponse(cargo: raw) }
}

/// Read response. Ported from CommonSoftwareInfoResponse.java (opcode raw -113).
public struct CommonSoftwareInfoResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 143, size: 60, variableSize: true, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var appSoftwareVersion: String = ""
    public private(set) var appSoftwarePartNumber: Int = 0
    public private(set) var appSoftwarePartDashNumber: Int = 0
    public private(set) var appSoftwarePartRevisionNumber: Int = 0
    public private(set) var bootloaderVersion: String = ""
    public private(set) var bootloaderPartNumber: Int = 0
    public private(set) var bootloaderPartDashNumber: Int = 0
    public private(set) var bootloaderPartRevisionNumber: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 60 else { return }
        appSoftwareVersion = Bytes.readString(raw, 0, 18)
        appSoftwarePartNumber = Int(Bytes.readUint32(raw, 18))
        appSoftwarePartDashNumber = Int(Bytes.readUint32(raw, 22))
        appSoftwarePartRevisionNumber = Int(Bytes.readUint32(raw, 26))
        bootloaderVersion = Bytes.readString(raw, 30, 17)
        bootloaderPartNumber = Int(Bytes.readUint32(raw, 47))
        bootloaderPartDashNumber = Int(Bytes.readUint32(raw, 51))
        bootloaderPartRevisionNumber = Int(Bytes.readUint32(raw, 55))
    }
    public mutating func parse(_ raw: [UInt8]) { self = CommonSoftwareInfoResponse(cargo: raw) }
}

/// Read response. Ported from ControlIQSleepScheduleResponse.java.
/// One Control-IQ sleep-schedule slot (6 bytes). enabled@i, activeDays@i+1 (day bitmask),
/// startTime short@i+2, endTime short@i+4 (minutes-of-day). Mirrors upstream `SleepSchedule`.
public struct SleepSchedule: Sendable, Equatable {
    public let enabled: Bool
    public let activeDays: Int
    public let startTime: Int
    public let endTime: Int
    public init(_ raw: [UInt8], _ i: Int) {
        enabled = raw.count > i && raw[i] != 0
        activeDays = raw.count > i + 1 ? Int(raw[i + 1]) : 0
        startTime = raw.count >= i + 4 ? Bytes.readShort(raw, i + 2) : 0
        endTime = raw.count >= i + 6 ? Bytes.readShort(raw, i + 4) : 0
    }
}

public struct ControlIQSleepScheduleResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 107, size: 24, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var schedules: [SleepSchedule] = []
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 24 else { return }
        schedules = [0, 6, 12, 18].map { SleepSchedule(raw, $0) }   // 4 slots × 6 bytes
    }
    public mutating func parse(_ raw: [UInt8]) { self = ControlIQSleepScheduleResponse(cargo: raw) }
}

/// Read response. Ported from CreateHistoryLogResponse.java.
public struct CreateHistoryLogResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 127, size: 1, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 1 else { return }
        status = Int(raw[0])
    }
    public mutating func parse(_ raw: [UInt8]) { self = CreateHistoryLogResponse(cargo: raw) }
}

/// Read response. Ported from CurrentEGVGuiDataResponse.java.
///
/// The V1 twin of `CurrentEgvGuiDataV2Response` (op 193) — identical 8-byte cargo layout and identical
/// field semantics, and the ONLY EGV read that older t:slim X2 firmware supports. Older pumps reply to
/// the V2 request (op 192) with `ErrorResponse`/BAD_OPCODE and then tear the BLE link down; see
/// `.planning/debug/pump-pairing-loop.md` (on-device capture #6) and `TandemBackend.resolveQueuedRead`,
/// which substitutes the V1 request for the V2 one on those pumps. The parity helpers below mirror the
/// V2 struct's exactly so both responses can feed one shared consumer path.
public struct CurrentEGVGuiDataResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 35, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bgReadingTimestampSeconds: Int = 0
    public private(set) var cgmReading: Int = 0
    public private(set) var egvStatusId: Int = 0
    public private(set) var trendRate: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 8 else { return }
        bgReadingTimestampSeconds = Int(Bytes.readUint32(raw, 0))
        cgmReading = Bytes.readShort(raw, 4)
        egvStatusId = Int(raw[6])
        // SIGNED, matching both the reference (`CurrentEGVGuiDataResponse.java`: `this.trendRate =
        // raw[7];` — Java's `byte` sign-extends into the int field) and the V2 twin. This was
        // previously `Int(raw[7])`, an unsigned read: a falling rate of -0.1 mg/dL/min (0xFF) decoded
        // as +25.5, i.e. every FALLING trend rendered as RAPIDLY RISING. That is the same defect class
        // the V2 struct's own `trendRateIsUnavailable` doc comment describes ("app shows double-up when
        // the pump shows no arrow"), and it was latent only because nothing consumed this response yet.
        trendRate = Int(Int8(bitPattern: raw[7]))
    }
    public mutating func parse(_ raw: [UInt8]) { self = CurrentEGVGuiDataResponse(cargo: raw) }

    // MARK: - Parity helpers (mirror `CurrentEgvGuiDataV2Response`; see its doc comments for rationale)

    /// `trendRate` is a signed byte in 0.1 mg/dL/min units.
    public var trendRateMgDlPerMin: Double { Double(trendRate) / 10.0 }
    /// `true` when `trendRate` is a **sentinel** ("rate unavailable") rather than a real rate.
    public var trendRateIsUnavailable: Bool {
        trendRate >= Int(Int8.max) || trendRate <= Int(Int8.min)
    }
    /// The trend rate, or `nil` when the pump has no usable rate.
    public var trendRateIfKnown: Double? {
        guard hasValidReading, !trendRateIsUnavailable else { return nil }
        return trendRateMgDlPerMin
    }
    /// A trend arrow derived client-side from `trendRate`, or `nil` when the rate is unknown.
    /// **Prefer `HomeScreenMirrorResponse.cgmTrendArrow`** — see `EgvTrend.arrow(forRate:)`.
    public var trendArrow: String? { EgvTrend.arrow(forRate: trendRateIfKnown) }
    /// EGV status per upstream: 0=INVALID, 1=VALID, 2=LOW, 3=HIGH, 4=UNAVAILABLE.
    public var hasValidReading: Bool {
        (egvStatusId == 1 || egvStatusId == 2 || egvStatusId == 3) && cgmReading > 0 && cgmReading < 600
    }
}

/// Read response. Ported from ExtendedBolusStatusResponse.java.
public struct ExtendedBolusStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 47, size: 18, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var bolusStatus: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var requestedVolume: Int = 0
    public private(set) var duration: Int = 0
    public private(set) var bolusSource: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 18 else { return }
        bolusStatus = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        timestamp = Int(Bytes.readUint32(raw, 5))
        requestedVolume = Int(Bytes.readUint32(raw, 9))
        duration = Int(Bytes.readUint32(raw, 13))
        bolusSource = Int(raw[17])
    }
    public mutating func parse(_ raw: [UInt8]) { self = ExtendedBolusStatusResponse(cargo: raw) }
}

/// Read response. Ported from GetG6TransmitterHardwareInfoResponse.java (opcode raw -59).
public struct GetG6TransmitterHardwareInfoResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 197, size: 96, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var transmitterFirmwareVersion: String = ""
    public private(set) var transmitterHardwareRevision: String = ""
    public private(set) var transmitterBleHardwareId: String = ""
    public private(set) var transmitterSoftwareNumber: String = ""
    public private(set) var transmitterPairingCode: String = ""
    public private(set) var transmitterSerialNumber: String = ""
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 96 else { return }
        transmitterFirmwareVersion = Bytes.readString(raw, 0, 16)
        transmitterHardwareRevision = Bytes.readString(raw, 16, 16)
        transmitterBleHardwareId = Bytes.readString(raw, 32, 16)
        transmitterSoftwareNumber = Bytes.readString(raw, 48, 16)
        transmitterPairingCode = Bytes.readString(raw, 64, 16)
        transmitterSerialNumber = Bytes.readString(raw, 80, 16)
    }
    public mutating func parse(_ raw: [UInt8]) { self = GetG6TransmitterHardwareInfoResponse(cargo: raw) }
}

/// Read response. Ported from GetSavedG7PairingCodeResponse.java.
public struct GetSavedG7PairingCodeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 117, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var pairingCode: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        pairingCode = Bytes.readShort(raw, 0)
    }
    public mutating func parse(_ raw: [UInt8]) { self = GetSavedG7PairingCodeResponse(cargo: raw) }
}

/// Read response. Ported from HighestAamResponse.java.
public struct HighestAamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 121, size: 11, variableSize: true, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var aamId: Int = 0
    public private(set) var faultId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 11 else { return }
        aamId = Int(Bytes.readUint32(raw, 0))
        faultId = Int(Bytes.readUint32(raw, 4))
    }
    public mutating func parse(_ raw: [UInt8]) { self = HighestAamResponse(cargo: raw) }
}

/// Read response. Ported from LastBolusStatusResponse.java.
public struct LastBolusStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 49, size: 20, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var deliveredVolume: Int = 0
    public private(set) var bolusStatusId: Int = 0
    public private(set) var bolusSourceId: Int = 0
    public private(set) var bolusTypeBitmask: Int = 0
    public private(set) var extendedBolusDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 20 else { return }
        status = Int(raw[0])
        bolusId = Bytes.readShort(raw, 1)
        timestamp = Int(Bytes.readUint32(raw, 5))
        deliveredVolume = Int(Bytes.readUint32(raw, 9))
        bolusStatusId = Int(raw[13])
        bolusSourceId = Int(raw[14])
        bolusTypeBitmask = Int(raw[15])
        extendedBolusDuration = Int(Bytes.readUint32(raw, 16))
    }
    public mutating func parse(_ raw: [UInt8]) { self = LastBolusStatusResponse(cargo: raw) }
}

/// Read response. Ported from LastBolusStatusV3Response.java (opcode raw -69).
public struct LastBolusStatusV3Response: ResponseMessage {
    public static let props = MessageProps(opCode: 187, size: 53, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var lastBolusTypeBitmask: Int = 0
    public private(set) var standardBolusStatusId: Int = 0
    public private(set) var standardBolusId: Int = 0
    public private(set) var standardBolusTimestamp: Int = 0
    public private(set) var standardBolusDeliveredVolume: Int = 0
    public private(set) var standardBolusEndReasonId: Int = 0
    public private(set) var standardBolusSourceId: Int = 0
    public private(set) var standardBolusTypeBitmask: Int = 0
    public private(set) var standardBolusRequestedVolume: Int = 0
    public private(set) var standardBolusSecondsSincePumpReset: Int = 0
    public private(set) var extendedBolusStatusId: Int = 0
    public private(set) var extendedBolusId: Int = 0
    public private(set) var extendedBolusTimestamp: Int = 0
    public private(set) var extendedBolusDeliveredVolume: Int = 0
    public private(set) var extendedBolusEndReasonId: Int = 0
    public private(set) var extendedBolusSourceId: Int = 0
    public private(set) var extendedBolusTypeBitmask: Int = 0
    public private(set) var extendedBolusRequestedVolume: Int = 0
    public private(set) var extendedBolusSecondsSincePumpReset: Int = 0
    public private(set) var extendedBolusDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 53 else { return }
        lastBolusTypeBitmask = Int(raw[0])
        standardBolusStatusId = Int(raw[1])
        standardBolusId = Bytes.readShort(raw, 2)
        standardBolusTimestamp = Int(Bytes.readUint32(raw, 6))
        standardBolusDeliveredVolume = Int(Bytes.readUint32(raw, 10))
        standardBolusEndReasonId = Int(raw[14])
        standardBolusSourceId = Int(raw[15])
        standardBolusTypeBitmask = Int(raw[16])
        standardBolusRequestedVolume = Int(Bytes.readUint32(raw, 17))
        standardBolusSecondsSincePumpReset = Int(Bytes.readUint32(raw, 21))
        extendedBolusStatusId = Int(raw[25])
        extendedBolusId = Bytes.readShort(raw, 26)
        extendedBolusTimestamp = Int(Bytes.readUint32(raw, 30))
        extendedBolusDeliveredVolume = Int(Bytes.readUint32(raw, 34))
        extendedBolusEndReasonId = Int(raw[38])
        extendedBolusSourceId = Int(raw[39])
        extendedBolusTypeBitmask = Int(raw[40])
        extendedBolusRequestedVolume = Int(Bytes.readUint32(raw, 41))
        extendedBolusSecondsSincePumpReset = Int(Bytes.readUint32(raw, 45))
        extendedBolusDuration = Int(Bytes.readUint32(raw, 49))
    }
    public mutating func parse(_ raw: [UInt8]) { self = LastBolusStatusV3Response(cargo: raw) }
}

/// Read response. Ported from LocalizationResponse.java (opcode raw -89).
public struct LocalizationResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 167, size: 7, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var glucoseUOM: Int = 0
    public private(set) var languageSelected: Int = 0
    public private(set) var regionSetting: Int = 0
    public private(set) var languagesAvailableBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 7 else { return }
        glucoseUOM = Int(raw[0])
        languageSelected = Int(raw[1])
        regionSetting = Int(raw[2])
        languagesAvailableBitmask = Int(Bytes.readUint32(raw, 3))
    }
    public mutating func parse(_ raw: [UInt8]) { self = LocalizationResponse(cargo: raw) }
}

/// Read response. Ported from PumpFeaturesV2Response.java (opcode raw -95).
public struct PumpFeaturesV2Response: ResponseMessage {
    public static let props = MessageProps(opCode: 161, size: 6, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public private(set) var supportedFeatureIndexId: Int = 0
    public private(set) var pumpFeaturesBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 6 else { return }
        status = Int(raw[0])
        supportedFeatureIndexId = Int(raw[1])
        pumpFeaturesBitmask = Int(Bytes.readUint32(raw, 2))
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpFeaturesV2Response(cargo: raw) }
}

/// Read response. Ported from PumpVersionBResponse.java (opcode raw -123).
public struct PumpVersionBResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 133, size: 60, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var softwareName: String = ""
    public private(set) var configurationBitsA: Int = 0
    public private(set) var configurationBitsB: Int = 0
    public private(set) var serialNumber: Int = 0
    public private(set) var modelNumber: Int = 0
    public private(set) var pumpRevision: String = ""
    public private(set) var pcbPartNumberA: Int = 0
    public private(set) var pcbSerialNumberA: Int = 0
    public private(set) var pcbRevisionNumberA: String = ""
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 60 else { return }
        softwareName = Bytes.readString(raw, 0, 20)
        configurationBitsA = Int(Bytes.readUint32(raw, 20))
        configurationBitsB = Int(Bytes.readUint32(raw, 24))
        serialNumber = Int(Bytes.readUint32(raw, 28))
        modelNumber = Int(Bytes.readUint32(raw, 32))
        pumpRevision = Bytes.readString(raw, 36, 8)
        pcbPartNumberA = Int(Bytes.readUint32(raw, 44))
        pcbSerialNumberA = Int(Bytes.readUint32(raw, 48))
        pcbRevisionNumberA = Bytes.readString(raw, 52, 8)
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpVersionBResponse(cargo: raw) }
}

/// Read response. Ported from RemindersResponse.java.
public struct RemindersResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 89, size: 105, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var lowBGThreshold: Int = 0
    public private(set) var highBGThreshold: Int = 0
    public private(set) var siteChangeDays: Int = 0
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 105 else { return }
        lowBGThreshold = Bytes.readShort(raw, 99)
        highBGThreshold = Bytes.readShort(raw, 101)
        siteChangeDays = Int(raw[103])
        status = Int(raw[104])
    }
    public mutating func parse(_ raw: [UInt8]) { self = RemindersResponse(cargo: raw) }
}

/// Read response. Ported from SecretMenuResponse.java (opcode raw -67).
public struct SecretMenuResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 189, size: 8, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var timeOfLastConnectionTimestampSeconds: Int = 0
    public private(set) var reservedValue: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 8 else { return }
        timeOfLastConnectionTimestampSeconds = Int(Bytes.readUint32(raw, 0))
        reservedValue = Int(Bytes.readUint32(raw, 4))
    }
    public mutating func parse(_ raw: [UInt8]) { self = SecretMenuResponse(cargo: raw) }
}

/// Read response. Ported from StreamDataReadinessResponse.java (opcode raw -57).
public struct StreamDataReadinessResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 199, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var freestyleLibre2ReadinessId: Int = 0
    public private(set) var streamDataTypeOrdinal: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        freestyleLibre2ReadinessId = Int(raw[0])
        streamDataTypeOrdinal = Int(raw[1])
    }
    public mutating func parse(_ raw: [UInt8]) { self = StreamDataReadinessResponse(cargo: raw) }
}

/// Read response. Ported from UnknownMobiOpcode110Response.java.
public struct UnknownMobiOpcode110Response: ResponseMessage {
    public static let props = MessageProps(opCode: 111, size: 4, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 4 else { return }
    }
    public mutating func parse(_ raw: [UInt8]) { self = UnknownMobiOpcode110Response(cargo: raw) }
}

/// Read response. Ported from TempRateResponse.java.
public struct TempRateResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 43, size: 10, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var active: Bool = false
    public private(set) var percentage: Int = 0
    public private(set) var startTimeRaw: Int = 0
    public private(set) var duration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 10 else { return }
        active = raw[0] != 0
        percentage = Int(raw[1])
        startTimeRaw = Int(Bytes.readUint32(raw, 2))
        duration = Int(Bytes.readUint32(raw, 6))
    }
    public mutating func parse(_ raw: [UInt8]) { self = TempRateResponse(cargo: raw) }
}
