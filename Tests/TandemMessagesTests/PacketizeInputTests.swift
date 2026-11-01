import Testing
@testable import TandemMessages

/// `Packetize` rejects input it can't frame instead of trapping or sending a malformed write.
/// Mirrors upstream `PacketizeTest` (pumpx2 9625c529), adapted to what can go wrong in Swift.
@Suite struct PacketizeInputTests {
    private let key = Array("6VeDeRAL5DCigGw2".utf8)

    @Test func chunksEvenlyAndWithAShortTail() throws {
        let packets = try Packetize.packetize(ApiVersionRequest(), txId: 1, maxChunkSize: 2)
        // 3-byte header + 0 cargo + 2-byte CRC = 5 bytes: 2 + 2 + 1.
        #expect(packets.map(\.internalCargo.count) == [2, 2, 1])
        #expect(packets.map(\.packetsRemaining) == [2, 1, 0])
    }

    @Test(arguments: [0, -1])
    func rejectsANonPositiveChunkSize(size: Int) {
        #expect(throws: Packetize.PacketizeError.invalidChunkSize(size)) {
            try Packetize.packetize(ApiVersionRequest(), txId: 1, maxChunkSize: size)
        }
    }

    @Test func rejectsAChunkSizeThatNeedsMoreThan256Packets() {
        // The largest legal frame is 3 + 255 + 2 = 260 bytes: 260 one-byte chunks can't be
        // counted in packetsRemaining, 130 two-byte chunks can.
        let big = RawMessage(cargo: [UInt8](repeating: 0, count: 255))
        #expect(throws: Packetize.PacketizeError.invalidChunkSize(1)) {
            try Packetize.packetize(big, txId: 1, maxChunkSize: 1)
        }
        #expect(throws: Never.self) { try Packetize.packetize(big, txId: 1, maxChunkSize: 2) }
    }

    @Test func rejectsCargoThatOverflowsTheLengthByte() {
        let tooLong = RawMessage(cargo: [UInt8](repeating: 0, count: 256))
        #expect(throws: Packetize.PacketizeError.cargoTooLong(opCode: 0x7F, framedLength: 256)) {
            try Packetize.packetize(tooLong, txId: 1)
        }
    }

    @Test func rejectsASignedCargoThatOverflowsOnlyWithItsSignature() {
        // 232 + 24 = 256: the cargo alone fits, the signature pushes it over.
        let signed = SignedRawMessage(cargo: [UInt8](repeating: 0, count: 232))
        #expect(throws: Packetize.PacketizeError.cargoTooLong(opCode: 0x7F, framedLength: 256)) {
            try Packetize.packetize(signed, authenticationKey: key, txId: 1)
        }
    }

    /// The delivery wall is checked before any framing check, so a closed tier is what's reported.
    @Test func deliveryGateIsReportedBeforeAMissingKey() {
        #expect(throws: Packetize.ActionsAffectingInsulinDeliveryNotEnabledError.self) {
            try Packetize.packetize(SuspendPumpingRequest(), txId: 1)
        }
    }

    @Test func rejectsASignedMessageWithNoKey() {
        #expect(throws: Packetize.PacketizeError.missingAuthenticationKey(opCode: CancelBolusRequest.props.opCode)) {
            try Packetize.packetize(CancelBolusRequest(bolusId: 1), txId: 1)
        }
    }
}

/// Bare messages with chosen cargo, for framing limits no real message reaches.
private struct RawMessage: Message {
    static let props = MessageProps(opCode: 0x7F, type: .request)
    var cargo: [UInt8]
    init() { cargo = [] }
    init(cargo: [UInt8]) { self.cargo = cargo }
    mutating func parse(_ raw: [UInt8]) { cargo = raw }
}

private struct SignedRawMessage: Message {
    static let props = MessageProps(opCode: 0x7F, signed: true, type: .request)
    var cargo: [UInt8]
    init() { cargo = [] }
    init(cargo: [UInt8]) { self.cargo = cargo }
    mutating func parse(_ raw: [UInt8]) { cargo = raw }
}
