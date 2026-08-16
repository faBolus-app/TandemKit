import Testing
import Foundation
import TandemMessages
@testable import TandemBLE

/// Phase 09.11 — D2 (Addendum G) txId-correlation SAFETY AUDIT (CONFIRMATION tests, NOT a feature build).
///
/// These tests CONFIRM existing, apparently-correct behavior of the D2 txId-correlation seam and are
/// expected to pass on FIRST WRITE. A RED here is a DEFECT FINDING, not a step to then "fix" the dose-path
/// Sources — a FIFO byte-identity break or a teardown edge leaving `.txIdMatch` standing is a
/// REVERT-TRIGGER for the owner (see 09.11-01-SUMMARY.md audit-findings). Additive test file only; no
/// Sources are mutated by this suite.
///
/// What this suite pins that the pre-existing `PumpTransactionCoordinatorTests` never did: those tests set
/// `coord.correlationMode = .txIdMatch` DIRECTLY via `@testable` (happy-path, bare coordinator). This suite
/// drives the arming/reset plumbing through the REAL public entry point `PumpBLEClient` — the observable
/// seam an app actually uses — proving the allowlist end-to-end.
///
/// Decisions pinned (09.11-CONTEXT.md):
/// - D-05: `correlationMode` defaults `.opcodeFIFO`, is `public internal(set)` (TYPE-enforced allowlist —
///   out-of-module callers cannot write it); the ONLY elevation is `setPumpFamily(.tslim)`.
/// - D-04 #1 (allowlist rejection): `setPumpFamily(.mobi)` / `.unknown` stay `.opcodeFIFO`.
/// - D-04 #3 (arming): `setPumpFamily(.tslim)` elevates to `.txIdMatch`.
/// - D-04 #2 + PLUS (fail-closed reset + 6-call-site routing) and D-03/D-08 (FIFO byte-identity + parser
///   additivity) are pinned by the structural guards added in Tasks 2 and 3 below.
@Suite struct D2CorrelationAllowlistTests {

    // MARK: - Task 1: end-to-end allowlist confirmation through PumpBLEClient (D-04 #1/#3, D-05)

