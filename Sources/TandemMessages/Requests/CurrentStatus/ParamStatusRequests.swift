import Foundation

/// Parameterized CURRENT_STATUS read requests (carry a small cargo, unsigned). Ports of the
/// corresponding `request/currentStatus/*Request` classes.

/// Reads why a bolus permission changed, for a given bolusId (opcode 0xA8 → 0xA9). LE uint16 cargo.
public struct BolusPermissionChangeReasonRequest: Message {
    public static let props = MessageProps(opCode: 0xA8, size: 2, type: .request, characteristic: .currentStatus, responseOpCode: 0xA9)
    public var cargo: [UInt8]
    public private(set) var bolusId = 0
    public init() { cargo = [] }
    public init(bolusId: Int) { self.bolusId = bolusId; cargo = Bytes.firstTwoBytesLittleEndian(bolusId) }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if b.count >= 2 { bolusId = Bytes.readShort(b, 0) } }
}

/// CGM support-package status for a device type (opcode 0xC8 → 0xC9). 1-byte cargo.
public struct CgmSupportPackageStatusRequest: Message {
    public static let props = MessageProps(opCode: 0xC8, size: 1, type: .request, characteristic: .currentStatus, responseOpCode: 0xC9)
    public var cargo: [UInt8]
    public private(set) var deviceType = 0
    public init() { cargo = [] }
    public init(deviceType: Int) { self.deviceType = deviceType; cargo = [UInt8(deviceType & 0xFF)] }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if !b.isEmpty { deviceType = Int(b[0]) } }
}

/// Common software info for an MCU type (opcode 0x8E → 0x8F). 1-byte cargo.
public struct CommonSoftwareInfoRequest: Message {
    public static let props = MessageProps(opCode: 0x8E, size: 1, type: .request, characteristic: .currentStatus, responseOpCode: 0x8F)
    public var cargo: [UInt8]
    public private(set) var mcuType = 0
    public init() { cargo = [] }
    public init(mcuType: Int) { self.mcuType = mcuType; cargo = [UInt8(mcuType & 0xFF)] }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if !b.isEmpty { mcuType = Int(b[0]) } }
}

/// Creates a history-log query for `numberOfLogs` (opcode 0x7E → 0x7F). uint32 cargo.
public struct CreateHistoryLogRequest: Message {
    public static let props = MessageProps(opCode: 0x7E, size: 4, type: .request, characteristic: .currentStatus, responseOpCode: 0x7F)
    public var cargo: [UInt8]
    public private(set) var numberOfLogs: UInt32 = 0
    public init() { cargo = [] }
    public init(numberOfLogs: UInt32) { self.numberOfLogs = numberOfLogs; cargo = Bytes.toUint32(numberOfLogs) }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if b.count >= 4 { numberOfLogs = Bytes.readUint32(b, 0) } }
}

/// Stream-data readiness for a stream type (opcode 0xC6 → 0xC7). 1-byte cargo.
public struct StreamDataReadinessRequest: Message {
    public static let props = MessageProps(opCode: 0xC6, size: 1, type: .request, characteristic: .currentStatus, responseOpCode: 0xC7)
    public var cargo: [UInt8]
    public private(set) var streamDataType = 0
    public init() { cargo = [] }
    public init(streamDataType: Int) { self.streamDataType = streamDataType; cargo = [UInt8(streamDataType & 0xFF)] }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if !b.isEmpty { streamDataType = Int(b[0]) } }
}

/// Pump feature set v2, selected by a feature index (opcode 0xA0 → 0xA1). 1-byte cargo (default 2).
public struct PumpFeaturesV2Request: Message {
    public static let props = MessageProps(opCode: 0xA0, size: 1, type: .request, characteristic: .currentStatus, responseOpCode: 0xA1)
    public var cargo: [UInt8]
    public private(set) var input = 2
    public init() { self.init(input: 2) }
    public init(input: Int) { self.input = input; cargo = Bytes.firstByteLittleEndian(input) }
    public mutating func parse(_ raw: [UInt8]) { let b = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3); cargo = b; if !b.isEmpty { input = Int(b[0]) } }
}

/// Active auto-adjustment-mode bits (opcode 0x92 → 0x93). Upstream's default cargo is EMPTY.
public struct ActiveAamBitsRequest: Message {
    public static let props = MessageProps(opCode: 0x92, size: 1, type: .request, characteristic: .currentStatus, responseOpCode: 0x93)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = raw }
}
