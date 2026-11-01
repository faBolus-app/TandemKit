import Testing
import TandemMessages
@testable import TandemAuth

/// A ZKP scalar comes out a byte short about 1 time in 256 per scalar (F23). These handshakes are
/// seeded so each one has a short scalar in exactly one place, in our rounds and in the pump's, and
/// run on every test run instead of turning up as a 1-in-100 pairing failure. Adapted from pumpx2's
/// `JpakeShortScalarTest` (b5fb3069), with mbedTLS on both sides of the handshake.
@Suite struct JpakeShortScalarTests {
    /// Where the short scalar is, and the seed that puts it there (client context seeded with
    /// `seed`, pump with `seed + pumpSeedOffset`; found by search).
    enum Position: String, CaseIterable, CustomTestStringConvertible {
        case ourRound1a, ourRound1b, ourRound2, pumpRound1a, pumpRound1b, pumpRound2
        var seed: UInt64 {
            switch self {
            case .ourRound1a: 2
            case .ourRound1b: 69
            case .ourRound2: 44
            case .pumpRound1a: 452
            case .pumpRound1b: 160
            case .pumpRound2: 136
            }
        }
        var testDescription: String { rawValue }
    }

    static let pumpSeedOffset: UInt64 = 1_000_000
    static let code = "123456"

    /// The raw mbedTLS scalar lengths for a seed, in the order the handshake writes them, so each
    /// case first proves its seed still produces the short scalar it is named for.
    private func rawScalarLengths(seed: UInt64) throws -> [Position: Int] {
        let secret = JpakeAuth.pairingCodeToBytes(Self.code)
        let ours = try EcJpakeContext(role: .client, secret: secret, randomBytes: SeededRandom.bytes(seed: seed))
        let pump = try EcJpakeContext(
            role: .server, secret: secret, randomBytes: SeededRandom.bytes(seed: seed &+ Self.pumpSeedOffset))
        let o1 = try ours.writeRoundOne(), p1 = try pump.writeRoundOne()
        try ours.readRoundOne(p1)
        try pump.readRoundOne(o1)
        let o2 = try ours.writeRoundTwo(), p2 = try pump.writeRoundTwo()
        let ok = try JpakeRound.roundOne(o1), pk = try JpakeRound.roundOne(p1)
        return [
            .ourRound1a: ok[0].r.count, .ourRound1b: ok[1].r.count,
            .ourRound2: try JpakeRound.keyKPs(o2, count: 1)[0].r.count,
            .pumpRound1a: pk[0].r.count, .pumpRound1b: pk[1].r.count,
            .pumpRound2: try JpakeRound.keyKPs(p2, count: 1, from: 3)[0].r.count
        ]
    }

    private func frame(_ opcode: UInt8, _ cargo: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [opcode, 0, UInt8(cargo.count)] + cargo
        return body + Bytes.calculateCRC16(body)
    }

