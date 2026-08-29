import Testing
@testable import TandemMessages

/// `ResponseParser` must HMAC-SHA1-verify the auth trailer on a signed response and fail closed on a
/// forged, tampered, absent, or wrong-key trailer. A CRC-valid forged InitiateBolus NACK must not be
/// accepted (that would release the durable delivery lock).
@Suite(.enabled(if: OracleRunner.isAvailable)) struct SignedResponseHmacVerifyTests {

    private let key = Array(OracleRunner.testPairingCode.utf8)
    private let op = InitiateBolusResponse.props.opCode

    /// Reassemble oracle packet hex into a single frame (drop each packet's 2-byte header).
    private func reassemble(_ packets: [String]) throws -> [UInt8] {
        var out: [UInt8] = []
        for hex in packets { out.append(contentsOf: try Hex.decode(hex).dropFirst(2)) }
        return out
    }

    /// A signed InitiateBolusResponse (accepted, bolusId 10650) minted with the shared test key/time, so
    /// its trailer HMAC is valid under `key`.
    private func validSignedFrame() throws -> [UInt8] {
        let packets = try OracleRunner.encode(
            txId: 5, messageName: "InitiateBolusResponse", json: "[0, 10650, 0]",
            pairingCode: OracleRunner.testPairingCode,
            pumpTimeSinceReset: OracleRunner.testPumpTimeSinceReset
        ).packets
        return try reassemble(packets)
    }

    /// Recompute the trailing CRC-16 over a (possibly mutated) body so the frame passes the CRC gate —
    /// exactly what a forging attacker does (CRC is non-cryptographic).
    private func reCrc(_ body: [UInt8]) -> [UInt8] { body + Bytes.calculateCRC16(body) }

    @Test func validSignedResponseVerifiesAndParses() throws {
        let frame = try validSignedFrame()
        let parsed = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: key)
        let msg = try #require(parsed.message as? InitiateBolusResponse)
        #expect(msg.accepted)  // status 0 ⇒ accepted
        #expect(msg.bolusId == 10650)
    }

    /// Flip the status/accept byte to forge a NACK, then recompute the CRC so integrity passes —
    /// the HMAC must still reject it.
    @Test func tamperedStatusWithFixedCrcIsRejected() throws {
        var frame = try validSignedFrame()
        var body = Array(frame[0..<(frame.count - 2)])
        body[3] = body[3] == 0 ? 1 : 0  // flip accepted(0) ⇄ rejected(non-zero)
        frame = reCrc(body)  // attacker fixes the CRC
        #expect(throws: ResponseParser.ParseError.signatureInvalid(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: key)
        }
    }

    /// A signed response whose declared length can't hold the 24-byte trailer fails closed (missing sig).
    @Test func absentTrailerFailsClosed() {
        let short: [UInt8] = [op, 0, 6] + [UInt8](repeating: 0, count: 6)
        let frame = reCrc(short)
        #expect(throws: ResponseParser.ParseError.signatureMissing(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: key)
        }
    }

    /// A signed response with NO key available must not be trusted (fail closed, never fail open).
    @Test func emptyKeyOnSignedResponseFailsClosed() throws {
        let frame = try validSignedFrame()
        #expect(throws: ResponseParser.ParseError.signatureKeyUnavailable(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: [])
        }
    }

    /// A wrong session key rejects an otherwise-valid frame.
    @Test func wrongKeyIsRejected() throws {
        let frame = try validSignedFrame()
        let wrong = Array("0000000000000000".utf8)  // 16 chars, wrong value
        #expect(throws: ResponseParser.ParseError.signatureInvalid(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: wrong)
        }
    }

    /// Sanity: `verifySignature: false` still parses (the decode/dispatch-test escape hatch), proving the
    /// gate is the verification step, not the decode path.
    @Test func verifyDisabledStillDecodes() throws {
        let frame = try validSignedFrame()
        let parsed = try ResponseParser.parse(
            frame: frame, characteristic: .control,
            authenticationKey: [], verifySignature: false)
        #expect(parsed.message is InitiateBolusResponse)
    }
}
