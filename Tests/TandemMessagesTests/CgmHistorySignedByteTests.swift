import Testing
@testable import TandemMessages

/// CGM-history trend-rate (raw[13]) and RSSI (raw[15]) are signed one-byte fields — the Java oracle
/// sign-extends them, so `0xFE` decodes to `-2` and `0xA7` to `-89`. An unsigned read would be wrong.
/// The raw cargo starts at offset 10, so `tail[3]` maps to raw[13] and `tail[5]` to raw[15].
@Suite struct CgmHistorySignedByteTests {
    /// Builds a 26-byte history-log record with the given header + a tail starting at offset 10.
    /// Mirrors the helper in HistoryLogEventsTests.swift (that copy is file-private).
    private func record(typeId: Int, pumpTimeSec: UInt32, seq: UInt32, tail: [UInt8] = []) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: 26)
        let t = Bytes.firstTwoBytesLittleEndian(typeId)
        r[0] = t[0]
        r[1] = t[1]
        let pt = Bytes.toUint32(pumpTimeSec)
        for i in 0..<4 { r[2 + i] = pt[i] }
        let sq = Bytes.toUint32(seq)
        for i in 0..<4 { r[6 + i] = sq[i] }
        for (i, b) in tail.enumerated() where 10 + i < 26 { r[10 + i] = b }
        return r
    }

    /// tail with rate@offset-3 (raw[13]) and rssi@offset-5 (raw[15]) set to the given bytes.
    private func cgmTail(rate: UInt8, rssi: UInt8) -> [UInt8] {
        var tail = [UInt8](repeating: 0, count: 16)
        tail[3] = rate
        tail[5] = rssi
        return tail
    }

    // MARK: DexcomG6CGMHistoryLog (typeId 256)

    /// Negative one-byte values sign-extend: 0xFE -> -2, 0xA7 -> -89.
    @Test func dexcomG6SignedNegative() {
        let rec = record(typeId: 256, pumpTimeSec: 500, seq: 1, tail: cgmTail(rate: 0xFE, rssi: 0xA7))
        let m = try? #require(HistoryLogParser.parse(record: rec) as? DexcomG6CGMHistoryLog)
        #expect(m?.rate == -2)
        #expect(m?.rssi == -89)
    }

    /// Positive boundary: 0x7F stays 127 (largest positive Int8).
    @Test func dexcomG6PositiveBoundary() {
        let rec = record(typeId: 256, pumpTimeSec: 500, seq: 1, tail: cgmTail(rate: 0x7F, rssi: 0x7F))
        let m = try? #require(HistoryLogParser.parse(record: rec) as? DexcomG6CGMHistoryLog)
        #expect(m?.rate == 127)
        #expect(m?.rssi == 127)
    }

    /// Zero stays zero.
    @Test func dexcomG6Zero() {
        let rec = record(typeId: 256, pumpTimeSec: 500, seq: 1, tail: cgmTail(rate: 0x00, rssi: 0x00))
        let m = try? #require(HistoryLogParser.parse(record: rec) as? DexcomG6CGMHistoryLog)
        #expect(m?.rate == 0)
        #expect(m?.rssi == 0)
    }

    // MARK: DexcomG7CGMHistoryLog (typeId 399) — proves the fix is consistent across decoders.

    @Test func dexcomG7SignedNegative() {
        let rec = record(typeId: 399, pumpTimeSec: 500, seq: 1, tail: cgmTail(rate: 0xFE, rssi: 0xA7))
        let m = try? #require(HistoryLogParser.parse(record: rec) as? DexcomG7CGMHistoryLog)
        #expect(m?.rate == -2)
        #expect(m?.rssi == -89)
    }
}
