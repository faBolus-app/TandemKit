import Testing
import Foundation
@testable import TandemMessages

/// Oracle byte-parity must fail closed when the oracle is unavailable. Default/CI/release runs
/// require JDK 21 + `cliparser.jar`; `PUMPX2_ALLOW_ORACLE_SKIP` is a local Swift-only opt-out and
/// must never be set in CI. This suite also proves the oracle process actually executed.
@Suite struct OracleAvailabilityGateTests {

    /// Default runs require the oracle. `PUMPX2_ALLOW_ORACLE_SKIP=1` is local Swift-only iteration
    /// only — CI / release must never set it.
    @Test func oracleRequiredUnlessDevModeOptOut() {
        if OracleRunner.isAvailable { return }
        let devMode = ProcessInfo.processInfo.environment["PUMPX2_ALLOW_ORACLE_SKIP"] == "1"
        #expect(
            devMode,
            """
            Oracle byte-parity is UNAVAILABLE (need JDK 21 + a built vendor/pumpx2-oracle cliparser.jar). \
            Default/CI/release runs must fail rather than silently skip parity for an insulin protocol. \
            Set PUMPX2_ALLOW_ORACLE_SKIP=1 ONLY for local Swift-only iteration.
            """)
    }

    /// A curated safety-critical message set must all byte-encode via the oracle when it is available,
    /// so a broken/no-op oracle cannot masquerade as coverage.
    @Test(.enabled(if: OracleRunner.isAvailable))
    func safetyCriticalMessagesRunAgainstOracle() throws {
        let names = [
            "ApiVersionRequest", "CancelBolusRequest", "SuspendPumpingRequest",
            "ResumePumpingRequest", "PlaySoundRequest", "BolusPermissionRequest"
        ]
        var encoded = 0
        for name in names {
            let packets = try OracleRunner.encodePackets(txId: 1, messageName: name)
            #expect(!packets.isEmpty, "\(name): oracle produced no packets")
            encoded += 1
        }
        #expect(encoded == names.count, "every curated safety message must encode against the oracle")
    }

    /// D-03 anti-vacuity: `oracleRequiredUnlessDevModeOptOut` above short-circuits on
    /// `isAvailable == true`, so on a JDK-21 host it never exercises the below-21 branch at all.
    /// These two cases assert the pure version-decision logic directly with concrete literal
    /// inputs, so they run (and can fail) on EVERY host regardless of which JVM is installed.
    @Test func javaMajorVersionParsingIsCorrect() {
        // Modern quoted-version shapes.
        #expect(OracleRunner.parseJavaMajorVersion(from: #"openjdk version "21.0.12.1" 2026-08-18"#) == 21)
        #expect(
            OracleRunner.parseJavaMajorVersion(
                from: "openjdk version \"11.0.23\" 2024-04-16 LTS\nOpenJDK Runtime Environment Corretto-11.0.23.9.1"
            ) == 11)
        #expect(OracleRunner.parseJavaMajorVersion(from: #"openjdk version "14.0.2" 2020-07-14"#) == 14)
        // Legacy `1.x` shape (pre-JEP-223 versioning): major is the SECOND component.
        #expect(OracleRunner.parseJavaMajorVersion(from: #"java version "1.8.0_401""#) == 8)
        // Unparseable input must resolve to nil, not a guessed default.
        #expect(OracleRunner.parseJavaMajorVersion(from: "") == nil)
        #expect(OracleRunner.parseJavaMajorVersion(from: "not a java version string") == nil)
    }

    /// The >=21 boundary that makes "present-but-wrong JVM" detectable. Asserts BOTH sides so this
    /// fails if `minimumJavaMajor` is ever loosened below 21.
    @Test func subTwentyOneJvmIsUnsupported() {
        #expect(!OracleRunner.isSupportedJavaMajor(11))
        #expect(!OracleRunner.isSupportedJavaMajor(20))
        #expect(OracleRunner.isSupportedJavaMajor(21))
        #expect(OracleRunner.isSupportedJavaMajor(22))
    }
}