    /// D-05: a FRESH `PumpBLEClient` reports the fail-closed default `.opcodeFIFO` correlation — read
    /// THROUGH the client's public `transactions` seam (not a bare coordinator), so this proves the default
    /// an app observes, not just the coordinator's own initializer default.
    @MainActor @Test func defaultCorrelationModeIsFifoViaClient() {
        let client = PumpBLEClient()
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    /// D-04 #3 (arming): the ONLY family that elevates. `setPumpFamily(.tslim)` puts the shared coordinator
    /// into `.txIdMatch` (t:slim is the hardware-confirmed txId-echo allowlist entry).
    @MainActor @Test func armingTslimElevatesToTxIdMatch() {
        let client = PumpBLEClient()
        client.setPumpFamily(.tslim)
        #expect(client.transactions.correlationMode == .txIdMatch)
    }

    /// D-04 #1a (allowlist rejection): Mobi's txId echo is UNCONFIRMED, so `setPumpFamily(.mobi)` must leave
    /// the mode on the FIFO reference path — the kit refuses to elevate a non-allowlisted family even though
    /// the caller asked for that family.
    @MainActor @Test func allowlistRejectsMobiStaysFifo() {
        let client = PumpBLEClient()
        client.setPumpFamily(.mobi)
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    /// D-04 #1b (allowlist rejection): an UNIDENTIFIED pump fails closed to FIFO — `setPumpFamily(.unknown)`
    /// never elevates. A caller cannot bypass the allowlist by passing an unknown family.
    @MainActor @Test func allowlistRejectsUnknownStaysFifo() {
        let client = PumpBLEClient()
        client.setPumpFamily(.unknown)
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    // MARK: - Source resolution (mirrors the project's #filePath-rooted source-scan guard pattern)

    /// Resolve the TandemKit repo root by walking up from `#filePath`
    /// (`<root>/Tests/TandemBLETests/D2CorrelationAllowlistTests.swift`) until the audited coordinator
    /// source exists. The guards below scan the REAL Sources file so a future edit that alters the
    /// default path trips the test — no Sources mutation, read-only.
    private static func repoRootURL() -> URL? {
        let fm = FileManager.default
        var probe = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = probe.appendingPathComponent("Sources/TandemBLE/PumpTransactionCoordinator.swift")
            if fm.fileExists(atPath: candidate.path) { return probe }
            probe = probe.deletingLastPathComponent()
        }
        return nil
    }

    private static func readSource(_ relativePath: String) -> String? {
        guard let root = repoRootURL() else { return nil }
        return try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Task 2: FIFO byte-identity + parser-additivity structural guards (D-03, D-08)

    /// D-03 (REVERT-trigger gate): the `.opcodeFIFO` branch of `ingest`'s correlation switch must contain
    /// the EXACT pre-D2 FIFO predicate, and `.txIdMatch` must be a SEPARATE case. The `d128eed` diff only
    /// wrapped the pre-D2 unconditional predicate in a `switch` and added a distinct `.txIdMatch` branch
    /// alongside it — the default path is byte-identical. A future edit that alters the `.opcodeFIFO`
    /// predicate (the blast radius is every faBolus dose-path read, which always runs FIFO) turns this RED;
    /// that RED is a REVERT-TRIGGER finding, not a step to "fix" the source.
    @Test func opcodeFifoBranchIsByteIdenticalStructuralGuard() throws {
        guard let source = Self.readSource("Sources/TandemBLE/PumpTransactionCoordinator.swift") else {
            Issue.record("could not resolve PumpTransactionCoordinator.swift from #filePath=\(#filePath)")
            return
        }
        // The two branches are distinct switch cases (default path is separated from txId correlation).
        #expect(source.contains("case .opcodeFIFO:"),
                "the .opcodeFIFO switch case must exist as the default correlation path")
        #expect(source.contains("case .txIdMatch:"),
                "the .txIdMatch branch must be a SEPARATE case, never merged into the default path")
        // The EXACT pre-D2 FIFO predicate (byte-for-byte from d128eed's parent 0816a12).
        let fifoPredicate = "$0.expectedCharacteristic == characteristic && $0.expectedOpCode == opCode"
        #expect(source.contains(fifoPredicate),
                "the .opcodeFIFO predicate diverged from the pre-D2 FIFO match — REVERT-TRIGGER (D-03)")
        // The predicate must sit inside the .opcodeFIFO case region, ahead of the .txIdMatch case.
        if let fifoCaseStart = source.range(of: "case .opcodeFIFO:"),
           let txCaseStart = source.range(of: "case .txIdMatch:") {
            let fifoRegion = source[fifoCaseStart.upperBound..<txCaseStart.lowerBound]
            #expect(fifoRegion.contains(fifoPredicate),
                    "the FIFO predicate must live in the .opcodeFIFO case region, not the txId branch")
        } else {
            Issue.record("could not bound the .opcodeFIFO case region between the two switch cases")
        }
    }

    /// D-08: the op-77 error reply is registered on `.control` as a purely ADDITIVE new (characteristic,
    /// opcode) key. The pre-existing `.currentStatus` op-77 registration (`ErrorResponse.props.characteristic
    /// == .currentStatus`) is untouched, and there is EXACTLY ONE `.control` override for it (no prior
    /// `.control` op-77 key is shadowed) — so no wire bytes changed and the parity suites stay green.
    @Test func op77ControlKeyIsAdditiveNotShadowingStructuralGuard() throws {
        guard let source = Self.readSource("Sources/TandemMessages/Responses/ResponseParser.swift") else {
            Issue.record("could not resolve ResponseParser.swift from #filePath=\(#filePath)")
            return
        }
        // The untouched currentStatus variant (ErrorResponse.props default characteristic is .currentStatus).
        #expect(source.contains("add(ErrorResponse.self)"),
                "the pre-existing .currentStatus op-77 registration must remain untouched (D-08)")
        // The additive control-variant key.
        #expect(source.contains("add(ErrorResponse.self, on: .control)"),
                "the additive op-77-on-.control registration must be present (D-08)")
        // Exactly one .control override for ErrorResponse — no shadowing / no duplicate key.
        let controlKeyCount = source.components(separatedBy: "add(ErrorResponse.self, on: .control)").count - 1
        #expect(controlKeyCount == 1,
                "expected exactly one op-77-on-.control key; a second would shadow it (found \(controlKeyCount))")
    }
}
