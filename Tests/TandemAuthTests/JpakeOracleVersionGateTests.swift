import Testing
import Foundation
@testable import TandemAuth

/// `JpakeOracle.available` (a SECOND, independent copy of `OracleRunner`'s version gate) must
/// refuse a present-but-too-old JVM rather than let the EC-JPAKE interop suite run against a
/// class file it cannot load. This suite is ALWAYS RUN — no `.enabled(if:)` — so the pure
/// version-decision logic is exercised (and can fail) on EVERY host regardless of which JVM is
/// installed, mirroring `OracleAvailabilityGateTests.javaMajorVersionParsingIsCorrect` /
/// `subTwentyOneJvmIsUnsupported`.
@Suite struct JpakeOracleVersionGateTests {

    @Test func javaMajorVersionParsingIsCorrect() {
        // Modern quoted-version shapes.
        #expect(JpakeOracle.parseJavaMajorVersion(from: #"openjdk version "21.0.12.1" 2026-08-18"#) == 21)
        #expect(
            JpakeOracle.parseJavaMajorVersion(
                from: "openjdk version \"11.0.23\" 2024-04-16 LTS\nOpenJDK Runtime Environment Corretto-11.0.23.9.1"
            ) == 11)
        #expect(JpakeOracle.parseJavaMajorVersion(from: #"openjdk version "14.0.2" 2020-07-14"#) == 14)
        // Legacy `1.x` shape (pre-JEP-223 versioning): major is the SECOND component.
        #expect(JpakeOracle.parseJavaMajorVersion(from: #"java version "1.8.0_401""#) == 8)
        // Unparseable input must resolve to nil, not a guessed default.
        #expect(JpakeOracle.parseJavaMajorVersion(from: "") == nil)
        #expect(JpakeOracle.parseJavaMajorVersion(from: "not a java version string") == nil)
    }

    /// The >=21 boundary that makes "present-but-wrong JVM" detectable. Asserts BOTH sides so
    /// this fails if `minimumJavaMajor` is ever loosened below 21.
    @Test func subTwentyOneJvmIsUnsupported() {
        #expect(!JpakeOracle.isSupportedJavaMajor(11))
        #expect(!JpakeOracle.isSupportedJavaMajor(20))
        #expect(JpakeOracle.isSupportedJavaMajor(21))
        #expect(JpakeOracle.isSupportedJavaMajor(22))
    }
}
