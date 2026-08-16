# D2 (BLE txId-correlation) — §1.4 Promotion-Readiness Dossier

**Feature:** D2 — "txId response correlation behind a fail-closed t:slim allowlist" (Addendum G)
**Introducing commit:** `d128eed` (experimental)
**Status today:** `experimental` / **default-off**
**Governed by:** `../faBolus/BRANCHES.md` §1.4 (the promotion criteria are canonical there; this repo's
`BRANCHES.md` is a pointer stub — see §1.4-6 through §1.4-7 quotes inlined below for convenience).

This dossier is the **pre-staged promotion package** the owner directed (D-06, 2026-08-16): it does **not**
promote D2 now (one criterion is still bench-blocked). Its purpose is to make the eventual promotion a
one-step, evidence-backed action the moment the Phase-11 saline bench clears, and to record — rather than
paper over — the governance fact that D2 reached `main` outside the §1.4 gate in the first place.

## Governance context — how D2 got to `main` outside the gate

Per `../faBolus/BRANCHES.md:134-143`: PR #16's squash-merge carried **D2** (`d128eed`) onto TandemKit `main`
in the **same commit** as D3 (the `Package.swift` `.unsafeFlags → .define` crypto fix) — D2 did not
independently clear the §1.4 promotion gate above. The owner's pin-current-main decision (2026-08-13,
`.planning/phases/03-pumpx2kit-version-pin/03-01-SUMMARY.md`) accepted this on the grounds that D2 is
opt-in/fail-closed (`correlationMode` defaults `.opcodeFIFO`, `internal(set)`, only elevated by
`setPumpFamily(.tslim)`, which faBolus never calls) and was squash-cherry-picked such that no `main` SHA
exists with D3 but not D2. faBolus's revision pin therefore formally consumes D2's code even though faBolus
never exercises the elevated path. **D2's own §1.4 promotion status remained the owner's separate
concern** — the pin did not retroactively promote it. This Phase 09.11 audit (Plans 01–02) and this dossier
(Plan 03) are that separate concern being resolved: not by promoting D2 outright, but by running the
missing §1.4 gate checks and pre-staging the promotion package.

D2 content is now on `origin/main` (`82c6241`, via the 09.12 rename to `TandemKit`) and pinned by faBolus at
`6efdd43`. It has never been marked verified, and real-insulin use with D2's elevated `.txIdMatch` mode
remains **NO-GO** pending the Phase-11 bench.

## §1.4 criteria walk — status + cited evidence

| # | Criterion (verbatim, `BRANCHES.md` §1.4) | Status | Evidence |
|---|---|---|---|
| 1 | **Verifiable or clearly bounded.** Either its output can be checked against the pump, or presented as advisory with that limitation stated. | 🟡 **OPEN (bench)** | D2's correlation is bounded to concurrent **reads only** — the load-bearing safety invariant, delivery serialization (`PumpTransactionCoordinator.perform` rejects a second in-flight serialized command regardless of `correlationMode`), is preserved in **both** modes and pinned by the pre-existing `txIdMatchStillSerializesDelivery` test. What is *not yet independently verified against the real pump* is the pipelined-bijection claim itself (two concurrent same-opcode reads resolving by txId, not by issue order) — that is exactly what the Phase-11 saline bench (`txIdMatchProbe`, `Tests/TandemHardwareTests/BenchCases.swift:211-244`) measures, read-only, against live hardware. This is the **sole open criterion** — see below. |
| 2 | **Default-off preserved if it automates.** Ships default-off on `main` too, with a one-time plain-language explanation. | ✅ **MET** | `correlationMode` defaults `.opcodeFIFO` and is `public internal(set)` (`PumpTransactionCoordinator.swift:73`) — type-enforced, not conventional: out-of-module callers (including faBolus) cannot write it. The **only** elevation path is `setPumpFamily(iff family == .tslim)` (`PumpBLEClient.swift:184-185`); `.mobi`/`.unknown` stay `.opcodeFIFO`. faBolus never calls `setPumpFamily`, so D2 is inert on the app and on `main` today. Confirmed end-to-end through the public `PumpBLEClient` entry point (not just the coordinator default) by Plan 01's `defaultCorrelationModeIsFifoViaClient`, `armingTslimElevatesToTxIdMatch`, `allowlistRejectsMobiStaysFifo`, `allowlistRejectsUnknownStaysFifo` (D-05). |
| 3 | **CI-green on the real toolchain**, across every surface it touches. | ✅ **MET** | Full TandemKit suite green on both audit plans: Plan 01 landed at **289 tests / 33 suites**; Plan 02 (adding the 6 adversarial tests) at **295 tests / 34 suites** — including `ResponseParityTests` (39) and `OracleParityTests` (56), the byte-parity suites that would catch any wire-format regression. Merge-after-green-CI is the repo's standing merge discipline. |
| 4 | **Tests pin the behaviour**, including the failure/edge path, not only the happy path. | ✅ **MET** | The original D2 PR only covered the happy path (existing `PumpTransactionCoordinatorTests` set `.txIdMatch` directly via `@testable`, never exercising `setPumpFamily`/`failClosed`). This audit added the **8 missing failure-path/adversarial cases** (D-04) across two additive suites — see the dedicated table below. |
| 5 | **No new capability inferred where the pump already answers it** — read the pump, don't model it. | ✅ **MET** | txId is **read** from the pump's own echoed response frame (`frame[1]`) — it is not modeled, guessed, or derived; the pump supplies the correlating fact directly. |
| 6 | **Clinical review** is complete for any feature touching dosing guidance, thresholds, or automation copy. | ✅ **N/A** (owner ruling D-07, 2026-08-16, binding) | D2 txId correlation is a **transport-layer response-attribution seam** — "which pump response belongs to which in-flight request" — not "dosing guidance, thresholds, or automation copy" (the literal §1.4-6 scope). It does not surface any UI copy, does not compute a dose, and does not set a threshold. The owner ruled this criterion N/A for D2 specifically (`.planning/OWNER-DECISIONS.md` "## 09.11" section) and directed Phase-10 (clinical-review) planners to exclude D2 from the clinical sign-off scope. This is a scoping ruling, not a waiver of rigor — it is why the audit weight for D2 fell entirely on criteria 3/4/7 plus the Phase-11 bench for criterion 1. |
| 7 | **Disposition honoured.** Nothing that would move the delivery disposition off NO-GO for real insulin promotes without that being the explicit, separate subject of the change. | ✅ **MET** | Promoting D2 (once the bench clears) does **not** touch the delivery disposition. Real-insulin use stays **NO-GO** regardless of D2's `experimental`/`main` location — that disposition is governed elsewhere and is not what this dossier or D2's promotion changes. The gate-tighter disposition (D-06) is explicitly: keep D2 experimental/default-off *now*, promote *later*, in one step, once bench-verified — never silently widen the delivery disposition as a side effect. |

