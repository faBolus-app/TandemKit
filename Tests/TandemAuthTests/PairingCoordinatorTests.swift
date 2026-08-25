import Testing
import TandemMessages
@testable import TandemAuth

@Suite struct PairingCoordinatorTests {
    /// Build an inbound frame [opcode, txId, len, cargo…, crc(2)]. CX-T-08: `handle(frame:)` now
    /// validates the CRC + declared length itself (mirroring ResponseParser), so this helper must
    /// emit a REAL `Bytes.calculateCRC16` trailer — a dummy `[0, 0]` CRC would now fail closed.
    private func frame(_ opcode: UInt8, _ cargo: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [opcode, 0, UInt8(cargo.count)] + cargo
        return body + Bytes.calculateCRC16(body)
    }
    private func withAppId(_ payload: [UInt8]) -> [UInt8] { [0, 0] + payload }  // appInstanceId=0

    /// The client-initiated pairing coordinator completes a full handshake against a mock pump
    /// (server-role EC-JPAKE) and derives a signing key matching the pump's.
    @Test func pairsWithMockPump() throws {
        let code = "123456"
        let pump = try EcJpakeContext(role: .server, secret: JpakeAuth.pairingCodeToBytes(code))
        let coord = try PairingCoordinator(pairingCode: code)

        var clientR1a: [UInt8] = [], clientR1b: [UInt8] = []
        var pumpR1a: [UInt8] = [], pumpR1b: [UInt8] = []
        var serverNonce3: [UInt8] = [], pumpDerived: [UInt8] = []
        var pairedKey: [UInt8]?

        coord.onError = { Issue.record("pairing error: \($0)") }
        coord.onPaired = { key, _ in pairedKey = key }
        coord.onSendRequest = { msg in
            do {
                switch msg {
                case let m as Jpake1aRequest:
                    clientR1a = m.centralChallenge
                    let r1 = try pump.writeRoundOne()
                    pumpR1a = Array(r1[0..<165]); pumpR1b = Array(r1[165...])
                    coord.handle(frame: self.frame(33, self.withAppId(pumpR1a)))
                case let m as Jpake1bRequest:
                    clientR1b = m.centralChallenge
                    try pump.readRoundOne(clientR1a + clientR1b)
                    coord.handle(frame: self.frame(35, self.withAppId(pumpR1b)))
                case let m as Jpake2Request:
                    let pumpR2 = try pump.writeRoundTwo()
                    try pump.readRoundTwo(m.centralChallenge)
                    pumpDerived = try pump.deriveSecret()
                    coord.handle(frame: self.frame(37, self.withAppId(pumpR2)))
                case is Jpake3SessionKeyRequest:
                    serverNonce3 = JpakeAuth.randomBytes(8)
                    coord.handle(frame: self.frame(39, self.withAppId(serverNonce3 + [UInt8](repeating: 0, count: 8))))
                case let m as Jpake4KeyConfirmationRequest:
                    let key = Crypto.hkdf(nonce: serverNonce3, keyMaterial: pumpDerived)
                    #expect(Crypto.hmacSha256(data: m.nonce, key: key) == m.hashDigest,
                            "client key-confirmation HMAC should match")
                    let sn4 = JpakeAuth.randomBytes(8)
                    let sh = Crypto.hmacSha256(data: sn4, key: key)
                    coord.handle(frame: self.frame(41, self.withAppId(sn4 + [UInt8](repeating: 0, count: 8) + sh)))
                default:
                    Issue.record("unexpected request: \(type(of: msg))")
                }
            } catch { Issue.record("mock pump error: \(error)") }
        }

        coord.start()

        #expect(coord.step == .paired)
        let key = try #require(pairedKey)
        #expect(key == Crypto.hkdf(nonce: serverNonce3, keyMaterial: pumpDerived))
        #expect(!key.isEmpty)
    }

    /// Resume ("quick-pair"): with a stored derived secret, only rounds 3–4 run (no code), and
    /// the session signing key is derived correctly.
    @Test func resumePairsWithStoredSecret() throws {
        let secret = (0..<32).map { UInt8($0 &+ 7) }   // a secret from a prior full pairing
        let coord = PairingCoordinator(resumeDerivedSecret: secret)
        var serverNonce3: [UInt8] = []
        var pairedKey: [UInt8]?
        coord.onError = { Issue.record("resume error: \($0)") }
        coord.onPaired = { key, _ in pairedKey = key }
        coord.onSendRequest = { msg in
            switch msg {
            case is Jpake3SessionKeyRequest:
                serverNonce3 = JpakeAuth.randomBytes(8)
                coord.handle(frame: self.frame(39, self.withAppId(serverNonce3 + [UInt8](repeating: 0, count: 8))))
            case let m as Jpake4KeyConfirmationRequest:
                let key = Crypto.hkdf(nonce: serverNonce3, keyMaterial: secret)
                #expect(Crypto.hmacSha256(data: m.nonce, key: key) == m.hashDigest)
                let sn4 = JpakeAuth.randomBytes(8)
                let sh = Crypto.hmacSha256(data: sn4, key: key)
                coord.handle(frame: self.frame(41, self.withAppId(sn4 + [UInt8](repeating: 0, count: 8) + sh)))
            default: Issue.record("unexpected request in resume: \(type(of: msg))")
            }
        }
        coord.start()
        #expect(coord.step == .paired)
        #expect(pairedKey == Crypto.hkdf(nonce: serverNonce3, keyMaterial: secret))
    }
}
