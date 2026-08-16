import Testing
@testable import TandemBLE

@Suite struct PacketReassemblerTests {
    /// Single packet (packetsRemaining == 0) yields its cargo immediately.
    @Test func singlePacket() {
        var r = PacketReassembler()
        // [pktsRemaining=0, txId=5, opcode=0x20, txId=5, len=0, crc0, crc1]
        let frame = r.ingest([0, 5, 0x20, 5, 0, 0xaf, 0xb5])
        #expect(frame == [0x20, 5, 0, 0xaf, 0xb5])
    }

    /// Two-packet frame: first returns nil, second completes and concatenates cargo.
    @Test func twoPackets() {
        var r = PacketReassembler()
        #expect(r.ingest([1, 2, 0xAA, 0xBB]) == nil)      // packetsRemaining=1
        let frame = r.ingest([0, 2, 0xCC, 0xDD])          // packetsRemaining=0
        #expect(frame == [0xAA, 0xBB, 0xCC, 0xDD])
    }

    /// A new txId arriving mid-stream restarts reassembly.
    @Test func txIdMismatchResets() {
        var r = PacketReassembler()
        #expect(r.ingest([1, 2, 0xAA]) == nil)            // txId 2, incomplete
        // txId changes to 3 as a single-packet frame → returns just its cargo.
        #expect(r.ingest([0, 3, 0xEE]) == [0xEE])
    }

    @Test func tooShortResets() {
        var r = PacketReassembler()
        #expect(r.ingest([0]) == nil)
    }
}
