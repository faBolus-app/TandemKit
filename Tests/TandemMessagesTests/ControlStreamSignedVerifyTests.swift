import Testing
@testable import TandemMessages

/// CX-T-01: the 5 CONTROL_STREAM cartridge-fill state responses (0xE1/0xE3/0xE5/0xE7/0xE9) declare
/// `signed: true, stream: true` so `ResponseParser.parse` actually HMAC-verifies their 24-byte auth
/// trailer and strips it before decoding cargo — previously these opcodes had neither flag set, so
/// VA-04 verification silently never ran on them. This suite hand-builds a valid trailer (via the
/// same `Packetize.doHmacSha1` primitive `ResponseParser` verifies with) rather than depending on the
/// JDK oracle, since the oracle's message catalog does not cover these representative-per-opcode
/// CONTROL_STREAM types. Byte-exact with `ResponseParser.parse`'s own signed-over-region computation.
@Suite struct ControlStreamSignedVerifyTests {

    private let key: [UInt8] = Array("unit-test-session-key".utf8)

    /// Recompute the trailing CRC-16 over `body` so the frame passes the CRC gate.
    private func reCrc(_ body: [UInt8]) -> [UInt8] { body + Bytes.calculateCRC16(body) }

    /// Build a signed CONTROL_STREAM frame: `[op, txId, length] + cargo + pumpTimeSinceReset(4) + mac(20) + crc(2)`,
    /// where `mac` is a real HMAC-SHA1 over everything preceding it under `key` — mirroring exactly what
    /// `ResponseParser.parse` recomputes and compares.
    private func signedFrame(
        op: UInt8, cargo: [UInt8], pumpTimeSinceReset: [UInt8] = [0, 0, 0, 0],
        signingKey: [UInt8]
    ) -> [UInt8] {
        let payloadBeforeMac = cargo + pumpTimeSinceReset
        let length = UInt8(payloadBeforeMac.count + 20)
        let header: [UInt8] = [op, 0x01, length]
        let signedOver = header + payloadBeforeMac
        let mac = Packetize.doHmacSha1(signedOver, key: signingKey)
        let body = header + payloadBeforeMac + mac
        return reCrc(body)
    }

    @Test func detectingCartridgeValidTrailerVerifiesAndStrips() throws {
        let op = DetectingCartridgeStateStreamResponse.props.opCode
        let frame = signedFrame(op: op, cargo: [50, 0], signingKey: key)
        let parsed = try ResponseParser.parse(frame: frame, characteristic: .controlStream, authenticationKey: key)
        let msg = try #require(parsed.message as? DetectingCartridgeStateStreamResponse)
        #expect(msg.percentComplete == 50)
    }

    @Test func detectingCartridgeTamperedTrailerFailsVerification() throws {
        let op = DetectingCartridgeStateStreamResponse.props.opCode
        var frame = signedFrame(op: op, cargo: [50, 0], signingKey: key)
        var body = Array(frame[0..<(frame.count - 2)])
        body[3] = body[3] == 50 ? 51 : 50  // tamper cargo[0] (percentComplete) after signing
        frame = reCrc(body)  // attacker fixes the CRC (non-cryptographic)
        #expect(throws: ResponseParser.ParseError.signatureInvalid(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .controlStream, authenticationKey: key)
        }
    }

    @Test func fillCannulaAbsentTrailerFailsClosed() {
        let op = FillCannulaStateStreamResponse.props.opCode
        // Declared length too short to hold the 24-byte trailer ⇒ signatureMissing, not a decode.
        let short: [UInt8] = [op, 0x01, 1, 3]
        let frame = reCrc(short)
        #expect(throws: ResponseParser.ParseError.signatureMissing(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .controlStream, authenticationKey: key)
        }
    }

    @Test func fillCannulaEmptyKeyFailsClosed() throws {
        let op = FillCannulaStateStreamResponse.props.opCode
        let frame = signedFrame(op: op, cargo: [3], signingKey: key)
        #expect(throws: ResponseParser.ParseError.signatureKeyUnavailable(opcode: op)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .controlStream, authenticationKey: [])
        }
    }
}
