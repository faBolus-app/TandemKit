import Foundation

/// Platform-independent hex encode/decode.
/// Port of `com.jwoglom.pumpx2.shared.Hex`.
public enum Hex {
    private static let hexChars = Array("0123456789abcdef")

    /// Lowercase hex string, no separators. Mirrors `encodeHexString`.
    public static func encode(_ data: [UInt8]) -> String {
        var s = String()
        s.reserveCapacity(data.count * 2)
        for b in data {
            s.append(hexChars[Int((b >> 4) & 0x0F)])
            s.append(hexChars[Int(b & 0x0F)])
        }
        return s
    }

    public static func encode(_ data: Data) -> String { encode([UInt8](data)) }

    /// Decodes a hex string to bytes. Mirrors `decodeHex`; throws on odd length or bad chars.
    public static func decode(_ hex: String) throws -> [UInt8] {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else {
            throw HexError.oddLength
        }
        var result = [UInt8]()
        result.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            let high = try nibble(chars[i], index: i)
            let low = try nibble(chars[i + 1], index: i + 1)
            result.append((high << 4) | low)
            i += 2
        }
        return result
    }

    private static func nibble(_ c: UInt8, index: Int) throws -> UInt8 {
        switch c {
        case 0x30...0x39: return c - 0x30          // 0-9
        case 0x61...0x66: return c - 0x61 + 10      // a-f
        case 0x41...0x46: return c - 0x41 + 10      // A-F
        default: throw HexError.invalidCharacter(Character(UnicodeScalar(c)), index)
        }
    }

    public enum HexError: Error, Equatable {
        case oddLength
        case invalidCharacter(Character, Int)
    }
}
