import Foundation

/// Returns the major/minor API version of the pump. Empty cargo.
/// Port of `request/currentStatus/ApiVersionRequest` (opcode 32).
public struct ApiVersionRequest: Message {
    public static let props = MessageProps(
        opCode: 32,
        size: 2,                    // or 0
        variableSize: true,
        type: .request,
        characteristic: .currentStatus,
        responseOpCode: 33          // ApiVersionResponse
    )

    public var cargo: [UInt8]

    public init() { self.cargo = [] }
    public init(cargo: [UInt8]) { self.cargo = cargo }

    public mutating func parse(_ raw: [UInt8]) {
        // empty cargo is ok
        if raw.isEmpty { return }
        precondition(raw.count == Self.props.size, "got length \(raw.count)")
        self.cargo = Bytes.dropFirst(raw, 3)
    }
}
