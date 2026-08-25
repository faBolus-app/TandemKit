import Foundation
import TandemMessages

/// Drives the modern (6-digit) JPAKE pairing handshake over a message transport, **client-
/// initiated** — the real pump flow (client sends a request, pump replies). Feed it inbound
/// response frames; it emits the next request via `onSendRequest` and calls `onPaired` with
/// the derived signing key when the handshake completes.
///
/// The underlying crypto (`JpakeAuth` / mbedTLS) is validated byte-compatible with the
/// reference in `JpakeInteropTests`; this coordinator adds the client-initiated sequencing and
/// is unit-tested in-process against a mock pump.
public final class PairingCoordinator {
    public enum Step: Equatable, Sendable { case idle, sent1a, sent1b, sent2, sent3, sent4, paired, failed }
    public enum PairingError: Error, Equatable { case unexpectedResponse(opcode: UInt8), keyConfirmationFailed, malformedFrame }

    private let auth: JpakeAuth
    private let isResume: Bool
    public private(set) var step: Step = .idle

    /// Transport hook: send a pairing request to the pump (AUTHORIZATION characteristic).
    public var onSendRequest: ((Message) -> Void)?
    /// Called once when pairing succeeds, with the per-command signing key + server nonce.
    public var onPaired: ((_ authKey: [UInt8], _ serverNonce: [UInt8]) -> Void)?
    public var onError: ((Error) -> Void)?

    private var pumpRound1a: [UInt8] = []
    private var r1b: Jpake1bRequest?

    /// The derived secret to persist after a full pairing, enabling later resume.
    public var derivedSecret: [UInt8] { auth.derivedSecret }

    /// Full pairing with the 6-digit code.
    public init(pairingCode: String, appInstanceId: Int = 0) throws {
        self.auth = try JpakeAuth(pairingCode: pairingCode, appInstanceId: appInstanceId)
        self.isResume = false
    }

    /// Resume ("quick-pair") using a stored derived secret — no 6-digit code, rounds 3–4 only.
    public init(resumeDerivedSecret: [UInt8], appInstanceId: Int = 0) {
        self.auth = JpakeAuth(resumeDerivedSecret: resumeDerivedSecret, appInstanceId: appInstanceId)
        self.isResume = true
    }

    /// Begins the handshake: full pairing sends Jpake1a; resume jumps straight to round 3.
    public func start() {
        do {
            if isResume {
                step = .sent3
                onSendRequest?(auth.makeRound3Request())
            } else {
                let (a, b) = try auth.makeRound1Requests()
                r1b = b
                step = .sent1a
                onSendRequest?(a)
            }
        } catch { fail(error) }
    }

    /// Feed a reassembled inbound frame `[opcode, txId, len, cargo…, crc0, crc1]`.
    public func handle(frame: [UInt8]) {
        guard frame.count >= 5 else { return fail(PairingError.malformedFrame) }
        // CX-T-08: mirror ResponseParser's CRC-then-length idiom (reusing the same
        // Bytes.calculateCRC16 — never a second CRC implementation in an auth-critical path).
        // A malformed pairing frame must fail(.malformedFrame) and never advance the JPAKE
        // state machine or reach frameCargo's clamp.
        let body = Array(frame[0..<(frame.count - 2)])
        let trailingCRC = Array(frame[(frame.count - 2)...])
        guard Bytes.calculateCRC16(body) == trailingCRC else { return fail(PairingError.malformedFrame) }
        guard 3 + Int(frame[2]) == frame.count - 2 else { return fail(PairingError.malformedFrame) }
        let opcode = frame[0]
        let cargo = frameCargo(frame)
        let challenge = Array(cargo.dropFirst(2))   // cargo = appInstanceId(2) + payload
        do {
            switch (step, opcode) {
            case (.sent1a, 33):   // Jpake1aResponse
                pumpRound1a = challenge
                step = .sent1b
                onSendRequest?(r1b!)
            case (.sent1b, 35):   // Jpake1bResponse
                try auth.readServerRound1(challenge1a: pumpRound1a, challenge1b: challenge)
                step = .sent2
                onSendRequest?(try auth.makeRound2Request())
            case (.sent2, 37):    // Jpake2Response
                try auth.readServerRound2(challenge: challenge)
                _ = try auth.derive()
                step = .sent3
                onSendRequest?(Jpake3SessionKeyRequest(challengeParam: 0))
            case (.sent3, 39):    // Jpake3SessionKeyResponse: payload = nonce(8) + reserved(8)
                let serverNonce3 = Array(challenge.prefix(8))
                step = .sent4
                onSendRequest?(auth.makeRound4Request(serverNonce3: serverNonce3))
            case (.sent4, 41):    // Jpake4KeyConfirmationResponse: nonce(8)+reserved(8)+hash(32)
                let serverNonce4 = Array(challenge.prefix(8))
                let serverHash = Array(challenge.dropFirst(16).prefix(32))
                try auth.verifyServerRound4(serverNonce4: serverNonce4, serverHashDigest: serverHash)
                step = .paired
                onPaired?(auth.authKey, auth.serverNonce)
            default:
                fail(PairingError.unexpectedResponse(opcode: opcode))
            }
        } catch { fail(error) }
    }

    public var authKey: [UInt8] { auth.authKey }

    private func fail(_ error: Error) { step = .failed; onError?(error) }

    private func frameCargo(_ frame: [UInt8]) -> [UInt8] {
        let len = Int(frame[2])
        let end = min(3 + len, frame.count - 2)   // exclude the 2-byte CRC
        guard end >= 3 else { return [] }
        return Array(frame[3..<end])
    }
}
