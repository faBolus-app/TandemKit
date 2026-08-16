import Foundation

/// Requests permission to bolus; the response carries a `bolusId` used to complete the bolus.
/// First step of the bolus flow. Signed. Port of `request/control/BolusPermissionRequest`
/// (opcode 0xA2 / -94).
public struct BolusPermissionRequest: Message {
    public static let props = MessageProps(
        opCode: 0xA2,               // -94 as unsigned
        size: 0,
        signed: true,
        type: .request,
        characteristic: .control,
        responseOpCode: 0xA3        // BolusPermissionResponse
    )

    public var cargo: [UInt8]

    public init() { self.cargo = [] }

    public mutating func parse(_ raw: [UInt8]) {
        let raw = removeSignedRequestHmacBytes(raw)
        precondition(raw.count == Self.props.size)
        self.cargo = raw
    }
}
