import Foundation

/// Sounds / find-my-pump / time-date control commands (A2). Signed CONTROL writes that don't touch
/// insulin delivery. Ports of `request/control/{PlaySound,SetPumpSounds,ChangeTimeDate}Request`.

/// Plays the "find my pump" sound (opcode 0xF4 → 0xF5). Empty cargo.
public struct PlaySoundRequest: Message {
    public static let props = MessageProps(
        opCode: 0xF4, size: 0, signed: true, type: .request,
        characteristic: .control, risk: .benign, responseOpCode: 0xF5)   // find-my-pump — no therapy effect (P-01)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Sets per-category annunciation (audio/vibrate) modes (opcode 0xE4 → 0xE5). 9-byte cargo:
/// firstByteUnknown(0) + quickBolus + general + reminder + alert + alarm + cgmA + cgmB + changeBitmask.
/// Annunciation values per PumpGlobalsResponse.AnnunciationEnum (0=audioHigh…3=vibrate).
public struct SetPumpSoundsRequest: Message {
    public static let props = MessageProps(
        opCode: 0xE4, size: 9, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xE5)
    public var cargo: [UInt8]
    public private(set) var quickBolusAnnunRaw = 0
    public private(set) var generalAnnunRaw = 0
    public private(set) var reminderAnnunRaw = 0
    public private(set) var alertAnnunRaw = 0
    public private(set) var alarmAnnunRaw = 0
    public private(set) var cgmAlertAnnunA = 0
    public private(set) var cgmAlertAnnunB = 0
    public private(set) var changeBitmaskRaw = 0
    public init() { cargo = [] }
    public init(quickBolusAnnunRaw: Int, generalAnnunRaw: Int, reminderAnnunRaw: Int,
                alertAnnunRaw: Int, alarmAnnunRaw: Int, cgmAlertAnnunA: Int, cgmAlertAnnunB: Int,
                changeBitmaskRaw: Int) {
        self.quickBolusAnnunRaw = quickBolusAnnunRaw
        self.generalAnnunRaw = generalAnnunRaw
        self.reminderAnnunRaw = reminderAnnunRaw
        self.alertAnnunRaw = alertAnnunRaw
        self.alarmAnnunRaw = alarmAnnunRaw
        self.cgmAlertAnnunA = cgmAlertAnnunA
        self.cgmAlertAnnunB = cgmAlertAnnunB
        self.changeBitmaskRaw = changeBitmaskRaw
        self.cargo = [0, UInt8(quickBolusAnnunRaw & 0xFF), UInt8(generalAnnunRaw & 0xFF),
                      UInt8(reminderAnnunRaw & 0xFF), UInt8(alertAnnunRaw & 0xFF),
                      UInt8(alarmAnnunRaw & 0xFF), UInt8(cgmAlertAnnunA & 0xFF),
                      UInt8(cgmAlertAnnunB & 0xFF), UInt8(changeBitmaskRaw & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        guard body.count >= 9 else { return }
        quickBolusAnnunRaw = Int(body[1]); generalAnnunRaw = Int(body[2])
        reminderAnnunRaw = Int(body[3]); alertAnnunRaw = Int(body[4])
        alarmAnnunRaw = Int(body[5]); cgmAlertAnnunA = Int(body[6])
        cgmAlertAnnunB = Int(body[7]); changeBitmaskRaw = Int(body[8])
    }
}

/// Sets the pump clock (opcode 0xD6 → 0xD7). 4-byte cargo: uint32 Tandem-epoch seconds
/// (seconds since Jan 1 2008 — see `HistoryLog.jan12008UnixEpoch`).
public struct ChangeTimeDateRequest: Message {
    public static let props = MessageProps(
        opCode: 0xD6, size: 4, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xD7)
    public var cargo: [UInt8]
    public private(set) var tandemEpochTime: UInt32 = 0
    public init() { cargo = [] }
    public init(tandemEpochTime: UInt32) {
        self.tandemEpochTime = tandemEpochTime
        self.cargo = Bytes.toUint32(tandemEpochTime)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 4 { tandemEpochTime = Bytes.readUint32(body, 0) }
    }
}
