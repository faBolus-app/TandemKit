import Foundation

/// First message on connection, beginning the legacy (16-char pairing) authorization.
/// The response carries the HMAC key used to compute `PumpChallengeRequest`.
/// Port of `request/authentication/CentralChallengeRequest` (opcode 16, size 10).
public struct CentralChallengeRequest: Message {
    public static let props = MessageProps(
        opCode: 16,
        size: 10,
        type: .request,
        characteristic: .authorization,
        responseOpCode: 17          // CentralChallengeResponse
    )

    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var centralChallenge: [UInt8] = []

    public init() { self.cargo = [] }

    /// `centralChallenge` is 8 random bytes.
    public init(appInstanceId: Int, centralChallenge: [UInt8]) {
        self.cargo = Self.buildCargo(appInstanceId: appInstanceId, centralChallenge: centralChallenge)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge
    }

    public mutating func parse(_ raw: [UInt8]) {
        self.cargo = raw
        self.appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0)
        self.centralChallenge = Array(raw[2...])
    }

    /// 10 bytes: appInstanceId (2, LE) + first 8 of centralChallenge.
    public static func buildCargo(appInstanceId: Int, centralChallenge: [UInt8]) -> [UInt8] {
        var cargo = [UInt8](repeating: 0, count: 10)
        let combined = Bytes.combine(Bytes.firstTwoBytesLittleEndian(appInstanceId), centralChallenge)
        for i in 0..<10 { cargo[i] = combined[i] }
        return cargo
    }
}
