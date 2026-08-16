import Foundation

/// Endian-aware numeric/byte conversions, CRC-16 (CCITT/XModem variant used by the pump),
/// and secure randomness. Port of `com.jwoglom.pumpx2.pump.messages.helpers.Bytes`.
///
/// All multi-byte pump cargo values are little-endian. Use these helpers rather than
/// hand-rolling conversions to avoid endian bugs (matching the upstream guidance).
public enum Bytes {

    // MARK: - Slicing / combining

    public static func dropFirst(_ bytes: [UInt8], _ n: Int) -> [UInt8] {
        Array(bytes[n...])
    }

    public static func dropLast(_ bytes: [UInt8], _ n: Int) -> [UInt8] {
        Array(bytes[..<(bytes.count - n)])
    }

    public static func reverse(_ bytes: [UInt8]) -> [UInt8] {
        bytes.reversed()
    }

    public static func combine(_ items: [UInt8]...) -> [UInt8] {
        var ret = [UInt8]()
        ret.reserveCapacity(items.reduce(0) { $0 + $1.count })
        for item in items { ret.append(contentsOf: item) }
        return ret
    }

    public static func empty(_ size: Int) -> [UInt8] {
        [UInt8](repeating: 0, count: size)
    }

    // MARK: - Reads (little-endian)

    /// Unsigned 16-bit little-endian at offset `i`.
    public static func readShort(_ raw: [UInt8], _ i: Int) -> Int {
        precondition(i >= 0 && i + 1 < raw.count)
        return (Int(raw[i + 1]) << 8) | Int(raw[i])
    }

    /// 32-bit little-endian IEEE-754 float at offset `i`.
    public static func readFloat(_ raw: [UInt8], _ i: Int) -> Float {
        precondition(i >= 0 && i + 3 < raw.count)
        let bits = UInt32(raw[i]) | (UInt32(raw[i + 1]) << 8)
            | (UInt32(raw[i + 2]) << 16) | (UInt32(raw[i + 3]) << 24)
        return Float(bitPattern: bits)
    }

    /// Unsigned 32-bit little-endian at offset `i`.
    public static func readUint32(_ raw: [UInt8], _ i: Int) -> UInt32 {
        precondition(i >= 0 && i + 3 < raw.count)
        return UInt32(raw[i]) | (UInt32(raw[i + 1]) << 8)
            | (UInt32(raw[i + 2]) << 16) | (UInt32(raw[i + 3]) << 24)
    }

