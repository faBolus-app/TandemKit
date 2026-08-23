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

    /// A never-terminating stream that overruns the 512-byte cap returns nil and resets;
    /// afterward a fresh single-packet frame still decodes cleanly.
    @Test func overflowResetsThenRecovers() {
        var r = PacketReassembler()
        let txId: UInt8 = 7
        let chunk = [UInt8](repeating: 0x11, count: 200)
        // packetsRemaining decrements 255 → 254 → 253 (never reaches 0);
        // cumulative cargo 200 → 400 → 600 crosses the 512 cap on the third packet.
        #expect(r.ingest([255, txId] + chunk) == nil)   // accumulated 200
        #expect(r.ingest([254, txId] + chunk) == nil)   // accumulated 400
        #expect(r.ingest([253, txId] + chunk) == nil)   // 600 > 512 → reset
        // Buffer is reset: a valid single-packet frame decodes normally.
        #expect(r.ingest([0, 9, 0x20, 9, 0, 0xaf, 0xb5]) == [0x20, 9, 0, 0xaf, 0xb5])
    }

    /// A non-decrementing (duplicated) packetsRemaining within one txId resets rather than
    /// silently concatenating the stale cargo.
    @Test func nonMonotonicRemainingResets() {
        var r = PacketReassembler()
        #expect(r.ingest([2, 4, 0xAA]) == nil)   // fresh sequence, remaining 2
        // Duplicate remaining=2 (should be 1) → monotonic violation → reset, nil.
        #expect(r.ingest([2, 4, 0xBB]) == nil)
        // 0xAA/0xBB were discarded, not concatenated: a fresh frame yields only its own cargo.
        #expect(r.ingest([0, 4, 0xCC]) == [0xCC])
    }

    /// Regression: a normal 3-fragment message (remaining 2 → 1 → 0) reassembles in order.
    @Test func threeFragmentReassembly() {
        var r = PacketReassembler()
        #expect(r.ingest([2, 8, 0x01, 0x02]) == nil)
        #expect(r.ingest([1, 8, 0x03, 0x04]) == nil)
        #expect(r.ingest([0, 8, 0x05, 0x06]) == [0x01, 0x02, 0x03, 0x04, 0x05, 0x06])
    }
}
