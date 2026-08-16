import Foundation

/// Releases (relinquishes) a previously granted bolus permission by `bolusID`. Signed.
/// Port of `request/control/BolusPermissionReleaseRequest` (opcode 0xF0 / -16, size 4 + HMAC).
public struct BolusPermissionReleaseRequest: Message {
    public static let props = MessageProps(
        opCode: 0xF0,               // -16 as unsigned
        size: 4,
        signed: true,
        type: .request,
        characteristic: .control,
        responseOpCode: 0xF1        // BolusPermissionReleaseResponse
    )

    public var cargo: [UInt8]
    public private(set) var bolusID: Int = 0
    public private(set) var reserve: Int = 0

    public init() { self.cargo = [] }

    public init(bolusID: Int, reserve: Int = 0) {
        self.cargo = Self.buildCargo(bolusID: bolusID, reserve: reserve)
        self.bolusID = bolusID
        self.reserve = reserve
    }

    public mutating func parse(_ raw: [UInt8]) {
        let raw = removeSignedRequestHmacBytes(raw)
        precondition(raw.count == Self.props.size)
        self.cargo = raw
        self.bolusID = Bytes.readShort(raw, 0)
        self.reserve = Bytes.readShort(raw, 2)
    }

    public static func buildCargo(bolusID: Int, reserve: Int) -> [UInt8] {
        Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bolusID),
            Bytes.firstTwoBytesLittleEndian(reserve)
        )
    }
}
