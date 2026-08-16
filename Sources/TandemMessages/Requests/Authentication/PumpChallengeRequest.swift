import Foundation

/// Second legacy authorization message, carrying the HMAC-SHA1 of the pairing code over the
/// pump-supplied HMAC key. Port of `request/authentication/PumpChallengeRequest`
/// (opcode 18, size 22).
public struct PumpChallengeRequest: Message {
    public static let props = MessageProps(
        opCode: 18,
        size: 22,
        type: .request,
        characteristic: .authorization,
        responseOpCode: 19          // PumpChallengeResponse
    )

    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var pumpChallengeHash: [UInt8] = []

    public init() { self.cargo = [] }

    /// `pumpChallengeHash` is the 20-byte HMAC-SHA1 result (see `PairingAuth.createV1`).
    public init(appInstanceId: Int, pumpChallengeHash: [UInt8]) {
        self.cargo = Self.buildCargo(appInstanceId: appInstanceId, pumpChallengeHash: pumpChallengeHash)
        self.appInstanceId = appInstanceId
        self.pumpChallengeHash = pumpChallengeHash
    }

    public mutating func parse(_ raw: [UInt8]) {
        self.cargo = raw
        self.appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0)
        self.pumpChallengeHash = Array(raw[2...])
    }

    /// 22 bytes: appInstanceId (2, LE) + first 20 of pumpChallengeHash.
    public static func buildCargo(appInstanceId: Int, pumpChallengeHash: [UInt8]) -> [UInt8] {
        var cargo = [UInt8](repeating: 0, count: 22)
        let combined = Bytes.combine(Bytes.firstTwoBytesLittleEndian(appInstanceId), pumpChallengeHash)
        for i in 0..<22 { cargo[i] = combined[i] }
        return cargo
    }
}