    /// Unsigned 64-bit little-endian at offset `i`.
    public static func readUint64(_ raw: [UInt8], _ i: Int) -> UInt64 {
        precondition(i >= 0 && i + 7 < raw.count)
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(raw[i + k]) << (8 * k) }
        return v
    }

    // MARK: - Writes (little-endian)

    public static func toFloat(_ f: Float) -> [UInt8] {
        let bits = f.bitPattern
        return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF),
                UInt8((bits >> 16) & 0xFF), UInt8((bits >> 24) & 0xFF)]
    }

    /// 4-byte little-endian unsigned 32-bit.
    public static func toUint32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF),
         UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    /// 8-byte little-endian unsigned 64-bit.
    public static func toUint64(_ v: UInt64) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 8)
        for k in 0..<8 { out[k] = UInt8((v >> (8 * k)) & 0xFF) }
        return out
    }

    /// Low two bytes of `i`, little-endian. Corollary of `readShort`.
    public static func firstTwoBytesLittleEndian(_ i: Int) -> [UInt8] {
        let v = UInt32(bitPattern: Int32(truncatingIfNeeded: i)) & 0x0000_FFFF
        return [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }

    public static func firstByteLittleEndian(_ i: Int) -> [UInt8] {
        [UInt8(UInt32(bitPattern: Int32(truncatingIfNeeded: i)) & 0xFF)]
    }

    // MARK: - Strings (null-terminated / null-padded UTF-8)

    /// Reads a UTF-8 string starting at `i`, stopping at the first non-positive byte
    /// (matching Java's `b > 0`) or after `length` bytes.
    public static func readString(_ raw: [UInt8], _ i: Int, _ length: Int) -> String {
        precondition(i >= 0 && i < raw.count)
        var strBytes = [UInt8]()
        var idx = i
        while idx < raw.count, Int8(bitPattern: raw[idx]) > 0 {
            strBytes.append(raw[idx])
            if strBytes.count >= length { break }
            idx += 1
        }
        return String(decoding: strBytes, as: UTF8.self)
    }

    /// Encodes `input` as UTF-8, null-padded up to `length`.
    public static func writeString(_ input: String, _ length: Int) -> [UInt8] {
        var encoded = [UInt8](input.utf8)
        while encoded.count < length { encoded.append(0) }
        return encoded
    }

    // MARK: - CRC-16

    // Precomputed table (CRC-16 CCITT / XModem, poly 0x1021, init 0xFFFF) — matches upstream.
    private static let crcLookupTable: [Int] = [
        0, 4129, 8258, 12387, 16516, 20645, 24774, 28903, 33032, 37161, 41290, 45419, 49548, 53677, 57806, 61935,
        4657, 528, 12915, 8786, 21173, 17044, 29431, 25302, 37689, 33560, 45947, 41818, 54205, 50076, 62463, 58334,
        9314, 13379, 1056, 5121, 25830, 29895, 17572, 21637, 42346, 46411, 34088, 38153, 58862, 62927, 50604, 54669,
        13907, 9842, 5649, 1584, 30423, 26358, 22165, 18100, 46939, 42874, 38681, 34616, 63455, 59390, 55197, 51132,
        18628, 22757, 26758, 30887, 2112, 6241, 10242, 14371, 51660, 55789, 59790, 63919, 35144, 39273, 43274, 47403,
        23285, 19156, 31415, 27286, 6769, 2640, 14899, 10770, 56317, 52188, 64447, 60318, 39801, 35672, 47931, 43802,
        27814, 31879, 19684, 23749, 11298, 15363, 3168, 7233, 60846, 64911, 52716, 56781, 44330, 48395, 36200, 40265,
        32407, 28342, 24277, 20212, 15891, 11826, 7761, 3696, 65439, 61374, 57309, 53244, 48923, 44858, 40793, 36728,
        37256, 33193, 45514, 41451, 53516, 49453, 61774, 57711, 4224, 161, 12482, 8419, 20484, 16421, 28742, 24679,
        33721, 37784, 41979, 46042, 49981, 54044, 58239, 62302, 689, 4752, 8947, 13010, 16949, 21012, 25207, 29270,
        46570, 42443, 38312, 34185, 62830, 58703, 54572, 50445, 13538, 9411, 5280, 1153, 29798, 25671, 21540, 17413,
        42971, 47098, 34713, 38840, 59231, 63358, 50973, 55100, 9939, 14066, 1681, 5808, 26199, 30326, 17941, 22068,
        55628, 51565, 63758, 59695, 39368, 35305, 47498, 43435, 22596, 18533, 30726, 26663, 6336, 2273, 14466, 10403,
        52093, 56156, 60223, 64286, 35833, 39896, 43963, 48026, 19061, 23124, 27191, 31254, 2801, 6864, 10931, 14994,
        64814, 60687, 56684, 52557, 48554, 44427, 40424, 36297, 31782, 27655, 23652, 19525, 15522, 11395, 7392, 3265,
        61215, 65342, 53085, 57212, 44955, 49082, 36825, 40952, 28183, 32310, 20053, 24180, 11923, 16050, 3793, 7920,
    ]

    /// CRC-16 over `bytes`, returned as 2 little-endian bytes. Byte-exact port of `calculateCRC16`.
    /// Uses UInt32 to replicate Java's 32-bit int accumulation with unsigned right shift.
    public static func calculateCRC16(_ bytes: [UInt8]) -> [UInt8] {
        var i: UInt32 = 0x0000_FFFF
        for b in bytes {
            let index = Int((UInt32(b) ^ (i >> 8)) & 0xFF)
            i = (i << 8) ^ UInt32(truncatingIfNeeded: crcLookupTable[index])
        }
        let i2 = i ^ 0
        return [UInt8(i2 & 0xFF), UInt8((i2 >> 8) & 0xFF)]
    }

    // MARK: - Secure randomness

    public static func secureRandom8Bytes() -> [UInt8] { secureRandom(8) }
    public static func secureRandom10Bytes() -> [UInt8] { secureRandom(10) }

    public static func secureRandom(_ count: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: count)
        for k in 0..<count { out[k] = UInt8.random(in: UInt8.min...UInt8.max) }
        return out
    }
}