## Default-path regression audit (cited for criteria 3–4, not a separate §1.4 item)

Two structural risks apply to *any* change near the correlation seam even when it stays on the default
`.opcodeFIFO` path — both were independently audited and found clean, with zero dose-path Source edits
required to prove it:

- **FIFO byte-identity (D-03):** the pre-D2 `pending.firstIndex(where:)` predicate
  (`$0.expectedCharacteristic == characteristic && $0.expectedOpCode == opCode`) is reproduced **byte-for-byte**
  inside the new `.opcodeFIFO` switch case (`PumpTransactionCoordinator.swift:165-168`); the D2 diff only
  wrapped it in a `switch` and added a separate `.txIdMatch` branch (`:169-179`). Pinned by
  `opcodeFifoBranchIsByteIdenticalStructuralGuard` (fault-injection RED-then-green verified with a
  byte-identical git revert of the audited Source). **PASS — no REVERT-trigger.**
- **Parser additivity (D-08):** the D2 change added a **new** `add(_:on:)` overload
  (`ResponseParser.swift:54-60`) registering a **single new key** `(control, 77)` (`:133`); the pre-existing
  `add(ErrorResponse.self)` registration (`(currentStatus, 77)`, unmodified) is not shadowed. Exactly one
  `on: .control` registration exists. `ResponseParityTests` (39) and `OracleParityTests` (56) stayed green.
  Pinned by `op77ControlKeyIsAdditiveNotShadowingStructuralGuard`. **PASS — no REVERT-trigger.**

## The 8 D-04 failure-path / adversarial cases (criterion 4 evidence, full list)

| # | Case | Suite | Test | Verdict |
|---|---|---|---|---|
| 1 | Allowlist rejection — `.mobi`/`.unknown` stay `.opcodeFIFO` | Plan 01 | `allowlistRejectsMobiStaysFifo`, `allowlistRejectsUnknownStaysFifo` | ✅ PASS |
| 2 | Fail-closed reset — disconnect/error/restore reverts `.txIdMatch → .opcodeFIFO` (all 6 call sites) | Plan 01 | `failClosedResetsModeAndAllSixEdgesRouteThroughIt` | ✅ PASS |
| 3 | Arming — `setPumpFamily(.tslim)` actually elevates to `.txIdMatch` | Plan 01 | `armingTslimElevatesToTxIdMatch` | ✅ PASS |
| 4 | Cross-characteristic isolation — a same-txId frame on a different characteristic does NOT match | Plan 02 | `txIdMatchRejectsSameTxIdOnDifferentCharacteristic` | ✅ PASS |
| 5 | Op-77 NACK precision — routed to the correct one of several distinct-txId in-flight; unknown txId → unsolicited | Plan 02 | `txIdMatchOp77NackResolvesOnlyMatchingTxIdAmongSeveral`, `txIdMatchOp77UnknownTxIdIsUnsolicited` | ✅ PASS |
| 6 | No double-resolve — a duplicate/stale frame after resolution is a no-op | Plan 02 | `txIdMatchDoesNotDoubleResolveDuplicateFrame` | ✅ PASS |
| 7 | Shared-txId — two pending sharing a txId has defined (graceful-degradation) behavior | Plan 02 | `txIdMatchSharedTxIdResolvesOldestOnlyDefinedBehavior` | ✅ PASS |
| 8 | Cancellation-only-own under `.txIdMatch` | Plan 02 | `txIdMatchCancellationResolvesOnlyOwningTransaction` | ✅ PASS |

