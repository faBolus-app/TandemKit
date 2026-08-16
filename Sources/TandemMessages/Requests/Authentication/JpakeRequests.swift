import Foundation

/// Modern (6-digit) JPAKE pairing wire messages on the AUTHORIZATION characteristic.
/// Ports of `request/authentication/Jpake{1a,1b,2,3SessionKey,4KeyConfirmation}Request`.
///
/// Rounds 1a/1b/2 carry EC-JPAKE round bytes (computed by `TandemAuth.JpakeAuth` via
/// mbedTLS); rounds 3/4 are the Tandem session-key + key-confirmation exchange. The cargo
/// framing is deterministic given its inputs and is verified byte-exact vs the oracle.

/// A JPAKE round message carrying `appInstanceId (2, LE) + challenge (165)`. Shared shape of
/// Jpake1a/1b/2.
public protocol JpakeChallengeMessage: Message {
    init(appInstanceId: Int, centralChallenge: [UInt8])
    var appInstanceId: Int { get }
    var centralChallenge: [UInt8] { get }
}

public struct Jpake1aRequest: JpakeChallengeMessage {
    public static let props = MessageProps(opCode: 32, size: 167, type: .request,
                                           characteristic: .authorization, responseOpCode: 33, minApi: .v3_2) // upstream API_V3_2 (D-08)
    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var centralChallenge: [UInt8] = []
    public init() { self.cargo = [] }
    public init(appInstanceId: Int, centralChallenge: [UInt8]) {
        self.cargo = jpakeChallengeCargo(appInstanceId, centralChallenge, size: 167)
        self.appInstanceId = appInstanceId; self.centralChallenge = centralChallenge
    }
    public mutating func parse(_ raw: [UInt8]) {
        cargo = raw; appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0); centralChallenge = Array(raw[2...])
    }
}

public struct Jpake1bRequest: JpakeChallengeMessage {
    public static let props = MessageProps(opCode: 34, size: 167, type: .request,
                                           characteristic: .authorization, responseOpCode: 35, minApi: .v3_2) // upstream API_V3_2 (D-08)
    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var centralChallenge: [UInt8] = []
    public init() { self.cargo = [] }
    public init(appInstanceId: Int, centralChallenge: [UInt8]) {
        self.cargo = jpakeChallengeCargo(appInstanceId, centralChallenge, size: 167)
        self.appInstanceId = appInstanceId; self.centralChallenge = centralChallenge
    }
    public mutating func parse(_ raw: [UInt8]) {
        cargo = raw; appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0); centralChallenge = Array(raw[2...])
    }
}

public struct Jpake2Request: JpakeChallengeMessage {
    public static let props = MessageProps(opCode: 36, size: 167, type: .request,
                                           characteristic: .authorization, responseOpCode: 37, minApi: .v3_2) // upstream API_V3_2 (D-08)
    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var centralChallenge: [UInt8] = []
    public init() { self.cargo = [] }
    public init(appInstanceId: Int, centralChallenge: [UInt8]) {
        self.cargo = jpakeChallengeCargo(appInstanceId, centralChallenge, size: 167)
        self.appInstanceId = appInstanceId; self.centralChallenge = centralChallenge
    }
    public mutating func parse(_ raw: [UInt8]) {
        cargo = raw; appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0); centralChallenge = Array(raw[2...])
    }
}

/// Round 3: 2-byte session-key challenge parameter.
public struct Jpake3SessionKeyRequest: Message {
    public static let props = MessageProps(opCode: 38, size: 2, type: .request,
                                           characteristic: .authorization, responseOpCode: 39, minApi: .v3_2) // upstream API_V3_2 (D-08)
    public var cargo: [UInt8]
    public private(set) var challengeParam: Int = 0
    public init() { self.cargo = [] }
    public init(challengeParam: Int) {
        self.cargo = Bytes.firstTwoBytesLittleEndian(challengeParam)
        self.challengeParam = challengeParam
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = raw; challengeParam = Bytes.readShort(raw, 0) }
}

/// Round 4: key confirmation. `appInstanceId (2) + nonce (8) + reserved (8) + hashDigest (32)`.
public struct Jpake4KeyConfirmationRequest: Message {
    public static let props = MessageProps(opCode: 40, size: 50, type: .request,
                                           characteristic: .authorization, responseOpCode: 41, minApi: .v3_2) // upstream API_V3_2 (D-08)
    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    public private(set) var nonce: [UInt8] = []
    public private(set) var reserved: [UInt8] = []
    public private(set) var hashDigest: [UInt8] = []
    public init() { self.cargo = [] }
    public init(appInstanceId: Int, nonce: [UInt8], reserved: [UInt8], hashDigest: [UInt8]) {
        precondition(nonce.count == 8 && reserved.count == 8 && hashDigest.count == 32)
        var cargo = [UInt8](repeating: 0, count: 50)
        let combined = Bytes.combine(Bytes.firstTwoBytesLittleEndian(appInstanceId), nonce, reserved, hashDigest)
        for i in 0..<50 { cargo[i] = combined[i] }
        self.cargo = cargo
        self.appInstanceId = appInstanceId; self.nonce = nonce
        self.reserved = reserved; self.hashDigest = hashDigest
    }
    public mutating func parse(_ raw: [UInt8]) {
        cargo = raw
        appInstanceId = Bytes.readShort(Array(raw[0..<2]), 0)
        nonce = Array(raw[2..<10]); reserved = Array(raw[10..<18]); hashDigest = Array(raw[18..<50])
    }
}

/// Builds `appInstanceId (2, LE) + challenge`, truncated/zero-padded to `size`.
private func jpakeChallengeCargo(_ appInstanceId: Int, _ challenge: [UInt8], size: Int) -> [UInt8] {
    var cargo = [UInt8](repeating: 0, count: size)
    let combined = Bytes.combine(Bytes.firstTwoBytesLittleEndian(appInstanceId), challenge)
    for i in 0..<min(size, combined.count) { cargo[i] = combined[i] }
    return cargo
}
