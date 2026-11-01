import Foundation

/// The wire layout of an EC-JPAKE round (RFC 8236 / Thread's TLS encoding, as mbedTLS writes it),
/// so a round can be re-encoded with every ZKP scalar at its full length.
///
/// Why: mbedTLS writes the proof scalar `r` at its minimal length, so about 1 time in 256 per
/// scalar a round comes out a byte short. Tandem carries rounds in fixed-size cargos (round 1 split
/// 165 + 165, round 2 in 165 or 168), so a short round shifts bytes between the halves or leaves a
/// trailing pad byte that a strict reader rejects. pumpx2 fixed both directions (3af6d36a pads its
/// own scalars; 6ef10609 accepts a short round from the peer); this is the same fix for a client
/// built on mbedTLS. Every reader turns the length-prefixed scalar into an integer, so a padded
/// scalar is still read correctly by a peer that writes minimal length (F23).
///
/// Layout (each `opaque<1..255>` is a one-byte length and that many bytes):
/// - ECJPAKEKeyKP = ECPoint X, ECSchnorrZKP { ECPoint V, opaque r };
/// - round 1 = two KeyKPs; client round 2 = one KeyKP; server round 2 = ECParameters (3 bytes)
///   then one KeyKP.
enum JpakeRound {
    enum DecodeError: Error, Equatable { case truncated(at: Int) }

    /// A P-256 scalar is 32 bytes.
    static let scalarLength = 32
    /// One KeyKP with an uncompressed point and a full-length scalar: (1 + 65) * 2 + 1 + 32.
    static let keyKPLength = 165
    /// The server's round-2 ECParameters: named_curve (3), secp256r1 (0x0017).
    static let ecParametersLength = 3

    struct KeyKP: Equatable {
        var x: [UInt8]
        var v: [UInt8]
        var r: [UInt8]

        /// Re-encodes with `r` left-padded with zeroes to `scalarLength`. A longer `r` is left as
        /// it is: mbedTLS never writes one, and stripping bytes would change the value.
        var encoded: [UInt8] {
            let padded =
                r.count < JpakeRound.scalarLength
                ? [UInt8](repeating: 0, count: JpakeRound.scalarLength - r.count) + r : r
            return [UInt8(x.count)] + x + [UInt8(v.count)] + v + [UInt8(padded.count)] + padded
        }
    }

    /// Reads `count` KeyKPs starting at `offset`. Bytes after the last field are ignored, which is
    /// what lets a round framed in a zero-padded fixed-size cargo be read.
    static func keyKPs(_ bytes: [UInt8], count: Int, from offset: Int = 0) throws -> [KeyKP] {
        var p = offset
        func opaque() throws -> [UInt8] {
            guard p < bytes.count else { throw DecodeError.truncated(at: p) }
            let len = Int(bytes[p])
            guard len > 0, p + 1 + len <= bytes.count else { throw DecodeError.truncated(at: p) }
            defer { p += 1 + len }
            return Array(bytes[(p + 1)..<(p + 1 + len)])
        }
        var out: [KeyKP] = []
        for _ in 0..<count {
            let x = try opaque()
            let v = try opaque()
            let r = try opaque()
            out.append(KeyKP(x: x, v: v, r: r))
        }
        return out
    }

    /// A round 1 (ours from mbedTLS, or the pump's two halves joined) as two full-length KeyKPs.
    static func roundOne(_ bytes: [UInt8]) throws -> [KeyKP] { try keyKPs(bytes, count: 2) }

    /// A round 2 re-encoded with a full-length scalar; `server` rounds keep their ECParameters.
    static func normalizedRoundTwo(_ bytes: [UInt8], server: Bool) throws -> [UInt8] {
        let prefix = server ? ecParametersLength : 0
        guard bytes.count >= prefix else { throw DecodeError.truncated(at: 0) }
        let kp = try keyKPs(bytes, count: 1, from: prefix)[0]
        return Array(bytes[0..<prefix]) + kp.encoded
    }
}