All 8 cases are **confirmation tests** (`type: execute`) that passed **GREEN on first write** — none required
a fix to Source. Zero `Sources/` edits across both audit plans (`PumpBLEClient.swift`,
`PumpTransactionCoordinator.swift`, `ResponseParser.swift` byte-identical to HEAD throughout).

**REVERT-TRIGGER STATUS across both plans: NONE.** No FIFO byte-identity break, no teardown edge leaving
`.txIdMatch` standing across reconnect, no op-77 misroute, no double-resolve, no parser shadowing, no
cross-characteristic mis-attribution, no cross-task cancellation misfire.

## SOLE REMAINING CRITERION — the Phase-11 saline bench (`txIdMatchProbe`)

Criterion 1 (verifiable/bounded) is the **only** §1.4 item still open. It is bounded already by delivery
serialization (both modes), but the pipelined-bijection claim itself needs live-hardware confirmation. That
confirmation is the existing, already-written, **read-only** bench case:

- **Location:** `Tests/TandemHardwareTests/BenchCases.swift:211-244`, `txIdMatchProbe`.
- **What it measures** (against a real, connected pump — no dose-path Source change, no re-implementation
  needed here):
  1. **ECHO** — a single read's response echoes the request's txId (`response.frame[1] == request.frame[1]`).
  2. **DISTINCT-ID PRESERVATION** — successive read commands are assigned distinct txIds, each echoed back.
  3. **DECISIVE / concurrent same-opcode disambiguation** — two same-opcode reads are **pipelined** (both
     issued before the first reply); the two responses must carry the two distinct request txIds as a
     bijection — i.e. attributable by txId even where opcode-FIFO order could not disambiguate.
- **Hard safety invariant preserved by the bench itself:** read-only, non-mutating status reads **only**;
  `exchangeCapturingTxId` throws on any non-read message; both software walls (transport serialization +
  the AppModel single-delivery mutex, P11) stay armed; no delivery is ever issued by this probe. The bench
  case's own doc-comment is explicit: never pipeline two delivery/bolus commands to "test" this — that is
  the exact double-dose the serialization exists to prevent.
- **This dossier does NOT re-implement or modify `txIdMatchProbe`** — it is referenced as-is (unchanged,
  confirmed via this audit's read-only inspection of `BenchCases.swift:190-244`).

## Disposition — GATE-TIGHTER + PRE-STAGE (D-06, binding owner decision 2026-08-16)

- **Keep D2 `experimental` / default-off** until the Phase-11 bench clears. This is **not** a full in-phase
  promotion — it is explicitly bench-blocked.
- **REVERT** is reserved for the case where an adversarial test surfaces a real defect (FIFO byte-identity
  break; a teardown edge leaving `.txIdMatch` standing across reconnect; op-77 `firstIndex` resolving a
  DELIVERY transaction's terminal frame onto the wrong request). **None occurred** — see the REVERT-TRIGGER
  STATUS line above. The disposition is confirmed as **gate-tighter + pre-stage**, not revert.
- **Real-insulin use remains NO-GO** regardless of D2's branch location or its eventual promotion — nothing
  in this dossier or in D2's promotion moves that disposition (criterion 7).
- Nothing in this dossier, the audit, or D2 itself is marked **verified**. "Confirmed" in this document means
  confirmed by test/code-inspection evidence in a simulated/`@testable` context, not confirmed against live
  hardware — that is precisely the Phase-11 bench's job.

## One-step promotion after the bench

Once the Phase-11 saline bench (`txIdMatchProbe`) runs and **all three of its assertions pass** against real
hardware:

1. This dossier's criteria table has **all seven items MET or N/A** — criterion 1 flips from OPEN to MET,
   citing the bench run (date + result) as the closing evidence. No other criterion needs re-work.
2. Promote `experimental → main` via the repo's standing discipline: **PR → green CI → merge** (same
   mechanism as every other `main` change; no special-cased fast path). No `--no-verify`.
3. Record the promotion date and the bench result in this dossier (append, do not silently replace this
   record) and in `../faBolus/BRANCHES.md`'s governance note (`:134-143`), closing the loop this dossier
   opened.
4. Promotion of D2 alone does **not** change the delivery disposition (still NO-GO for real insulin) or
   distribute the `experimental` branch (§1.2 clinical-review-gate-on-distribution is a separate,
   independent constraint that this dossier does not touch).

If instead the bench fails any of its three assertions, this dossier's disposition becomes
**REVERT-pending-owner**: the finding must be recorded here and escalated, not silently patched around.

---
*Phase: 09.11-d2-ble-txid-correlation-safety-audit (Plan 03)*
*Written: 2026-08-16*
*Cites: 09.11-01-SUMMARY.md, 09.11-02-SUMMARY.md (faBolus-internal planning), `../faBolus/BRANCHES.md` §1.4,
`.planning/OWNER-DECISIONS.md` "## 09.11" (D-06, D-07)*
