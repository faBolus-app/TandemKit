import Foundation

/// Power-user / dangerous control commands + internal-stream/test commands (A2). Signed CONTROL.
/// The pump-lifecycle ones (factory reset, shelf mode, disconnect) are destructive — the app must
/// expose them ONLY via the hidden Debug menu, never the normal control surface. Ports of the
/// corresponding `request/control/*Request` classes.

/// Activates shelf/storage mode (opcode 0xBA → 0xBB). Empty cargo. Dangerous.
public struct ActivateShelfModeRequest: Message {
    public static let props = MessageProps(opCode: 0xBA, size: 0, signed: true, type: .request, characteristic: .control, risk: .destructive, responseOpCode: 0xBB)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Disconnects the pump BLE session (opcode 0xBE → 0xBF). Empty cargo. Dangerous.
public struct DisconnectPumpRequest: Message {
    public static let props = MessageProps(opCode: 0xBE, size: 0, signed: true, type: .request, characteristic: .control, risk: .destructive, responseOpCode: 0xBF)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Factory reset (opcode 0xE8 → 0xE9). 8-byte cargo: uint32 key + uint32 serialNumber. DESTRUCTIVE.
public struct FactoryResetRequest: Message {
    public static let props = MessageProps(opCode: 0xE8, size: 8, signed: true, type: .request, characteristic: .control, risk: .destructive, responseOpCode: 0xE9)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(key: UInt32, serialNumber: UInt32) {
        self.cargo = Bytes.combine(Bytes.toUint32(key), Bytes.toUint32(serialNumber))
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Factory reset "B" variant (opcode 0x7C → 0x7D). 9-byte cargo: uint32 key + uint32 serialNumber
/// + enableShelfMode. DESTRUCTIVE.
public struct FactoryResetBRequest: Message {
    public static let props = MessageProps(opCode: 0x7C, size: 9, signed: true, type: .request, characteristic: .control, risk: .destructive, responseOpCode: 0x7D)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(key: UInt32, serialNumber: UInt32, enableShelfMode: Bool) {
        self.cargo = Bytes.combine(Bytes.toUint32(key), Bytes.toUint32(serialNumber), [enableShelfMode ? 1 : 0])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Marks a user interaction (opcode 0x84 → 0x85). Empty cargo.
public struct UserInteractionRequest: Message {
    public static let props = MessageProps(opCode: 0x84, size: 0, signed: true, type: .request, characteristic: .control, responseOpCode: 0x85)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Preflight for a data stream (opcode 0x82 → 0x83). Cargo: streamType + LE uint16 length + hmac.
public struct StreamDataPreflightRequest: Message {
    public static let props = MessageProps(opCode: 0x82, size: 3, signed: true, type: .request, characteristic: .control, responseOpCode: 0x83)
    public var cargo: [UInt8]
    public private(set) var streamType = 0, length = 0
    public init() { cargo = [] }
    public init(streamType: Int, length: Int, hmac: [UInt8]) {
        self.streamType = streamType; self.length = length
        self.cargo = Bytes.combine([UInt8(streamType & 0xFF)], Bytes.firstTwoBytesLittleEndian(length), hmac)
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// TIPS control generic test (opcode 0x76 → 0x77). 24-byte cargo: 6 × uint32 params.
public struct SendTipsControlGenericTestRequest: Message {
    public static let props = MessageProps(opCode: 0x76, size: 24, signed: true, type: .request, characteristic: .control, responseOpCode: 0x77)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(param1: UInt32, param2: UInt32, param3: UInt32, param4: UInt32, param5: UInt32, param6: UInt32) {
        self.cargo = Bytes.combine(Bytes.toUint32(param1), Bytes.toUint32(param2), Bytes.toUint32(param3),
                                   Bytes.toUint32(param4), Bytes.toUint32(param5), Bytes.toUint32(param6))
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}
