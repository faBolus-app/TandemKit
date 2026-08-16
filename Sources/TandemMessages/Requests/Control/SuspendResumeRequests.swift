import Foundation

/// Suspends insulin delivery on the pump. Signed, empty cargo, and **modifies insulin delivery**
/// (so the BLE write-policy must be raised to allow it). Port of
/// `request/control/SuspendPumpingRequest` (opcode -100 / 0x9C).
public struct SuspendPumpingRequest: Message {
    public static let props = MessageProps(
        opCode: 0x9C, size: 0, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0x9D)
    public var cargo: [UInt8]
    public init() { self.cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { self.cargo = [] }   // size 0 — empty cargo
}

/// Resumes insulin delivery on the pump. Signed, empty cargo, modifies insulin delivery. Port of
/// `request/control/ResumePumpingRequest` (opcode -102 / 0x9A).
public struct ResumePumpingRequest: Message {
    public static let props = MessageProps(
        opCode: 0x9A, size: 0, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0x9B)
    public var cargo: [UInt8]
    public init() { self.cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { self.cargo = [] }
}
