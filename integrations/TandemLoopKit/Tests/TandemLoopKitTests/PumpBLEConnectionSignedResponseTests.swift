import Testing
import TandemMessages
@testable import TandemLoopKit

/// U1-06: `PumpBLEConnection.send`'s RESPONSE-PARSE call previously omitted `authenticationKey`, so a
/// signed response on this LoopKit integration path was NEVER HMAC-verified — VA-04 protects the app
/// path (`ResponseParser` itself fails closed on a missing/wrong key), but this call site silently
/// supplied an empty key on every call, which IS the fail-closed "no key available" case, not a real
/// verification. The fix forwards `signing?.authKey ?? []` on the parse call, exactly like the SEND
/// call already did.
///
/// `PumpBLEConnection.send` cannot be exercised end-to-end in a test host: it requires a `PumpBLEClient`
/// in `.ready` state with a real `CBCharacteristic`, and CoreBluetooth provides no public initializer
/// for one (see `PumpBLEClient`'s TCC-abort note — a macOS test host cannot even reach BLE scan).
/// Instead, this proves the SAME call the fixed line now makes —
/// `ResponseParser.parse(frame:characteristic:authenticationKey:)` — using a HAND-SIGNED fixture (no
/// Java oracle needed: `Packetize.doHmacSha1` is byte-exact with the algorithm `ResponseParser`
/// verifies against, per its own doc comment). A response signed with the configured key
/// parses/verifies; the SAME frame verified with the WRONG key fails; an EMPTY key (what the omitted
/// argument silently defaulted to) also fails closed. The full send()->parse() round-trip through
/// `PumpBLEConnection` against a real/simulated `PumpBLEClient` is a bench/host follow-up — recorded in
/// SUMMARY, not claimed proven here (see the plan's TEST STRATEGY note on this precise limitation).
@Suite struct PumpBLEConnectionSignedResponseTests {
    private let key = Array("123456".utf8)          // stand-in JPAKE-derived session key
    private let pumpTimeSinceReset: UInt32 = 1000

    /// Hand-signs an `InitiateBolusResponse` (opcode 159, `.control`, `signed: true`) exactly the way
    /// `ResponseParser.parse` verifies it (VA-04): HMAC-SHA1 over
    /// `[opcode, txId, length] + cargo + pumpTimeSinceReset(4)`, trailer = that HMAC (20 bytes).
    private func signedInitiateBolusFrame(txId: UInt8 = 5, accepted: Bool, bolusId: Int,
                                          signingKey: [UInt8]) -> [UInt8] {
        let opcode = InitiateBolusResponse.props.opCode
        let cargo: [UInt8] = [accepted ? 0 : 1] + Bytes.firstTwoBytesLittleEndian(bolusId) + [0, 0, 0]
        let length = cargo.count + 24   // + 4-byte pumpTimeSinceReset + 20-byte HMAC-SHA1 trailer
        let header: [UInt8] = [opcode, txId, UInt8(length)]
        let pumpTimeBytes = Bytes.toUint32(pumpTimeSinceReset)
        let signedOver = header + cargo + pumpTimeBytes
        let mac = Packetize.doHmacSha1(signedOver, key: signingKey)
        let body = header + cargo + pumpTimeBytes + mac
        return body + Bytes.calculateCRC16(body)
    }

    /// GREEN (this is the fix's positive case): the session key forwarded on the parse call verifies a
    /// correctly-signed response and decodes it.
    @Test func validKeyParsesAndVerifiesTheSignedResponse() throws {
        let frame = signedInitiateBolusFrame(accepted: true, bolusId: 10650, signingKey: key)
        let parsed = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: key)
        let msg = try #require(parsed.message as? InitiateBolusResponse)
        #expect(msg.accepted)
        #expect(msg.bolusId == 10650)
    }

    /// The same frame, verified with the WRONG key, must fail — proving this is a real HMAC
    /// verification, not a pass-through.
    @Test func wrongKeyFailsVerification() throws {
        let frame = signedInitiateBolusFrame(accepted: true, bolusId: 10650, signingKey: key)
        let wrong = Array("000000".utf8)
        #expect(throws: ResponseParser.ParseError.signatureInvalid(opcode: InitiateBolusResponse.props.opCode)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: wrong)
        }
    }

    /// An EMPTY key (what the pre-fix call site effectively always supplied) fails closed rather than
    /// silently accepting the response — this is exactly the risk U1-06 flags: a caller that "forwards"
    /// an empty key is indistinguishable, at the call site, from one that forwards nothing at all.
    @Test func emptyKeyOnASignedResponseFailsClosed() throws {
        let frame = signedInitiateBolusFrame(accepted: true, bolusId: 10650, signingKey: key)
        #expect(throws: ResponseParser.ParseError.signatureKeyUnavailable(opcode: InitiateBolusResponse.props.opCode)) {
            _ = try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: [])
        }
    }
}
