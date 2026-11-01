import Testing
@testable import TandemMessages

/// An op-77 error on CONTROL answers a signed write, so it is trusted only when its HMAC trailer
/// verifies. Anything else parses as `UnverifiedErrorResponse`, never as `ErrorResponse`, so a forged
/// or damaged NACK can't make a write look refused; the write's outcome stays unknown.
@Suite struct ControlErrorHmacTests {
    private let key = Array("6VeDeRAL5DCigGw2".utf8)

    /// The signed form a pump sends: `[77, txId, 26] + [requestCodeId, errorCodeId] +
    /// pumpTimeSinceReset(4) + HMAC-SHA1(20) + CRC`. Packetize writes the same trailer for requests
    /// (its HMAC is oracle-checked in OracleParityTests).
    private func signedFrame(errorCode: UInt8, key: [UInt8], txId: UInt8 = 0x12) throws -> [UInt8] {
        let packets = try Packetize.packetize(
            SignedErrorCargo(cargo: [0, errorCode]), authenticationKey: key, txId: txId,
            pumpTimeSinceReset: 586_961_779, maxChunkSize: 255)
        return Array(packets[0].build().dropFirst(2))
    }

    private func reCrc(_ frame: [UInt8]) -> [UInt8] {
        let body = Array(frame.dropLast(2))
        return body + Bytes.calculateCRC16(body)
    }

    private func parse(_ frame: [UInt8], key: [UInt8]) throws -> ResponseParser.Parsed {
        try ResponseParser.parse(frame: frame, characteristic: .control, authenticationKey: key)
    }

    @Test func verifiedControlErrorParsesAsErrorResponse() throws {
        let parsed = try parse(signedFrame(errorCode: 6, key: key), key: key)
        let error = try #require(parsed.message as? ErrorResponse)
        #expect(error.errorCodeId == 6 && error.isBadOpcode)
        #expect(error.cargo == [0, 6])
        #expect(parsed.txId == 0x12)
    }

    /// A tampered error code with the CRC recomputed (CRC is not cryptographic) is caught by the HMAC.
    @Test func tamperedControlErrorIsUnverified() throws {
        var frame = try signedFrame(errorCode: 0, key: key)
        frame[4] = 6
        let parsed = try parse(reCrc(frame), key: key)
        #expect(parsed.message is ErrorResponse == false)
        let unverified = try #require(parsed.message as? UnverifiedErrorResponse)
        #expect(unverified.reason == .hmacMismatch)
        #expect(unverified.claimedErrorCodeId == 6)
        #expect(parsed.txId == 0x12)
    }

    @Test func controlErrorSignedWithAnotherKeyIsUnverified() throws {
        let parsed = try parse(signedFrame(errorCode: 0, key: Array("another-key-0000".utf8)), key: key)
        #expect((parsed.message as? UnverifiedErrorResponse)?.reason == .hmacMismatch)
    }

    @Test func controlErrorWithNoSessionKeyIsUnverified() throws {
        let parsed = try parse(signedFrame(errorCode: 0, key: key), key: [])
        #expect((parsed.message as? UnverifiedErrorResponse)?.reason == .keyUnavailable)
    }

    /// A 2-byte op-77 on CONTROL has no trailer to check; its claimed codes are kept.
    @Test func unsignedControlErrorIsUnverified() throws {
        let body: [UInt8] = [77, 3, 2, 0x9C, 6]
        let parsed = try parse(body + Bytes.calculateCRC16(body), key: key)
        let unverified = try #require(parsed.message as? UnverifiedErrorResponse)
        #expect(unverified.reason == .trailerMissing)
        #expect(unverified.claimedRequestCodeId == 0x9C && unverified.claimedErrorCodeId == 6)
    }

    /// A real CONTROL op-77 captured from P1 (API 2.5) after a rejected ChangeTimeDate: cargo
    /// `00 00`, then the trailer. Without that session's key it must not verify, and its layout must
    /// parse as a 26-byte signed reply with the claimed codes at bytes 0 and 1.
    @Test func capturedP1ControlErrorParsesAsUnverifiedWithoutItsKey() throws {
        let frame = try Hex.decode("4d121a00007353fc22f897d0152e293cef765ee02d87113b4ee20206d7c73c")
        #expect(frame[2] == 26)
        let parsed = try parse(reCrc(frame), key: key)
        let unverified = try #require(parsed.message as? UnverifiedErrorResponse)
        #expect(unverified.reason == .hmacMismatch)
        #expect(unverified.cargo == [0, 0])
    }

    /// The CURRENT_STATUS op-77 answers unsigned reads and stays unsigned.
    @Test func currentStatusErrorIsUnchanged() throws {
        let body: [UInt8] = [77, 3, 2, 20, 6]
        let parsed = try ResponseParser.parse(
            frame: body + Bytes.calculateCRC16(body), characteristic: .currentStatus)
        #expect((parsed.message as? ErrorResponse)?.isBadOpcode == true)
    }
}

/// An op-77-shaped signed message, to mint a valid trailer with Packetize.
private struct SignedErrorCargo: Message {
    static let props = MessageProps(opCode: 77, signed: true, type: .response, characteristic: .control)
    var cargo: [UInt8]
    init() { cargo = [] }
    init(cargo: [UInt8]) { self.cargo = cargo }
    mutating func parse(_ raw: [UInt8]) { cargo = raw }
}
