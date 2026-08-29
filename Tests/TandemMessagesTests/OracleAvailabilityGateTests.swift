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
}
