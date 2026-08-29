import Testing
import Foundation
import TandemMessages
@testable import TandemAuth

/// Round-4 key confirmation must compare HMAC-SHA256 digests with CryptoKit's constant-time
/// `isValidAuthenticationCode`, not Array `==` (which short-circuits). The source-scan guard fails
/// if a short-circuiting compare is reintroduced; the behavioral tests pin that a wrong digest still throws.
@Suite struct JpakeConstantTimeGuardTests {

    // MARK: - Source resolution (mirrors D2CorrelationAllowlistTests' #filePath-rooted pattern)

    private static func repoRootURL() -> URL? {
        let fm = FileManager.default
        var probe = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = probe.appendingPathComponent("Sources/TandemAuth/JpakeAuth.swift")
            if fm.fileExists(atPath: candidate.path) { return probe }
            probe = probe.deletingLastPathComponent()
        }
        return nil
    }

    private static func readSource(_ relativePath: String) -> String? {
        guard let root = repoRootURL() else { return nil }
        return try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Source-scan guard

    /// `verifyServerRound4` must not use a short-circuiting Array `==`/`!=` compare against the
    /// server's digest, and must route through the constant-time primitive. Scans the real
    /// `JpakeAuth.swift` source so a reintroduced short-circuit fails here even if behavioral tests still pass.
    @Test func verifyServerRound4UsesConstantTimeCompareStructuralGuard() throws {
        guard let source = Self.readSource("Sources/TandemAuth/JpakeAuth.swift") else {
            Issue.record("could not resolve JpakeAuth.swift from #filePath=\(#filePath)")
            return
        }
        guard let bodyRange = source.range(of: "func verifyServerRound4") else {
            Issue.record("verifyServerRound4 not found in JpakeAuth.swift")
            return
        }
        // Isolate just this function's body (up to the next top-level `func`/closing brace of
        // reasonable size) so the guard can't be satisfied by unrelated code elsewhere in the file.
        let tail = source[bodyRange.lowerBound...]
        let bodyEnd = tail.range(of: "\n    static func randomBytes")?.lowerBound ?? tail.endIndex
        let body = String(tail[tail.startIndex..<bodyEnd])

        #expect(
            !body.contains("== serverHashDigest"),
            "verifyServerRound4 must not use short-circuiting Array `==` on the digest (timing side-channel)")
        #expect(
            !body.contains("!= serverHashDigest"),
            "verifyServerRound4 must not use short-circuiting Array `!=` on the digest (timing side-channel)")
        #expect(
            body.contains("isValidHmacSha256") || body.contains("isValidAuthenticationCode"),
            "verifyServerRound4 must route through a constant-time comparison primitive")
    }

    // MARK: - Behavioral safety net

    /// Handshake setup reused to pin that a correct digest still verifies and a wrong digest
    /// (flipped, truncated, or over-length) still throws `keyConfirmationFailed`.
    private func makeAuthenticatedPair() throws -> (auth: JpakeAuth, serverSecret: [UInt8], serverNonce3: [UInt8]) {
        let auth = try JpakeAuth(pairingCode: "123456")
        let server = try EcJpakeContext(role: .server, secret: JpakeAuth.pairingCodeToBytes("123456"))
        let (r1a, r1b) = try auth.makeRound1Requests()
        let sR1 = try server.writeRoundOne()
        try server.readRoundOne(r1a.centralChallenge + r1b.centralChallenge)
        let mid = sR1.count / 2
        try auth.readServerRound1(challenge1a: Array(sR1[0..<mid]), challenge1b: Array(sR1[mid...]))
        let r2 = try auth.makeRound2Request()
        let sR2 = try server.writeRoundTwo()
        try server.readRoundTwo(r2.centralChallenge)
        try auth.readServerRound2(challenge: sR2)
        _ = try auth.derive()
        let serverSecret = try server.deriveSecret()

        let serverNonce3 = JpakeAuth.randomBytes(8)
        _ = auth.makeRound4Request(serverNonce3: serverNonce3)
        return (auth, serverSecret, serverNonce3)
    }

    @Test func correctServerDigestVerifies() throws {
        let (auth, serverSecret, serverNonce3) = try makeAuthenticatedPair()
        let serverNonce4 = JpakeAuth.randomBytes(8)
        let serverHash = Crypto.hmacSha256(
            data: serverNonce4, key: Crypto.hkdf(nonce: serverNonce3, keyMaterial: serverSecret))
        #expect(throws: Never.self) {
            try auth.verifyServerRound4(serverNonce4: serverNonce4, serverHashDigest: serverHash)
        }
    }

    @Test func singleByteFlippedDigestThrowsKeyConfirmationFailed() throws {
        let (auth, serverSecret, serverNonce3) = try makeAuthenticatedPair()
        let serverNonce4 = JpakeAuth.randomBytes(8)
        var serverHash = Crypto.hmacSha256(
            data: serverNonce4, key: Crypto.hkdf(nonce: serverNonce3, keyMaterial: serverSecret))
        serverHash[0] ^= 0xFF  // flip one byte — same length, wrong digest
        #expect(throws: JpakeAuth.JpakeAuthError.keyConfirmationFailed) {
            try auth.verifyServerRound4(serverNonce4: serverNonce4, serverHashDigest: serverHash)
        }
    }

    @Test func truncatedDigestThrowsKeyConfirmationFailedWithoutCrashing() throws {
        let (auth, serverSecret, serverNonce3) = try makeAuthenticatedPair()
        let serverNonce4 = JpakeAuth.randomBytes(8)
        let fullHash = Crypto.hmacSha256(
            data: serverNonce4, key: Crypto.hkdf(nonce: serverNonce3, keyMaterial: serverSecret))
        let truncated = Array(fullHash.prefix(fullHash.count - 4))
        #expect(throws: JpakeAuth.JpakeAuthError.keyConfirmationFailed) {
            try auth.verifyServerRound4(serverNonce4: serverNonce4, serverHashDigest: truncated)
        }
    }

    @Test func overLengthDigestThrowsKeyConfirmationFailedWithoutCrashing() throws {
        let (auth, serverSecret, serverNonce3) = try makeAuthenticatedPair()
        let serverNonce4 = JpakeAuth.randomBytes(8)
        var overLength = Crypto.hmacSha256(
            data: serverNonce4, key: Crypto.hkdf(nonce: serverNonce3, keyMaterial: serverSecret))
        overLength.append(contentsOf: [0x00, 0x01, 0x02, 0x03])
        #expect(throws: JpakeAuth.JpakeAuthError.keyConfirmationFailed) {
            try auth.verifyServerRound4(serverNonce4: serverNonce4, serverHashDigest: overLength)
        }
    }
}
