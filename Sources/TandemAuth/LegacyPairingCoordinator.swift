import Foundation
import TandemMessages

/// The shared surface of a client-initiated pump pairing handshake, so callers (`LiveSession`, the
/// app connect path) can drive JPAKE (6-digit) and legacy V1 (16-char) pairing UNIFORMLY. Both
/// `PairingCoordinator` (JPAKE) and `LegacyPairingCoordinator` (V1) conform.
///
/// The two differ in exactly one place a caller must branch on: RESUME. JPAKE supports a quick-pair
/// resume (rounds 3–4 from a stored derived secret); V1 has no resume — a reconnect constructs a
/// fresh `LegacyPairingCoordinator` and re-runs the full challenge (silent, since the app already
/// holds the code). That asymmetry stays an explicit type decision at construction; everything after
/// (`onSendRequest` / `handle(frame:)` / `onPaired` / `onError`) is uniform through this protocol.
public protocol PairingCoordinating: AnyObject {
    /// Transport hook: send a pairing request to the pump (AUTHORIZATION characteristic).
    var onSendRequest: ((Message) -> Void)? { get set }
    /// Called once when pairing succeeds, with the per-command signing key (+ a server nonce, which
    /// is empty for V1 — it has no resume secret).
    var onPaired: ((_ authKey: [UInt8], _ serverNonce: [UInt8]) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }
    /// Begins the handshake (emits the first request via `onSendRequest`).
    func start()
    /// Feed a reassembled inbound frame `[opcode, txId, len, cargo…, crc0, crc1]` from AUTHORIZATION.
    func handle(frame: [UInt8])
}

extension PairingCoordinator: PairingCoordinating {}

/// Drives the LEGACY (V1 / 16-char pairing code) authorization handshake over a message transport,
/// client-initiated — the pre-firmware-v7.7 t:slim X2 scheme. Same public shape as
/// `PairingCoordinator`, so callers treat the two uniformly (see `PairingCoordinating`).
///
/// The two-message exchange (oracle-confirmed):
/// ```
/// client → CentralChallengeRequest  (op 16)   appInstanceId + centralChallenge(8 random)
/// pump   → CentralChallengeResponse (op 17)   appInstanceId + centralChallengeHash(20) + hmacKey(8)
/// client → PumpChallengeRequest      (op 18)   appInstanceId + pumpChallengeHash(20)
/// pump   → PumpChallengeResponse      (op 19)   appInstanceId + success(1)
/// ```
/// `pumpChallengeHash = HMAC-SHA1(data = hmacKey, key = pairingCode UTF-8)` (see
/// `PairingAuth.createV1`). The signing key for all subsequent signed requests is the processed
/// 16-char pairing code's UTF-8 bytes — NOT a derived secret (JPAKE derives via HKDF; V1 does not;
/// confirmed in the oracle `PumpStateSupplier`).
///
/// `appInstanceId` on op18 is the value op17's `CentralChallengeResponse` ECHOES back (the reference's
/// `PumpChallengeRequestBuilder.createV1()`: `int appInstanceId = challengeResponse.getAppInstanceId();`)
/// — NOT the app's own op16 value. This coordinator's own op16 `appInstanceId` (constructor param,
/// default 0) is unrelated and unchanged by this: it is this app's OWN identifier, sent once as the
/// initial challenge; JPAKE, by contrast, hardcodes a literal 0 for every request in the reference
/// (`JpakeAuthBuilder.java`) and never reads/echoes anything back — `PairingCoordinator`'s matching
/// static-0 behavior for every JPAKE round is therefore already reference-correct and must NOT be
/// changed to mirror this.
///
/// Pairing traffic is operation-risk `.read` and never touches either delivery software wall.
public final class LegacyPairingCoordinator: PairingCoordinating {
    public enum Step: Equatable, Sendable { case idle, sentCentral, sentPump, paired, failed }
    public enum PairingError: Error, Equatable {
        case unexpectedResponse(opcode: UInt8)
        case malformedResponse
        /// The pump returned `success == false` — the entered pairing code was rejected.
        case pairingRejected
    }

    private let appInstanceId: Int
    /// The validated 16-char canonical form (its UTF-8 bytes ARE the signing key).
    private let processedPairingCode: String
    private let centralChallenge: [UInt8]
    public private(set) var step: Step = .idle

