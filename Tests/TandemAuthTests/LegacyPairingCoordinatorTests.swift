import Testing
import TandemMessages
@testable import TandemAuth

/// Unit tests for the legacy (V1 / 16-char) pairing coordinator, mirroring `PairingCoordinatorTests`
/// (a mock pump driven synchronously via `onSendRequest`, no BLE). Proves the 2-step
/// CentralChallenge→PumpChallenge exchange, the HMAC-SHA1 argument order, the pairing-code-as-signing-
/// key rule, fail-closed rejection, and the no-resume (full re-challenge) behavior.
@Suite struct LegacyPairingCoordinatorTests {
    private func frame(_ opcode: UInt8, _ cargo: [UInt8]) -> [UInt8] {
        [opcode, 0, UInt8(cargo.count)] + cargo + [0, 0]   // [opcode, txId, len, cargo…, crc(2 dummy)]
    }
    private func withAppId(_ payload: [UInt8]) -> [UInt8] { [0, 0] + payload }  // appInstanceId = 0

    private let code = "abcd1234ijkl5678"                                       // valid 16-char code
    private let hmacKey: [UInt8] = [0x84, 0x0c, 0x4e, 0x16, 0x87, 0x30, 0x46, 0xbc]
    private let challengeHash = [UInt8](repeating: 0xAB, count: 20)             // pump's hash (client ignores)

