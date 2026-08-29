import Testing
@testable import TandemMessages

/// Byte-exact parity for the legacy (V1 / 16-char) pairing responses on AUTHORIZATION (opcodes 17
/// and 19). The vectors are the upstream oracle's OWN canonical test frames — jwoglom
/// `CentralChallengeResponseTest.testTconnectAppFirstPumpReplyMessage_legacyAuth` and
/// `PumpChallengeResponseTest.testTconnectAppChallengeResponseMessage{Success,Failure}_legacyAuth`.
/// Because they are oracle-emitted, these run without the JVM and are not gated on
/// `OracleRunner.isAvailable`. `ResponseParser` validates CRC-16 over the frame before dispatch.
@Suite struct LegacyPairingParityTests {
    /// Reassemble oracle packet hex into a single frame (drop the 2-byte packet header), mirroring
    /// `ResponseParityTests.frame`.
    private func frame(_ packet: String) throws -> [UInt8] {
        Array(try Hex.decode(packet).dropFirst(2))
    }
    private func parse(_ packet: String) throws -> ResponseParser.Parsed {
        try ResponseParser.parse(frame: try frame(packet), characteristic: .authorization)
    }

    @Test func centralChallengeResponseParsesFieldsAndCRC() throws {
        let p = try parse("000011001e01008c212d7a8fbda85f83a3440254488dfb561264ec840c4e16873046bc2c1a")
        #expect(p.opCode == 17)
        let m = try #require(p.message as? CentralChallengeResponse)
        #expect(m.appInstanceId == 1)
        #expect(Hex.encode(m.centralChallengeHash) == "8c212d7a8fbda85f83a3440254488dfb561264ec")
        #expect(Hex.encode(m.hmacKey) == "840c4e16873046bc")
        #expect(m.centralChallengeHash.count == 20 && m.hmacKey.count == 8)
        #expect(m.isValid)
    }

    @Test func pumpChallengeResponseSuccessParses() throws {
        let p = try parse("0001130103010001e8cc")
        #expect(p.opCode == 19)
        let m = try #require(p.message as? PumpChallengeResponse)
        #expect(m.appInstanceId == 1)
        #expect(m.success)
    }

    @Test func pumpChallengeResponseFailureParses() throws {
        let p = try parse("0001130103010000c9dc")
        let m = try #require(p.message as? PumpChallengeResponse)
        #expect(m.appInstanceId == 1)
        #expect(!m.success)
    }

    /// A truncated CentralChallengeResponse cargo is rejected by the parser (length guard), never
    /// trapped, and never yields a valid challenge.
    @Test func truncatedCentralChallengeIsRejected() {
        // opcode 17, txId 0, len 4, 4-byte cargo (< the required 30) + a (wrong) CRC.
        #expect(throws: (any Error).self) {
            _ = try ResponseParser.parse(frame: [17, 0, 4, 0, 0, 1, 2, 0, 0], characteristic: .authorization)
        }
    }
}