    public var onSendRequest: ((Message) -> Void)?
    public var onPaired: ((_ authKey: [UInt8], _ serverNonce: [UInt8]) -> Void)?
    public var onError: ((Error) -> Void)?

    /// The V1 signing key: the processed pairing code's UTF-8 bytes (not a derived secret). Valid
    /// once pairing succeeds; the same value the pump uses to verify signed requests.
    public var authKey: [UInt8] { Array(processedPairingCode.utf8) }

    /// Full V1 pairing with a 16-char code. `centralChallenge` defaults to 8 random bytes; passing
    /// an explicit value is a test/repro seam only. Throws if `pairingCode` is not a valid 16-char
    /// (alphanumeric) code.
    public init(pairingCode: String, appInstanceId: Int = 0, centralChallenge: [UInt8]? = nil) throws {
        self.processedPairingCode = try PairingAuth.processPairingCode(pairingCode, type: .long16Char)
        self.appInstanceId = appInstanceId
        self.centralChallenge = centralChallenge ?? (0..<8).map { _ in UInt8.random(in: .min ... .max) }
    }

    /// Begins the handshake: emits `CentralChallengeRequest` (op 16). A reconnect just builds a fresh
    /// instance and calls `start()` again — V1 has no resume state.
    public func start() {
        step = .sentCentral
        onSendRequest?(CentralChallengeRequest(appInstanceId: appInstanceId, centralChallenge: centralChallenge))
    }

    public func handle(frame: [UInt8]) {
        guard frame.count >= 5 else { return fail(PairingError.malformedResponse) }
        let opcode = frame[0]
        let cargo = Self.frameCargo(frame)
        switch (step, opcode) {
        case (.sentCentral, 17):   // CentralChallengeResponse
            let resp = CentralChallengeResponse(cargo: cargo)
            guard resp.isValid else { return fail(PairingError.malformedResponse) }
            do {
                // createV1: pumpChallengeHash = HMAC-SHA1(data = hmacKey, key = pairingCode UTF-8).
                // appInstanceId: echo back the PUMP-ASSIGNED value from CentralChallengeResponse, not
                // this coordinator's own (op16) value — matches the vendored jwoglom/pumpX2 reference's
                // `PumpChallengeRequestBuilder.createV1()` exactly: `int appInstanceId =
                // challengeResponse.getAppInstanceId();`. Every prior version of this coordinator built
                // PumpChallengeRequest with `appInstanceId` (the coordinator's own op16 value, default 0)
                // instead, silently ignoring `resp.appInstanceId` — a real, reference-confirmed
                // divergence, though on-device evidence (`.planning/debug/pump-pairing-loop.md`, capture
                // #4) shows it is NOT what causes the post-pair read-drop loop: appInstanceId appears
                // nowhere in the wire format of any non-pairing (CURRENT_STATUS/CONTROL) message or in
                // Packetize's packet header, so a wrong value here cannot mis-route a later read; and the
                // coordinator sent the SAME (wrong) constant on every capture, yet the drop's presence
                // varied cycle-to-cycle, which a constant input cannot explain. Fixed anyway as a genuine
                // protocol-parity correctness issue, independent of the loop.
                let pumpChallenge = try PairingAuth.createV1(
                    appInstanceId: resp.appInstanceId, hmacKey: resp.hmacKey, pairingCode: processedPairingCode)
                step = .sentPump
                onSendRequest?(pumpChallenge)
            } catch { fail(error) }
        case (.sentPump, 19):      // PumpChallengeResponse
            let resp = PumpChallengeResponse(cargo: cargo)
            if resp.success {
                step = .paired
                onPaired?(authKey, [])   // no resume secret in V1
            } else {
                fail(PairingError.pairingRejected)
            }
        default:
            fail(PairingError.unexpectedResponse(opcode: opcode))
        }
    }

    private func fail(_ error: Error) { step = .failed; onError?(error) }

    /// Extract cargo `[3 ..< 3+len]` from a `[opcode, txId, len, cargo…, crc0, crc1]` frame,
    /// mirroring `PairingCoordinator.frameCargo` (the coordinator parses AUTHORIZATION frames
    /// inline; the BLE layer already validated the CRC).
    private static func frameCargo(_ frame: [UInt8]) -> [UInt8] {
        let len = Int(frame[2])
        let end = min(3 + len, frame.count - 2)   // exclude the 2-byte CRC
        guard end >= 3 else { return [] }
        return Array(frame[3..<end])
    }
}
