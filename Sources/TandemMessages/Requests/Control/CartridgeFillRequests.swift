import Foundation

/// Cartridge-change / tubing-fill / cannula-fill workflow commands (A2, Mobi). Signed CONTROL
/// writes. The "enter mode" and fill/prime steps dispense or interrupt insulin, so those carry
/// `modifiesInsulinDelivery=true` — they require WritePolicy `.allowDelivery` + bench (saline)
/// validation + the advanced-control gate. Progress feedback arrives on CONTROL_STREAM (A3,
/// deferred until the cartridge UI is built). Ports of the `request/control/*CartridgeMode`,
/// `*FillTubingMode`, `FillCannula`, `PrimeTubingSuspend` classes.

/// Enters cartridge-change mode (opcode 0x90 → 0x91). Stops delivery.
public struct EnterChangeCartridgeModeRequest: Message {
    public static let props = MessageProps(
        opCode: 0x90, size: 0, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0x91)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Exits cartridge-change mode (opcode 0x92 → 0x93).
public struct ExitChangeCartridgeModeRequest: Message {
    public static let props = MessageProps(
        opCode: 0x92, size: 0, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0x93)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Enters fill-tubing mode (opcode 0x94 → 0x95). Dispenses insulin to prime tubing.
public struct EnterFillTubingModeRequest: Message {
    public static let props = MessageProps(
        opCode: 0x94, size: 0, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0x95)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Exits fill-tubing mode (opcode 0x96 → 0x97).
public struct ExitFillTubingModeRequest: Message {
    public static let props = MessageProps(
        opCode: 0x96, size: 0, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0x97)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Fills the cannula with `primeSize` milliunits (opcode 0x98 → 0x99). Dispenses insulin.
/// 2-byte LE cargo.
public struct FillCannulaRequest: Message {
    public static let props = MessageProps(
        opCode: 0x98, size: 2, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0x99)
    public var cargo: [UInt8]
    public private(set) var primeSize = 0
    public init() { cargo = [] }
    public init(primeSize: Int) {
        self.primeSize = primeSize
        self.cargo = Bytes.firstTwoBytesLittleEndian(primeSize)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 2 { primeSize = Bytes.readShort(body, 0) }
    }
}

/// Suspends the prime/tubing step (opcode 0xEE → 0xEF).
public struct PrimeTubingSuspendRequest: Message {
    public static let props = MessageProps(
        opCode: 0xEE, size: 0, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xEF)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}
