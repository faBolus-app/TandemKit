import Testing
import PumpX2Messages
@testable import PumpX2Auth

@Suite struct CryptoTests {
    // Known-answer vectors captured from the cliparser oracle (`hmac-sha256`, `hkdf`).
    @Test func hmacSha256KnownAnswer() throws {
        let out = Crypto.hmacSha256(data: try Hex.decode("01020304"), key: try Hex.decode("0a0b0c0d"))
        #expect(Hex.encode(out) == "a0ab311e66ff4ca8d5fa7b60597d93637b3fb86f3ce9a01ceee118a4bf143af2")
    }

    @Test func hkdfKnownAnswer() throws {
        let out = Crypto.hkdf(nonce: try Hex.decode("0011223344556677"),
                              keyMaterial: try Hex.decode("aabbccddeeff"))
        #expect(Hex.encode(out) == "23babb413e58519c975ff4c28f980d11a2051341ca3a67a7ea4394e5c88c1250")
    }

    // Standard RFC/well-known HMAC-SHA1 vector.
    @Test func hmacSha1KnownAnswer() {
        let key = Array("key".utf8)
        let data = Array("The quick brown fox jumps over the lazy dog".utf8)
        #expect(Hex.encode(Crypto.hmacSha1(data: data, key: key))
            == "de7c9b85b8b78aa6bc8a7a36f70a90701c9db4d9")
    }
}

@Suite struct PairingAuthTests {
    @Test func validLongCodes() throws {
        for code in ["abcdefghijklmnop", "abcd-efgh-ijkl-mnop", "abcd-1234-ijkl-5678",
                     "abcd1234ijkl5678", "abcd-1234-ijkl 5678"] {
            #expect(throws: Never.self) { try PairingAuth.processPairingCode(code) }
        }
    }

    /// `.planning/debug/pump-pairing-loop.md`: owner tried the pump's 16-char code with and without
    /// dashes and observed the identical loop both ways — this pins the reason down as an EQUALITY,
    /// not just "both validate": dashed and undashed forms of the same code must canonicalize to the
    /// exact same 16-char string (so they produce the identical `CentralChallengeRequest` on the wire),
    /// ruling dash formatting itself out as a variable in that investigation.
    @Test func dashedAndUndashedLongCodesCanonicalizeIdentically() throws {
        let dashed = try PairingAuth.processPairingCode("1234-5678-9012-3456", type: .long16Char)
        let undashed = try PairingAuth.processPairingCode("1234567890123456", type: .long16Char)
        #expect(dashed == undashed)
        #expect(dashed == "1234567890123456")
    }

    @Test func invalidLongCodes() {
        #expect(throws: PairingAuth.PairingError.self) {
            try PairingAuth.processPairingCode("abcd-!fgh-ijkl-mnop")
        }
        #expect(throws: PairingAuth.PairingError.self) {
            try PairingAuth.processPairingCode("abcd!fghijklmnop")
        }
        #expect(throws: PairingAuth.PairingError.invalidLongPairingCode) {
            try PairingAuth.processPairingCode("123456", type: .long16Char)
        }
    }

    @Test func validShortCodes() throws {
        for code in ["123456", "123 456", "123-456", "123-789"] {
            #expect(throws: Never.self) { try PairingAuth.processPairingCode(code) }
        }
    }

    @Test func invalidShortCodes() {
        #expect(throws: PairingAuth.PairingError.invalidShortPairingCode) {
            try PairingAuth.processPairingCode("123", type: .short6Char)
        }
        #expect(throws: PairingAuth.PairingError.invalidShortPairingCode) {
            try PairingAuth.processPairingCode("1234567", type: .short6Char)
        }
        #expect(throws: PairingAuth.PairingError.invalidShortPairingCode) {
            try PairingAuth.processPairingCode("abcd-efgh-ijkl-mnop", type: .short6Char)
        }
    }

    /// V1 pairing hash: `PumpChallengeRequest.pumpChallengeHash` = HMAC-SHA1(hmacKey, pairingCode).
    @Test func createV1ComputesHash() throws {
        let hmacKey = try Hex.decode("00112233445566778899aabbccddeeff")
        let code = "abcd1234ijkl5678"
        let req = try PairingAuth.createV1(appInstanceId: 0, hmacKey: hmacKey, pairingCode: code)
        #expect(req.appInstanceId == 0)
        #expect(req.pumpChallengeHash == Crypto.hmacSha1(data: hmacKey, key: Array(code.utf8)))
        #expect(req.pumpChallengeHash.count == 20)
        #expect(req.cargo.count == 22)
    }

    /// Independent golden vector for `createV1` — the expected digest was computed OUTSIDE Swift
    /// (Python `hmac`/`hashlib`), so it pins the FULL path (pairing-code processing → HMAC argument
    /// order → digest) against a reference the app's own `Crypto.hmacSha1` cannot circularly satisfy.
    /// The self-check above compares two Swift computations, so a regression in `hmacSha1` (or the
    /// arg order flipping) would pass it; this vector would fail. Inputs: the upstream 16-char example
    /// code + the real pump `hmacKey` from jwoglom `CentralChallengeResponseTest` (840c4e16873046bc);
    /// `pumpChallengeHash = HMAC-SHA1(key = pairingCode UTF-8, data = hmacKey)`.
    @Test func createV1MatchesIndependentGolden() throws {
        let hmacKey = try Hex.decode("840c4e16873046bc")
        let req = try PairingAuth.createV1(appInstanceId: 1, hmacKey: hmacKey, pairingCode: "6VeDeRAL5DCigGw2")
        #expect(Hex.encode(req.pumpChallengeHash) == "e39aea1f3d120be8206d4bb728b54fd94ad02e54")
        #expect(req.appInstanceId == 1)
        #expect(req.pumpChallengeHash.count == 20)
    }
}
