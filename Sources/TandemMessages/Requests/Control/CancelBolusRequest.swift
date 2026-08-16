import Foundation

/// Cancels/terminates an in-progress bolus (phone- or pump-initiated, including extended).
/// Signed. Port of `request/control/CancelBolusRequest` (opcode 0xA0 / -96, size 4 + HMAC).
public struct CancelBolusRequest: Message {
    public static let props = MessageProps(
        opCode: 0xA0,               // -96 as unsigned
        size: 4,
        signed: true,
        type: .request,
        characteristic: .control,
        responseOpCode: 0xA1        // CancelBolusResponse
    )

    public var cargo: [UInt8]
    public private(set) var bolusId: Int = 0

    public init() { self.cargo = [] }

    public init(bolusId: Int) {
        self.cargo = Self.buildCargo(bolusId: bolusId)
        self.bolusId = bolusId
    }

    public mutating func parse(_ raw: [UInt8]) {
        let raw = removeSignedRequestHmacBytes(raw)
        precondition(raw.count == Self.props.size)
        self.cargo = raw
        self.bolusId = Bytes.readShort(raw, 0)
    }

    public static func buildCargo(bolusId: Int) -> [UInt8] {
        Bytes.combine(Bytes.firstTwoBytesLittleEndian(bolusId), [0, 0])
    }
}
