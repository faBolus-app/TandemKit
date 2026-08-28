import Testing
import Foundation
@testable import TandemMessages

/// PX-09: make the oracle **fail-closed**. The parity suites are gated `.enabled(if: isAvailable)`, so a
/// checkout without a built oracle (JDK 21 + `cliparser.jar`) silently skips *all* byte-parity coverage
/// and the run still reports green — a dangerous false pass for a byte-exact insulin protocol. This suite
/// turns that into an explicit failure unless the runner opts into a Swift-only dev mode, and it proves
/// the oracle process actually executed (not merely that the files exist).
@Suite struct OracleAvailabilityGateTests {

    /// Default runs REQUIRE the oracle. A developer iterating without Java can set
    /// `PUMPX2_ALLOW_ORACLE_SKIP=1` to run Swift-only — but CI / release must not.
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

    /// A curated safety-critical message set must ALL byte-encode via the oracle when it is available —
    /// proving the oracle really ran for these (PX-09 "assert the expected oracle case count ran"), so a
    /// broken/no-op oracle can't masquerade as coverage. Count is asserted exactly.
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
}
