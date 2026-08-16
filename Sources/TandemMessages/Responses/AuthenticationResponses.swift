import Foundation

/// Inbound pairing responses for the legacy (V1 / 16-char) authorization handshake, on the
/// AUTHORIZATION characteristic. Ports of `response/authentication/{CentralChallengeResponse,
/// PumpChallengeResponse}`.
///
/// These are the pump replies for the pre-firmware-v7.7 t:slim X2 pairing scheme (a 16-char
/// pairing code + HMAC-SHA1 challenge/response). The modern (v7.7+) 6-digit EC-JPAKE pairing
/// uses different opcodes (33/35/37/39/41), which `PairingCoordinator` parses inline; these two
/// are registered in `ResponseParser` for byte-exact oracle parity and reuse, and are also read
/// by `LegacyPairingCoordinator`.
///
/// Both are operation-risk `.read` (pairing traffic never modifies pump state), so they pass the
/// `.readOnly` write interlock unchanged — no delivery wall is involved in pairing.

/// `CentralChallengeResponse` (opcode 17, size 30). The pump's reply to `CentralChallengeRequest`:
/// it carries the `hmacKey` the client feeds into `PairingAuth.createV1` to compute the
/// `PumpChallengeRequest`.
///
/// Cargo layout (matches the oracle `parse()`):
///   `appInstanceId` (2, LE) + `centralChallengeHash` (20) + `hmacKey` (8) = 30 bytes.
public struct CentralChallengeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 17, size: 30, type: .response,
                                           characteristic: .authorization)
    public var cargo: [UInt8]
    /// App-chosen id the pump echoes back (0 on a fresh pair).
    public private(set) var appInstanceId: Int = 0
    /// The pump's HMAC of our central challenge (20 bytes). Not used client-side in the reference
    /// flow — the client authenticates via `hmacKey` below (kept for parity + inspection).
    public private(set) var centralChallengeHash: [UInt8] = []
    /// The 8-byte key over which the client computes `PumpChallengeRequest` (HMAC-SHA1 with the
    /// pairing code as the HMAC key — see `PairingAuth.createV1`).
    public private(set) var hmacKey: [UInt8] = []

    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        // Tolerant parse: never trap on a short/oversized frame (a malformed reply must surface as
        // an unusable response, not a crash). A valid frame is exactly 30 bytes.
        if raw.count >= 30 {
            appInstanceId = Bytes.readShort(raw, 0)
            centralChallengeHash = Array(raw[2..<22])   // len 20 (raw[2..22])
            hmacKey = Array(raw[22..<30])               // len 8  (raw[22..30])
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = CentralChallengeResponse(cargo: raw) }

    /// True when the pump returned a usable challenge (well-formed hash + hmacKey).
    public var isValid: Bool { centralChallengeHash.count == 20 && hmacKey.count == 8 }
}

/// `PumpChallengeResponse` (opcode 19, size 3), aka AuthenticationStatusResponse. The final legacy
/// pairing reply: `success == true` means the pump accepted the pairing code.
///
/// Cargo layout: `appInstanceId` (2, LE) + `success` (1: `raw[2] == 1`) = 3 bytes.
public struct PumpChallengeResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 19, size: 3, type: .response,
                                           characteristic: .authorization)
    public var cargo: [UInt8]
    public private(set) var appInstanceId: Int = 0
    /// Pairing accepted. A malformed/short reply parses as `false` (fail-closed — never assume a
    /// pairing succeeded from a frame we could not read).
    public private(set) var success: Bool = false

    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 3 {
            appInstanceId = Bytes.readShort(raw, 0)
            success = raw[2] == 1
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = PumpChallengeResponse(cargo: raw) }
}
