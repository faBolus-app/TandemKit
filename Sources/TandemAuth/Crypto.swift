import Foundation
import CryptoKit

/// Crypto primitives for pump authentication. Ports of
/// `builders/crypto/{HmacSha256,Hkdf}` and the HMAC-SHA1 used for pairing/signing.
///
/// Verified against the cliparser oracle's `hmac-sha256` and `hkdf` subcommands.
public enum Crypto {
    /// HMAC-SHA256(data, key). (Upstream's `mod255` normalization is a no-op on bytes, so this
    /// is a standard HMAC-SHA256.)
    public static func hmacSha256(data: [UInt8], key: [UInt8]) -> [UInt8] {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(data), using: SymmetricKey(data: Data(key)))
        return [UInt8](mac)
    }

    /// HMAC-SHA1(data, key). Same primitive `Packetize` uses for signing.
    public static func hmacSha1(data: [UInt8], key: [UInt8]) -> [UInt8] {
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(data), using: SymmetricKey(data: Data(key)))
        return [UInt8](mac)
    }

    /// HKDF-SHA256 as implemented upstream (`Hkdf.build`): extract with salt = `nonce`,
    /// IKM = `keyMaterial`, empty info, output length 32.
    ///
    /// = HMAC-SHA256(key = HMAC-SHA256(key = nonce, data = keyMaterial), data = [0x01]).
    public static func hkdf(nonce: [UInt8], keyMaterial: [UInt8]) -> [UInt8] {
        // An empty key becomes 32 zero bytes (matches upstream `newSecretKeySpec`).
        let salt = nonce.isEmpty ? [UInt8](repeating: 0, count: 32) : nonce
        let prk = hmacSha256(data: keyMaterial, key: salt)
        // expand: single 32-byte block, info empty, block index 1.
        return hmacSha256(data: [0x01], key: prk)
    }

    /// Constant-time HMAC-SHA256 verification: `mac == HMAC-SHA256(data, key)`.
    ///
    /// Used where an attacker-observable HMAC comparison is on an auth path (e.g. JPAKE round-4
    /// key confirmation) — comparing digests with Array `==` short-circuits on the first
    /// mismatching byte, a timing side-channel. `HMAC<SHA256>.isValidAuthenticationCode` performs
    /// a constant-time comparison by CryptoKit contract, returning `false` (never crashing) on any
    /// mismatch including a wrong-length `mac`. Matches the fix upstream jwoglom/pumpX2 applied in
    /// PR #102 (Java `MessageDigest.isEqual`) for the same comparison.
    public static func isValidHmacSha256(mac: [UInt8], data: [UInt8], key: [UInt8]) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(
            Data(mac),
            authenticating: Data(data),
            using: SymmetricKey(data: Data(key)))
    }
}
