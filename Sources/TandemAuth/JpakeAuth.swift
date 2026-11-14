import Foundation
import TandemMessages
import CMbedTLSJPAKE

/// Low-level EC-JPAKE context (secp256r1/SHA-256) backed by vendored mbedTLS. Client role in
/// production; the server role exists only for the in-process self-test.
public final class EcJpakeContext {
    public enum Role { case client, server }
    public enum JpakeError: Error { case setupFailed, roundFailed(Int32) }

    private let ctx: OpaquePointer
    /// Kept alive for the C callback while a seeded test context exists; nil in production. Never read:
    /// holding it is the point.
    // periphery:ignore
    private var randomSource: RandomSource?

    public init(role: Role, secret: [UInt8]) throws {
        let made: OpaquePointer? = secret.withUnsafeBufferPointer { buf in
            switch role {
            case .client: return cjpake_new_client(buf.baseAddress, buf.count)
            case .server: return cjpake_new_server(buf.baseAddress, buf.count)
            }
        }
        guard let made else { throw JpakeError.setupFailed }
        self.ctx = made
    }

    /// A context whose randomness comes from `randomBytes` instead of the OS CSPRNG, so a test can
    /// reproduce a particular round (for example one with a short ZKP scalar). Tests only.
    convenience init(role: Role, secret: [UInt8], randomBytes: @escaping (Int) -> [UInt8]) throws {
        try self.init(role: role, secret: secret)
        let source = RandomSource(randomBytes)
        randomSource = source
        cjpake_set_rng(
            ctx,
            { p, out, len in
                guard let p, let out else { return -1 }
                let bytes = Unmanaged<RandomSource>.fromOpaque(p).takeUnretainedValue().next(len)
                guard bytes.count == len else { return -1 }
                for i in 0..<len { out[i] = bytes[i] }
                return 0
            },
            Unmanaged.passUnretained(source).toOpaque())
    }

    deinit { cjpake_free(ctx) }

    private final class RandomSource {
        let next: (Int) -> [UInt8]
        init(_ next: @escaping (Int) -> [UInt8]) { self.next = next }
    }

    private func write(_ fn: (OpaquePointer, UnsafeMutablePointer<UInt8>, Int, UnsafeMutablePointer<Int>) -> Int32)
        throws -> [UInt8]
    {
        var out = [UInt8](repeating: 0, count: 1024)
        var olen = 0
        let rc = out.withUnsafeMutableBufferPointer { b in fn(ctx, b.baseAddress!, b.count, &olen) }
        guard rc == 0 else { throw JpakeError.roundFailed(rc) }
        return Array(out.prefix(olen))
    }

    private func read(_ bytes: [UInt8], _ fn: (OpaquePointer, UnsafePointer<UInt8>, Int) -> Int32) throws {
        let rc = bytes.withUnsafeBufferPointer { b in fn(ctx, b.baseAddress!, b.count) }
        guard rc == 0 else { throw JpakeError.roundFailed(rc) }
    }

    public func writeRoundOne() throws -> [UInt8] { try write(cjpake_write_round_one) }
    public func readRoundOne(_ b: [UInt8]) throws { try read(b, cjpake_read_round_one) }
    public func writeRoundTwo() throws -> [UInt8] { try write(cjpake_write_round_two) }
    public func readRoundTwo(_ b: [UInt8]) throws { try read(b, cjpake_read_round_two) }
    public func deriveSecret() throws -> [UInt8] { try write(cjpake_derive_secret) }
}

/// Modern (6-digit) JPAKE pairing state machine (client side). Wraps EC-JPAKE rounds 1–2 +
/// derive (mbedTLS) and the Tandem session-key/key-confirmation rounds 3–4 (HKDF + HMAC-256).
///
/// Round one (330 bytes) is split into the 1a/1b halves the pump expects, one KeyKP each. Every
/// round we send has its ZKP scalars at full length, and every round we read is re-encoded the
/// same way first, so a short scalar on either side can't shift the halves (`JpakeRound`).
/// The final signing
/// key is `HKDF(serverNonce, derivedSecret)` — the same key `Packetize` uses to HMAC signed
/// (insulin-affecting) commands. Validated in-process (client↔server derive equal secrets);
/// interop with the pump's implementation is validated via the oracle `jpake-server` handshake
/// and, ultimately, on hardware.
public final class JpakeAuth {
    public enum JpakeAuthError: Error { case keyConfirmationFailed }

    /// nil in resume mode (rounds 1–2 are skipped; the derived secret is already known).
    private let ec: EcJpakeContext?
    public let appInstanceId: Int

    public private(set) var derivedSecret: [UInt8] = []
    public private(set) var serverNonce: [UInt8] = []
    /// Per-command signing key once pairing completes: `HKDF(serverNonce, derivedSecret)`.
    public private(set) var authKey: [UInt8] = []
    private var clientNonce4: [UInt8] = []

    /// Full pairing with the 6-digit code (runs EC-JPAKE rounds 1–2 + derive).
    public init(pairingCode: String, appInstanceId: Int = 0) throws {
        self.appInstanceId = appInstanceId
        self.ec = try EcJpakeContext(role: .client, secret: Self.pairingCodeToBytes(pairingCode))
    }

