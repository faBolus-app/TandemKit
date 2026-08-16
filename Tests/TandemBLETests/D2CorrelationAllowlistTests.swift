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
}