    /// Pairs through `PairingCoordinator` against a seeded mbedTLS pump. The pump frames each round
    /// the way mbedTLS writes it, at minimal length; with `pumpPadsCargo` it zero-pads to the fixed
    /// cargo size instead. Every request we send is checked for full length, and the pump reads each
    /// of our rounds with mbedTLS's strict parser (it requires the round to end exactly).
    @Test(arguments: Position.allCases, [false, true])
    func pairsWithAShortScalar(at position: Position, pumpPadsCargo: Bool) throws {
        let lengths = try rawScalarLengths(seed: position.seed)
        #expect(lengths[position] == 31, "seed no longer gives a short scalar at \(position): \(lengths)")
        #expect(lengths.filter { $0.key != position }.allSatisfy { $0.value == 32 })

        let secret = JpakeAuth.pairingCodeToBytes(Self.code)
        let ours = try EcJpakeContext(
            role: .client, secret: secret, randomBytes: SeededRandom.bytes(seed: position.seed))
        let pump = try EcJpakeContext(
            role: .server, secret: secret, randomBytes: SeededRandom.bytes(seed: position.seed &+ Self.pumpSeedOffset))
        let coord = PairingCoordinator(auth: JpakeAuth(context: ours))

        var ourR1a: [UInt8] = [], pumpR1b: [UInt8] = []
        var pumpDerived: [UInt8] = [], serverNonce3: [UInt8] = []
        var sentScalarLengths: [Int] = []
        var pairedKey: [UInt8]?
        coord.onError = { Issue.record("pairing error: \($0)") }
        coord.onPaired = { key, _ in pairedKey = key }

        func pumpCargo(_ payload: [UInt8], fixedSize: Int) -> [UInt8] {
            let cargo = [0, 0] + payload
            return pumpPadsCargo ? cargo + [UInt8](repeating: 0, count: max(0, fixedSize - cargo.count)) : cargo
        }
        func checkFullLength(_ m: some JpakeChallengeMessage) throws {
            #expect(m.cargo.count == 167)
            #expect(m.centralChallenge.count == 165)
            let kp = try JpakeRound.keyKPs(m.centralChallenge, count: 1)[0]
            sentScalarLengths.append(kp.r.count)
        }

        coord.onSendRequest = { msg in
            do {
                switch msg {
                case let m as Jpake1aRequest:
                    try checkFullLength(m)
                    ourR1a = m.centralChallenge
                    let (a, b) = try pumpRoundOneHalves(try pump.writeRoundOne())
                    pumpR1b = b
                    coord.handle(frame: self.frame(33, pumpCargo(a, fixedSize: 167)))
                case let m as Jpake1bRequest:
                    try checkFullLength(m)
                    try pump.readRoundOne(ourR1a + m.centralChallenge)
                    coord.handle(frame: self.frame(35, pumpCargo(pumpR1b, fixedSize: 167)))
                case let m as Jpake2Request:
                    try checkFullLength(m)
                    let pumpR2 = try pump.writeRoundTwo()
                    try pump.readRoundTwo(m.centralChallenge)
                    pumpDerived = try pump.deriveSecret()
                    coord.handle(frame: self.frame(37, pumpCargo(pumpR2, fixedSize: 170)))
                case is Jpake3SessionKeyRequest:
                    serverNonce3 = [1, 2, 3, 4, 5, 6, 7, 8]
                    coord.handle(frame: self.frame(39, [0, 0] + serverNonce3 + [UInt8](repeating: 0, count: 8)))
                case let m as Jpake4KeyConfirmationRequest:
                    let key = Crypto.hkdf(nonce: serverNonce3, keyMaterial: pumpDerived)
                    #expect(Crypto.hmacSha256(data: m.nonce, key: key) == m.hashDigest)
                    let nonce4: [UInt8] = [8, 7, 6, 5, 4, 3, 2, 1]
                    let hash = Crypto.hmacSha256(data: nonce4, key: key)
                    coord.handle(frame: self.frame(41, [0, 0] + nonce4 + [UInt8](repeating: 0, count: 8) + hash))
                default:
                    Issue.record("unexpected request: \(type(of: msg))")
                }
            } catch { Issue.record("mock pump error: \(error)") }
        }

        coord.start()

        #expect(coord.step == .paired)
        #expect(sentScalarLengths == [32, 32, 32])
        #expect(try #require(pairedKey) == Crypto.hkdf(nonce: serverNonce3, keyMaterial: pumpDerived))
    }

    /// Our short scalar goes out zero-padded: length byte 32, then a zero, then mbedTLS's 31 bytes.
    @Test func ourShortScalarIsZeroPadded() throws {
        let secret = JpakeAuth.pairingCodeToBytes(Self.code)
        let raw = try EcJpakeContext(
            role: .client, secret: secret, randomBytes: SeededRandom.bytes(seed: Position.ourRound1b.seed)
        ).writeRoundOne()
        #expect(raw.count == 329)
        let auth = JpakeAuth(
            context: try EcJpakeContext(
                role: .client, secret: secret, randomBytes: SeededRandom.bytes(seed: Position.ourRound1b.seed)))
        let (a, b) = try auth.makeRound1Requests()
        #expect(a.centralChallenge + b.centralChallenge != raw)
        #expect(Array(a.centralChallenge) == Array(raw[0..<165]))
        // 1b: X (66) + V (66), then the scalar field.
        #expect(b.centralChallenge[132] == 32)
        #expect(b.centralChallenge[133] == 0)
        #expect(Array(b.centralChallenge[134...]) == Array(raw[(165 + 133)...]))
    }

    /// A round cut off inside a field is rejected, not read past its end.
    @Test func truncatedRoundIsRejected() throws {
        let raw = try EcJpakeContext(role: .client, secret: JpakeAuth.pairingCodeToBytes(Self.code)).writeRoundOne()
        #expect(throws: JpakeRound.DecodeError.self) { try JpakeRound.keyKPs(Array(raw[0..<100]), count: 1) }
        #expect(throws: JpakeRound.DecodeError.self) { try JpakeRound.normalizedRoundTwo([3, 0], server: true) }
        #expect(throws: JpakeRound.DecodeError.self) { try JpakeRound.keyKPs([0] + raw, count: 1) }
    }
}
