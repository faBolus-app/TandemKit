import Foundation

/// CONTROL_STREAM state responses (A3) — progress feedback during the cartridge-change / fill
/// workflow. Several upstream classes share an opcode (e.g. -29 Detecting/Load, -23 ExitFillTubing/
/// Prime/Pumping); upstream's `Messages` map registers ONE representative per opcode, and its fields
/// are a compatible superset. We mirror that: register the representative and parse its layout;
/// variant-specific fields are not separately decoded (matching upstream dispatch). Ports of
/// `response/controlStream/*StateStreamResponse`.

/// Enter-change-cartridge-mode state (op 0xE1). stateId@0.
public struct EnterChangeCartridgeModeStateStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE1, size: 1, type: .response, characteristic: .controlStream)
    public var cargo: [UInt8]
    public private(set) var stateId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; if !raw.isEmpty { stateId = Int(raw[0]) } }
    public mutating func parse(_ raw: [UInt8]) { self = EnterChangeCartridgeModeStateStreamResponse(cargo: raw) }
}

/// Detecting-cartridge state (op 0xE3, representative for the -29 group; also load-cartridge).
/// percentComplete = short@0.
public struct DetectingCartridgeStateStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE3, size: 2, type: .response, characteristic: .controlStream)
    public var cargo: [UInt8]
    public private(set) var percentComplete = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; if raw.count >= 2 { percentComplete = Bytes.readShort(raw, 0) } }
    public mutating func parse(_ raw: [UInt8]) { self = DetectingCartridgeStateStreamResponse(cargo: raw) }
}

/// Fill-tubing state (op 0xE5). buttonState@0.
public struct FillTubingStateStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE5, size: 1, type: .response, characteristic: .controlStream)
    public var cargo: [UInt8]
    public private(set) var buttonState = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; if !raw.isEmpty { buttonState = Int(raw[0]) } }
    public mutating func parse(_ raw: [UInt8]) { self = FillTubingStateStreamResponse(cargo: raw) }
}

/// Fill-cannula state (op 0xE7). stateId@0.
public struct FillCannulaStateStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE7, size: 1, type: .response, characteristic: .controlStream)
    public var cargo: [UInt8]
    public private(set) var stateId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; if !raw.isEmpty { stateId = Int(raw[0]) } }
    public mutating func parse(_ raw: [UInt8]) { self = FillCannulaStateStreamResponse(cargo: raw) }
}

/// Exit-fill-tubing-mode state (op 0xE9, representative for the -23 group; also prime/pumping).
/// stateId@0.
public struct ExitFillTubingModeStateStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 0xE9, size: 1, type: .response, characteristic: .controlStream)
    public var cargo: [UInt8]
    public private(set) var stateId = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) { cargo = raw; if !raw.isEmpty { stateId = Int(raw[0]) } }
    public mutating func parse(_ raw: [UInt8]) { self = ExitFillTubingModeStateStreamResponse(cargo: raw) }
}
