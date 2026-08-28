import Foundation
import TandemMessages

/// The two legacy pairing code formats. Port of `models/PairingCodeType`.
/// - LONG_16CHAR: t:slim X2 before firmware v7.7 (alphanumeric).
/// - SHORT_6CHAR: t:slim X2 v7.7+ (6 digits, used with JPAKE).
public enum PairingCodeType: String, Sendable {
    case long16Char = "LONG_16CHAR"
    case short6Char = "SHORT_6CHAR"

    /// Strips separators/invalid characters. LONG keeps [A-Za-z0-9]; SHORT keeps [0-9].
    public func filterCharacters(_ pairingCode: String) -> String {
        pairingCode.filter { c in
            switch self {
            case .long16Char: return c.isLetter && c.isASCII || (c.isNumber && c.isASCII)
            case .short6Char: return c.isNumber && c.isASCII
            }
        }
    }
}

/// Legacy (V1 / 16-char) pairing handshake helper. Port of the V1 path of
/// `builders/PumpChallengeRequestBuilder`.
///
/// The V2 (JPAKE / 6-digit) path is NOT implemented here — it requires an elliptic-curve
/// J-PAKE implementation (upstream uses `io.particle.crypto.EcJpake`). See `JpakeAuth`.
public enum PairingAuth {
    public enum PairingError: Error, Equatable {
        case invalidLongPairingCode
        case invalidShortPairingCode
        case invalidType
    }

    /// Validates + normalizes a pairing code to the given type's canonical form.
    public static func processPairingCode(_ pairingCode: String, type: PairingCodeType) throws -> String {
        switch type {
        case .long16Char:
            let p = type.filterCharacters(pairingCode)
            guard p.count == 16 else { throw PairingError.invalidLongPairingCode }
            return p
        case .short6Char:
            let p = type.filterCharacters(pairingCode)
            guard p.count == 6 else { throw PairingError.invalidShortPairingCode }
            return p
        }
    }

    /// Auto-detects the type (6-digit → SHORT, else LONG) and normalizes. Mirrors the upstream
    /// `PumpChallengeRequestBuilder.processPairingCode(_:)` heuristic exactly (kept for parity).
    public static func processPairingCode(_ pairingCode: String) throws -> String {
        if pairingCode.count == 6 || PairingCodeType.short6Char.filterCharacters(pairingCode).count == 6 {
            return try processPairingCode(pairingCode, type: .short6Char)
        }
        return try processPairingCode(pairingCode, type: .long16Char)
    }

    /// Selects the pairing SCHEME for a code without validating it — used to pick the right pairing
    /// coordinator (JPAKE for `.short6Char`, legacy V1 for `.long16Char`).
    ///
    /// This is a safety-hardened variant of the upstream auto-detect above: a 16-char alphanumeric
    /// code that happens to contain exactly 6 digits would be MISCLASSIFIED as `.short6Char` by the
    /// upstream heuristic (which keys on "6 digits present"), selecting the wrong (JPAKE) handshake
    /// and causing a confusing pairing failure. Here, a code whose alphanumeric length is 16 is
    /// always `.long16Char`; only a purely-numeric 6-digit code is `.short6Char`. On every input the
    /// upstream heuristic classifies unambiguously (including all of its own test vectors) this
    /// returns the same answer. The chosen coordinator's `init` still validates the exact format and
    /// throws on a malformed code, so detection is only a routing hint, never a correctness gate.
    public static func detectType(_ pairingCode: String) -> PairingCodeType {
        let alnum = PairingCodeType.long16Char.filterCharacters(pairingCode)
        let digits = PairingCodeType.short6Char.filterCharacters(pairingCode)
        if alnum.count == 16 { return .long16Char }                    // unambiguous: 16 alphanumeric
        if digits.count == 6 && alnum.count == 6 { return .short6Char } // purely-numeric 6-digit
        // Fall back to the upstream heuristic for anything else.
        if pairingCode.count == 6 || digits.count == 6 { return .short6Char }
        return .long16Char
    }

    /// V1 pairing: given the pump's `hmacKey` (from CentralChallengeResponse), the
    /// `appInstanceId`, and the 16-char pairing code, produces the `PumpChallengeRequest`.
    ///
    /// The hash is `HMAC-SHA1(data = hmacKey, key = pairingCode UTF-8 bytes)` (note the
    /// argument order — the pairing code is the HMAC key), matching `createV1`.
    public static func createV1(
        appInstanceId: Int,
        hmacKey: [UInt8],
        pairingCode: String
    ) throws -> PumpChallengeRequest {
        let pairingChars = try processPairingCode(pairingCode, type: .long16Char)
        let challengeHash = Crypto.hmacSha1(data: hmacKey, key: Array(pairingChars.utf8))
        return PumpChallengeRequest(appInstanceId: appInstanceId, pumpChallengeHash: challengeHash)
    }
}