    /// Full pairing over a given context (a seeded one, in tests).
    init(context: EcJpakeContext, appInstanceId: Int = 0) {
        self.appInstanceId = appInstanceId
        self.ec = context
    }

    /// Resume ("quick-pair") using a derived secret from a prior full pairing — no code, no
    /// EC-JPAKE rounds 1–2. Only the session-key + key-confirmation rounds (3–4) run.
    public init(resumeDerivedSecret: [UInt8], appInstanceId: Int = 0) {
        self.appInstanceId = appInstanceId
        self.ec = nil
        self.derivedSecret = resumeDerivedSecret
    }

    /// The 6-digit code's ASCII bytes (matches upstream `pairingCodeToBytes`).
    public static func pairingCodeToBytes(_ code: String) -> [UInt8] {
        code.compactMap { $0.isNumber ? $0.asciiValue : nil }
    }

    // MARK: rounds 1–2 (full pairing only)

    /// Writes round one and splits it into the 1a/1b request messages, one KeyKP (165 bytes) each.
    /// Splitting at the byte midpoint instead would move a byte between the halves whenever the
    /// second scalar came out short.
    public func makeRound1Requests() throws -> (Jpake1aRequest, Jpake1bRequest) {
        let kps = try JpakeRound.roundOne(ec!.writeRoundOne())
        return (
            Jpake1aRequest(appInstanceId: appInstanceId, centralChallenge: kps[0].encoded),
            Jpake1bRequest(appInstanceId: appInstanceId, centralChallenge: kps[1].encoded)
        )
    }

    /// Feeds the pump's round one into the context. Each half is read on its own, so a half that
    /// arrives short, or zero-padded to the fixed cargo, still lines up.
    public func readServerRound1(challenge1a: [UInt8], challenge1b: [UInt8]) throws {
        let a = try JpakeRound.keyKPs(challenge1a, count: 1)[0]
        let b = try JpakeRound.keyKPs(challenge1b, count: 1)[0]
        try ec!.readRoundOne(a.encoded + b.encoded)
    }

    public func makeRound2Request() throws -> Jpake2Request {
        let round2 = try JpakeRound.normalizedRoundTwo(ec!.writeRoundTwo(), server: false)
        return Jpake2Request(appInstanceId: appInstanceId, centralChallenge: round2)
    }

    /// Round 3 request (session-key exchange) — the first message in a resume handshake.
    public func makeRound3Request() -> Jpake3SessionKeyRequest {
        Jpake3SessionKeyRequest(challengeParam: 0)
    }

    /// Feeds the pump's round two (ECParameters + one KeyKP) into the context, trimmed of any
    /// cargo padding and with its scalar at full length.
    public func readServerRound2(challenge: [UInt8]) throws {
        try ec!.readRoundTwo(JpakeRound.normalizedRoundTwo(challenge, server: true))
    }

    /// Derives the pre-master secret (must follow rounds 1 and 2).
    @discardableResult
    public func derive() throws -> [UInt8] {
        derivedSecret = try ec!.deriveSecret()
        return derivedSecret
    }

    // MARK: rounds 3–4 (Tandem key confirmation)

    /// Given the server's round-3 nonce, computes `authKey = HKDF(serverNonce, derivedSecret)`
    /// and returns the round-4 key-confirmation request.
    public func makeRound4Request(serverNonce3: [UInt8], randomNonce: [UInt8]? = nil) -> Jpake4KeyConfirmationRequest {
        self.serverNonce = serverNonce3
        self.authKey = Crypto.hkdf(nonce: serverNonce3, keyMaterial: derivedSecret)
        self.clientNonce4 = randomNonce ?? Self.randomBytes(8)
        let hashDigest = Crypto.hmacSha256(data: clientNonce4, key: authKey)
        return Jpake4KeyConfirmationRequest(
            appInstanceId: appInstanceId, nonce: clientNonce4,
            reserved: [UInt8](repeating: 0, count: 8), hashDigest: hashDigest)
    }

    /// Verifies the server's round-4 confirmation HMAC.
    ///
    /// Uses a constant-time comparison (`Crypto.isValidHmacSha256`, backed by CryptoKit's
    /// `HMAC<SHA256>.isValidAuthenticationCode`) rather than Array `==` — an elementwise compare
    /// short-circuits on the first mismatching byte, a timing side-channel on this auth-path HMAC.
    /// Matches upstream jwoglom/pumpX2 PR #102, which fixed the Java equivalent with the
    /// constant-time `MessageDigest.isEqual`.
    public func verifyServerRound4(serverNonce4: [UInt8], serverHashDigest: [UInt8]) throws {
        guard Crypto.isValidHmacSha256(mac: serverHashDigest, data: serverNonce4, key: authKey) else {
            throw JpakeAuthError.keyConfirmationFailed
        }
    }

    static func randomBytes(_ n: Int) -> [UInt8] {
        var g = SystemRandomNumberGenerator()
        return (0..<n).map { _ in UInt8.random(in: 0...255, using: &g) }
    }
}