    @Test func pairsWithMockPump() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code)
        var sentCentral = false
        var pumpChallengeSent: [UInt8]?
        var pairedKey: [UInt8]?
        coord.onError = { Issue.record("pairing error: \($0)") }
        coord.onPaired = { key, nonce in pairedKey = key; #expect(nonce.isEmpty) }  // V1 has no resume secret
        coord.onSendRequest = { msg in
            switch msg {
            case let m as CentralChallengeRequest:
                sentCentral = true
                #expect(m.centralChallenge.count == 8)
                // pump replies op-17 with the hmacKey (+ an arbitrary challenge hash the client ignores).
                coord.handle(frame: self.frame(17, self.withAppId(self.challengeHash + self.hmacKey)))
            case let m as PumpChallengeRequest:
                pumpChallengeSent = m.pumpChallengeHash
                // The pump verifies exactly as createV1 computes: HMAC-SHA1(data = hmacKey, key = code).
                #expect(m.pumpChallengeHash == Crypto.hmacSha1(data: self.hmacKey, key: Array(self.code.utf8)))
                coord.handle(frame: self.frame(19, self.withAppId([1])))   // success
            default:
                Issue.record("unexpected request: \(type(of: msg))")
            }
        }
        coord.start()
        #expect(sentCentral)
        #expect(coord.step == .paired)
        #expect(pumpChallengeSent?.count == 20)
        // The V1 signing key IS the pairing code's UTF-8 bytes (not a derived secret).
        #expect(pairedKey == Array(code.utf8))
        #expect(coord.authKey == Array(code.utf8))
    }

    /// `PumpChallengeRequest` (op18) must carry the pump-assigned `appInstanceId` echoed in
    /// `CentralChallengeResponse` (op17), not this coordinator's own op16 value — even when the two differ.
    @Test func pumpChallengeRequestEchoesThePumpAssignedAppInstanceId() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code)   // op16 appInstanceId defaults to 0
        let pumpAssignedId = 517                                      // nonzero, deliberately != 0
        var pumpChallengeAppInstanceId: Int?
        coord.onError = { Issue.record("pairing error: \($0)") }
        coord.onSendRequest = { msg in
            switch msg {
            case is CentralChallengeRequest:
                let respPayload = self.challengeHash + self.hmacKey
                // appInstanceId(2, LE) + payload — matches CentralChallengeResponse's cargo layout.
                let cargo = Bytes.firstTwoBytesLittleEndian(pumpAssignedId) + respPayload
                coord.handle(frame: self.frame(17, cargo))
            case let m as PumpChallengeRequest:
                pumpChallengeAppInstanceId = m.appInstanceId
                coord.handle(frame: self.frame(19, self.withAppId([1])))
            default:
                Issue.record("unexpected request: \(type(of: msg))")
            }
        }
        coord.start()
        #expect(coord.step == .paired)
        #expect(pumpChallengeAppInstanceId == pumpAssignedId)          // echoed, not op16's default 0
    }

    @Test func rejectsWrongPairingCode() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code)
        var failure: Error?
        coord.onPaired = { _, _ in Issue.record("must not pair when the pump rejects the code") }
        coord.onError = { failure = $0 }
        coord.onSendRequest = { msg in
            switch msg {
            case is CentralChallengeRequest:
                coord.handle(frame: self.frame(17, self.withAppId(self.challengeHash + self.hmacKey)))
            case is PumpChallengeRequest:
                coord.handle(frame: self.frame(19, self.withAppId([0])))   // success = false
            default: Issue.record("unexpected request: \(type(of: msg))")
            }
        }
        coord.start()
        #expect(coord.step == .failed)
        #expect(failure as? LegacyPairingCoordinator.PairingError == .pairingRejected)
    }

    @Test func malformedCentralResponseFailsClosed() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code)
        var failure: Error?
        coord.onPaired = { _, _ in Issue.record("must not pair on a malformed challenge") }
        coord.onError = { failure = $0 }
        coord.onSendRequest = { msg in
            if msg is CentralChallengeRequest { coord.handle(frame: self.frame(17, self.withAppId([1, 2, 3]))) }
        }
        coord.start()
        #expect(coord.step == .failed)
        #expect(failure as? LegacyPairingCoordinator.PairingError == .malformedResponse)
    }

    @Test func unexpectedOpcodeFails() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code)
        var failure: Error?
        coord.onError = { failure = $0 }
        coord.onSendRequest = { msg in
            if msg is CentralChallengeRequest { coord.handle(frame: self.frame(19, self.withAppId([1]))) }  // wrong step
        }
        coord.start()
        #expect(coord.step == .failed)
        guard case .unexpectedResponse = (failure as? LegacyPairingCoordinator.PairingError) else {
            Issue.record("expected .unexpectedResponse, got \(String(describing: failure))")
            return
        }
    }

    @Test func invalidCodeThrows() {
        #expect(throws: PairingAuth.PairingError.self) {
            _ = try LegacyPairingCoordinator(pairingCode: "123456")     // a 6-digit is not a 16-char code
        }
    }

    /// V1 has NO quick-pair resume: a reconnect re-runs the FULL challenge. A fresh coordinator's
    /// `start()` emits a `CentralChallengeRequest` (never a resume message).
    @Test func reconnectRerunsFullChallenge() throws {
        let coord = try LegacyPairingCoordinator(pairingCode: code, centralChallenge: [UInt8](repeating: 9, count: 8))
        var firstRequestType: String?
        coord.onSendRequest = { msg in if firstRequestType == nil { firstRequestType = String(describing: type(of: msg)) } }
        coord.start()
        #expect(firstRequestType == "CentralChallengeRequest")
    }
}

/// Code-type detection drives which coordinator (JPAKE vs legacy V1) a caller builds.
@Suite struct PairingCodeDetectionTests {
    @Test func detectsShortAndLong() {
        #expect(PairingAuth.detectType("123456") == .short6Char)
        #expect(PairingAuth.detectType("123-456") == .short6Char)
        #expect(PairingAuth.detectType("abcd1234ijkl5678") == .long16Char)
        #expect(PairingAuth.detectType("abcd-efgh-ijkl-mnop") == .long16Char)
        #expect(PairingAuth.detectType("abcd-1234-ijkl-5678") == .long16Char)
    }

    /// The safety-hardened case: a 16-char alphanumeric code with exactly 6 digits must still be
    /// `.long16Char` — the upstream "6 digits present" heuristic would misroute it to JPAKE.
    @Test func sixDigitsInsideSixteenCharCodeIsLong() {
        #expect(PairingAuth.detectType("ab12cd34ef56ghij") == .long16Char)
    }
}
