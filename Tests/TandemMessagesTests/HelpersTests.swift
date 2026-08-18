import Testing
@testable import TandemMessages

@Suite struct HexTests {
    @Test func encode() {
        #expect(Hex.encode([0x00, 0x0f, 0xff, 0xa5]) == "000fffa5")
        #expect(Hex.encode([]) == "")
    }

    @Test func decode() throws {
        #expect(try Hex.decode("000fffa5") == [0x00, 0x0f, 0xff, 0xa5])
        #expect(try Hex.decode("ABCDEF") == [0xab, 0xcd, 0xef]) // case-insensitive
    }

    @Test func roundTrip() throws {
        let bytes: [UInt8] = (0...255).map { UInt8($0) }
        #expect(try Hex.decode(Hex.encode(bytes)) == bytes)
    }

    @Test func decodeErrors() {
        #expect(throws: Hex.HexError.oddLength) { try Hex.decode("abc") }
        #expect(throws: (any Error).self) { try Hex.decode("zz") }
    }
}

@Suite struct BytesTests {
    @Test func readWriteUint32RoundTrip() {
        for v: UInt32 in [0, 1, 255, 256, 65535, 0x1234_5678, 0xFFFF_FFFF] {
            let bytes = Bytes.toUint32(v)
            #expect(bytes.count == 4)
            // append a guard byte since readUint32 requires i+3 < count
            #expect(Bytes.readUint32(bytes + [0], 0) == v)
        }
    }

    @Test func toUint32IsLittleEndian() {
        #expect(Bytes.toUint32(0x1234_5678) == [0x78, 0x56, 0x34, 0x12])
    }

    @Test func readShortLittleEndian() {
        #expect(Bytes.readShort([0x34, 0x12, 0x00], 0) == 0x1234)
    }

    @Test func floatRoundTrip() {
        for f: Float in [0, 1, -1, 3.14159, 12.5, -0.001] {
            let bytes = Bytes.toFloat(f)
            #expect(Bytes.readFloat(bytes + [0], 0) == f)
        }
    }

    @Test func uint64RoundTrip() {
        for v: UInt64 in [0, 1, 0xFF, 0x0102_0304_0506_0708, .max] {
            #expect(Bytes.readUint64(Bytes.toUint64(v) + [0], 0) == v)
        }
    }

    @Test func stringRoundTrip() {
        let encoded = Bytes.writeString("Mobi", 10)
        #expect(encoded.count == 10)
        #expect(Bytes.readString(encoded, 0, 10) == "Mobi")
    }

    // Non-ASCII round-trip: the fixed readString terminates only on a NUL byte (0x00), not on
    // the first byte >= 0x80. Every UTF-8 continuation/lead byte of these strings is >= 0x80, so
    // the pre-fix signed-terminator (`Int8(bitPattern: raw[idx]) > 0`) truncated them at byte 0
    // (e.g. "café" decoded as "caf"). Shape mirrors upstream jwoglom/pumpX2 PR #123's own
    // BytesTest additions (DEV-NOT-TRUSTED reference; validated here against TandemKit's own code).
    // NO ORACLE BACKING by construction: the vendored pumpx2-oracle Java Bytes.java (submodule pin
    // dad3eea2, pre-PR#123) carries the identical bug, so OracleParityTests cannot cover this — this
    // direct BytesTests case is the substitute ground truth (same posture as the 09.8-04 targetBg
    // capture-based deviation).
    @Test func readWriteStringDecodesNonAscii() {
        for s in ["café", "Ünïcøde", "日本語", "aéb"] {
            let field = Bytes.writeString(s, 32)
            #expect(Bytes.readString(field, 0, 32) == s)
        }
    }

    // writeString boundary lock. The overlong-reject itself is a fail-loud `precondition` (Swift
    // Testing has no precondition-trap assertion, and this project has no precondition-crash helper —
    // do NOT invent one), so this case locks the *in-bound* boundary positively: the exact-fit case
    // (encoded UTF-8 byte count == field width) must NOT false-trigger the precondition, and the
    // byte pattern must be correct. "é" is TWO UTF-8 bytes (0xc3 0xa9), so writeString("é", 4) is
    // the two content bytes NUL-padded to 4 — this documents that the bound is on encoded BYTES, not
    // characters. Short-input padding (unchanged by the fix) is re-locked too.
    @Test func writeStringExactFitBoundaryAndPad() {
        #expect(Bytes.writeString("é", 4) == [0xc3, 0xa9, 0, 0])
        #expect(Bytes.writeString("é", 4).count == 4)
        #expect(Bytes.writeString("abc", 3).count == 3)   // exact-fit ASCII, no padding
        #expect(Bytes.writeString("Mobi", 10).count == 10) // short-input NUL-pad
    }

    @Test func combineAndSlices() {
        #expect(Bytes.combine([1, 2], [3], [4, 5]) == [1, 2, 3, 4, 5])
        #expect(Bytes.dropFirst([1, 2, 3, 4], 2) == [3, 4])
        #expect(Bytes.dropLast([1, 2, 3, 4], 1) == [1, 2, 3])
        #expect(Bytes.reverse([1, 2, 3]) == [3, 2, 1])
    }

    // CRC-16 CCITT/XModem: init 0xFFFF, poly 0x1021 (CCITT-FALSE). "123456789" → 0x29B1;
    // upstream returns [low, high] bytes.
    @Test func crc16KnownVector() {
        #expect(Bytes.calculateCRC16(Array("123456789".utf8)) == [0xB1, 0x29])
    }

    @Test func crc16Deterministic() {
        let a = Bytes.calculateCRC16([0x01, 0x02, 0x03])
        #expect(a == Bytes.calculateCRC16([0x01, 0x02, 0x03]))
        #expect(a.count == 2)
    }
}
