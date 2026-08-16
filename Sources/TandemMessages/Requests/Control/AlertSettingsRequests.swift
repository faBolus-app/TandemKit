import Foundation

/// Alert-threshold settings (A2). Signed CONTROL writes, non-insulin-affecting. Ports of
/// `request/control/{SetLowInsulinAlert,SetAutoOffAlert}Request`.

/// Sets the low-insulin (reservoir) alert threshold in units (opcode 0xDE → 0xDF). 1-byte cargo.
public struct SetLowInsulinAlertRequest: Message {
    public static let props = MessageProps(
        opCode: 0xDE, size: 1, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xDF)
    public var cargo: [UInt8]
    public private(set) var insulinThreshold = 0
    public init() { cargo = [] }
    public init(insulinThreshold: Int) {
        self.insulinThreshold = insulinThreshold
        self.cargo = [UInt8(insulinThreshold & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if !body.isEmpty { insulinThreshold = Int(body[0]) }
    }
}

/// Sets the auto-off (no-activity shutoff) alert (opcode 0xE0 → 0xE1). 4-byte cargo:
/// enable byte + LE uint16 duration (minutes) + bitmask byte.
public struct SetAutoOffAlertRequest: Message {
    public static let props = MessageProps(
        opCode: 0xE0, size: 4, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xE1)
    public var cargo: [UInt8]
    public private(set) var enableAutoOff = false
    public private(set) var autoOffDuration = 0
    public private(set) var bitmask = 0
    public init() { cargo = [] }
    public init(enableAutoOff: Bool, autoOffDuration: Int, bitmask: Int) {
        self.enableAutoOff = enableAutoOff
        self.autoOffDuration = autoOffDuration
        self.bitmask = bitmask
        self.cargo = Bytes.combine(
            [enableAutoOff ? 1 : 0],
            Bytes.firstTwoBytesLittleEndian(autoOffDuration),
            [UInt8(bitmask & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        guard body.count >= 4 else { return }
        enableAutoOff = body[0] != 0
        autoOffDuration = Bytes.readShort(body, 1)
        bitmask = Int(body[3])
    }
}
