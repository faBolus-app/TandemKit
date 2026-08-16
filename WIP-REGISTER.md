# WIP register — TandemKit

**Created:** 2026-08-04, per §0.1 of `faBolus-handoff-v3.md`.

**State at capture:** `git status` clean · no stashes · nothing unpushed · no pull requests ever opened.

**Disposition key:** **R** = resume after restructuring · **F** = fold into the v3 plan · **A** = abandon ·
**N** = not our WIP.

---

| # | Item | Evidence | Disp. | Note |
|---|---|---|---|---|
| 1 | ~~`remediation/audit-round3-2026-07-24` is a bare label — identical SHA to `main`~~ **SUPERSEDED 2026-08-04 — DO NOT DELETE THIS BRANCH** | now **2 commits ahead** of `main` (`b157efa`, `4fbe4df`); pushed, upstream set | **F** | True when captured (`main` was still `802b921`), and **dangerous now**: the branch carries the only copy of the pump-authoritative trend-arrow API (`HomeScreenMirrorResponse.cgmTrendArrow`, `CurrentEgvGuiDataV2Response.trendArrow -> String?`) that faBolus's own round-3 commits require. Following the original "delete after the `deprecated` tag" disposition would break the faBolus build. Correct action: **merge to `main`** (master plan P3, and it must merge *first* — it is the only repo whose CI has no cross-repo inputs). **RESOLVED — merged to `main`** (round-3 landed; `main` @ `a026279`). |
| 2 | Stale "NOT yet hardware-tested" doc comments | `Sources/TandemBLE/PumpBLEClient.swift:24`, `Sources/TandemBLE/TandemBLE.swift:7` | **F** | Contradicted by `PINNED.md:34-51`, which records a 2026-07-18 on-hardware pass (JPAKE pairing, reads, a signed 0.10 u bolus delivered). A false *pessimistic* claim is still a false claim — v3 §13 requires every displayed/stated fact to trace to something real. Correct the wording to name exactly what was and was not exercised. **RESOLVED 2026-08-07 (P16 close-out):** both comments corrected — `PumpBLEClient.swift` and `TandemBLE.swift` now state the JPAKE (2026-07-18) and legacy-V1 (2026-08-07) on-hardware passes recorded in `PINNED.md`, note the BLE path validates via `TandemBenchHarness` (not `swift test`), and name the cartridge-gated items still outstanding. |
| 3 | CONTROL_STREAM (A3) cartridge-fill progress feedback deferred | `Sources/TandemMessages/Requests/Control/CartridgeFillRequests.swift:6-7` | **R** | Requests are ported; the stream consumer is not, and faBolus has no cartridge UI. Blocks nothing today. |
| 4 | The protocol port is knowingly partial | `scripts/coverage_report.py:6` — a tool exists solely to list upstream message classes with no Swift type | **F** | Run it and record the gap. v3 §2.4 wants the abstraction assessed; knowing which messages are missing is an input to that. |
| 5 | Pending hardware niceties: mass/accuracy check at a larger dose; cancel *mid*-delivery for partial-delivery reporting | `PINNED.md:52-53` | **R** | Bench-gated. The mid-delivery cancel gap matters for v3 defect group B — a cancel that races a completing dose is exactly the indeterminate case. **BOOKED 2026-08-04** as Objectives 1 & 3 of [`docs/BENCH-SESSION-PLAN.md`](docs/BENCH-SESSION-PLAN.md) — scheduled with item 12 into one saline session (master-plan P7: schedule it, don't rediscover it). |
| 6 | `PUMPX2_ALLOW_ORACLE_SKIP=1` — the single lever that silently drops all byte-parity coverage for 4 oracle-gated suites | `Tests/TandemMessagesTests/OracleAvailabilityGateTests.swift:16`; suites at `OracleParityTests.swift:7`, `ResponseParityTests.swift:7`, `HistoryLogEventsTests.swift:18`, `JpakeInteropTests.swift:10` | **N** | Working as designed and fail-closed: no CI job sets it, and nothing currently skips. Recorded so nobody "fixes" a red build by setting it. **Never set this.** |
| 7 | `scripts/test.sh` — a Command-Line-Tools-only `swift test` wrapper whose own header says it is unnecessary once full Xcode is installed | `scripts/test.sh:1-27` | **F** | **VERIFIED 2026-08-04: full Xcode _is_ installed** (`xcodebuild -version` → Xcode 26.6, build 17F113, at `/Applications/Xcode.app`), so `OPEN_QUESTIONS.md:44` is correct and the wrapper's premise no longer holds. **RESOLVED 2026-08-07 (P16 close-out):** header rewritten to state the wrapper is a convenience, not a necessity (Xcode is installed; CI runs plain `swift test`). The file is KEPT — it is the CLT-only test path and its behavior is unchanged. Recorded now because the verification was the actual task, and because the wrapper being unnecessary means **the watch/iOS/macOS targets are all buildable locally** — which is what let the 32-bit `glucoseEpochSec` overflow be caught (faBolus `c7b103c`) rather than shipped. |
| 8 | **`.unsafeFlags` on `CMbedTLSJPAKE` prevents TandemKit from ever being consumed as a versioned SwiftPM dependency** | `Package.swift:37`; faBolus pins by local path at `faBolus/project.yml:40-41` ("Pin to a released version once TandemKit tags v0.1.0") | **F** | **This is a hard blocker for v3 §1.3**, which requires semantic versioning on the backend with apps pinning explicit versions. SwiftPM refuses `unsafeFlags` in a version-pinned dependency. Resolving it means moving `-DMBEDTLS_CONFIG_FILE` into the header/`cSettings` via `.define`, or vendoring a pre-configured config header. **DECLARED UNMET 2026-08-07 (P16 close-out, owner decision):** version-pinning is NOT achieved and NOT attempted — the `.unsafeFlags`/mbedtls-vendoring refactor is deferred and local-path consumption stays. There are in fact TWO `.unsafeFlags` sites (`Package.swift:37` crypto — the real blocker in the `TandemAuth`/`TandemBLE` closure faBolus consumes; `Package.swift:69` harness linker on the non-consumed executable). `v0.1.0` (annotated) and `v0.2.0` (lightweight) tags now exist, but no `v0.3.0` and no committed `Package.resolved`. Contract + declaration written into `CONTRIBUTING.md`/`AGENTS.md` (§1.3). Remains a standing WIP item. **MET 2026-08-13 (faBolus Phase 03, owner decision pin-current-main):** the crypto `.unsafeFlags` → `.define` swap (D3, `7ec57c6`) landed on `main` via squash PR #16, and faBolus now pins by `url:`+`revision:` to `main` tip `6efdd43d767c34a0d298ac52fbbd2cd77a6d192a` (not by an exact-version tag — no `v0.3.0` was cut; a revision pin needs none) with a committed `Package.resolved`. Governance note: the same PR #16 squash also carried an unrelated experimental change (BLE txId correlation, item 12's `PumpTransactionCoordinator` work) onto `main` in the same commit as D3, outside faBolus's own `experimental`→`main` promotion gate — accepted by the owner as a known, recorded deviation (see faBolus `BRANCHES.md` §1.3 and `.planning/phases/03-pumpx2kit-version-pin/03-01-SUMMARY.md`); it does not change this item's own disposition. |
| 9 | `Sources/TandemBenchHarness` — a shipped executable product with no test target, exercised only manually behind `PUMPX2_DELIVER_SALINE=1` | `main.swift:324,350` | **N** | Correct posture for a hardware bench tool. |
| 10 | ~~compile inputs are symlinks generated by `link-mbedtls.sh`, **not committed**~~ **CORRECTED 2026-08-04 — the original entry was wrong** | `git ls-files -s Sources/CMbedTLSJPAKE/mbedtls_lib` → **13 entries, all mode `120000`** | **N** | The symlinks **are** committed (git preserves them), which is exactly why CI works with `submodules: recursive` and why no CI step invokes the script. `link-mbedtls.sh` is a maintenance tool, to be re-run only if the mbedTLS file set changes. What a fresh clone lacks is the **submodule** the links point into, not the links. Acting on the original entry — "a fresh clone must run that script" — would have been harmless; acting on its premise (that the links are untracked and should be generated) would break the build. Nothing to do. |
| 11 | `scripts/port_message.py` emits `// TODO(port):` markers into generated Swift | `:186, :200, :210, :239` | **N** | Generator templates, not live markers. No file in `Sources/` currently contains a `TODO(port)` — the port is clean. |
| 12 | **BENCH FOLLOW-UP (R3-D):** transaction correlation could be tightened from `(characteristic, opCode)` FIFO to also match the wire txId (`frame[1]`), letting two identical in-flight opcodes coexist safely and retiring the delivery-class serialization. | `Sources/TandemBLE/PumpTransactionCoordinator.swift` `ingest()` note; `Pending.txId` is retained for exactly this | **R** | **Gated on a hardware fact:** does a Tandem response reliably ECHO the request txId in `frame[1]`? Neither the code nor the vendored oracle establishes it, and matching on a txId the pump does not echo would fail EVERY correlation → break all pump comms. Until confirmed on the bench, R3-D closes the cross-resolve hazard with **delivery-class serialization** (owner decision 2026-08-04: serialize boluses now, investigate txId-match later). When bench time is available: capture a few request/response pairs, confirm `response.frame[1] == request.txId`, and if so add `&& frame[1] == entry.txId` to `ingest` + drop the `serialized` gate. **BOOKED 2026-08-04** as Objective 2 of [`docs/BENCH-SESSION-PLAN.md`](docs/BENCH-SESSION-PLAN.md) — bundled with item 5's mid-delivery cancel into one saline session. |

---

## P16 close-out reconciliation (2026-08-07)

Re-disposition of every open item against `main` @ `a026279`, with evidence. Inline cell notes above
carry the same status.

| # | Status | Evidence |
|---|---|---|
| 1 | **RESOLVED** | round-3 merged to `main` (`main` @ `a026279`; the trend-arrow API the faBolus build needs is present). |
| 2 | **RESOLVED** | stale "NOT yet hardware-tested" comments corrected in `Sources/TandemBLE/PumpBLEClient.swift` and `Sources/TandemBLE/TandemBLE.swift` to match the `PINNED.md` JPAKE (2026-07-18) + legacy-V1 (2026-08-07) passes; wording only, no behavior change. |
| 3 | **STANDING BENCH HOLD** (reaffirmed) | CONTROL_STREAM cartridge-fill progress consumer still deferred; no cartridge UI depends on it. Bench-gated; blocks nothing. |
| 4 | open (R) | protocol port knowingly partial; `scripts/coverage_report.py` still lists the gap. Out of scope for P16 governance/licensing. |
| 5 | **STANDING BENCH HOLD** (reaffirmed) | mass/accuracy at a larger dose + mid-delivery cancel — booked in `docs/BENCH-SESSION-PLAN.md`; needs a real pump + saline. |
| 6 | **CONFIRMED never set** | no CI job sets `PUMPX2_ALLOW_ORACLE_SKIP`; the new `sbom-provenance` job does not touch it; the oracle suite runs full. **Never set this.** |
| 7 | **RESOLVED** | `scripts/test.sh` header rewritten to "convenience, not a necessity"; file KEPT (CLT-only test path), behavior unchanged. |
| 8 | **MET** (owner pin-current-main, 2026-08-13; supersedes the 2026-08-07 DECLARED UNMET) | version-pinning now achieved via a `url:`+`revision:` pinned revision (`6efdd43d767c34a0d298ac52fbbd2cd77a6d192a`), not an exact-version tag; the crypto `.unsafeFlags` → `.define` swap (D3) is on `main`; committed `Package.resolved` closes the contract's third clause. §1.3 target-state + current-state sections corrected in `BRANCHES.md`/`CONTRIBUTING.md`/`AGENTS.md` (faBolus). D2-on-main governance deviation (item 12's txId work rode along in the same PR #16 squash) recorded, not silently corrected away. |
| 12 | **STANDING BENCH HOLD** (reaffirmed) | txId-match tightening; booked in `docs/BENCH-SESSION-PLAN.md`. The 2026-08-07 legacy-pump probe observed reliable txId echo on reads (see `PINNED.md`), but the R3-D delivery-class serialization is retired only after a saline-session confirmation — hold stays open. |

Items 9/10/11 remain **N** (working as designed). Governance/licensing landed this pass:
`BRANCHES.md` stub, `CHANGELOG.md`, `THIRD_PARTY.md`, `docs/SBOM.md` + `scripts/check-sbom.sh`
(non-blocking CI job), `.github/CODEOWNERS`, `.github/pull_request_template.md`, and the §1.3/§1.4
sections in `AGENTS.md`/`CONTRIBUTING.md`.

## Negative results

- No `FIXME`, `HACK`, or `XXX` anywhere. The only strict `TODO` hits are the generator templates above.
- No Swift `#if` compilation conditions at all in `Sources/` or `Tests/` — the only preprocessor use is
  C header guards in `Sources/CMbedTLSJPAKE/include/`.
- No `exclude:` in `Package.swift`; every `Sources/` and `Tests/` directory is wired to a target.
- No `XCTSkip*`, `func x_test`, `@Test(.disabled`, or commented-out test bodies. Skipping is expressed
  only through `.enabled(if: OracleRunner.isAvailable)`, backed by the fail-closed gate in item 6.
- No `fatalError` / `preconditionFailure` / `unimplemented` in `Sources/` or `Tests/`.
- Zero commented-out code blocks over 5 lines.
- `vendor/pumpx2-oracle` and `vendor/mbedtls` are upstream submodules and were excluded from all
  content scans.

## 09.8-01 Upstream sync — one-time catch-up triage (2026-08-16)

**Scope:** faBolus Phase 09.8 Plan 01 (tracer). Re-verifies CURRENT live upstream state (not the
2026-08-15 RESEARCH.md snapshot, which is now stale), oracle-re-derives the priority-1 candidate,
spot-checks history-log opcodes, runs the coverage-gap tool, and performs a systematic
"silently-dropped" parity audit. **INVESTIGATE + TRIAGE + INVENTORY only** — per explicit executor
instruction, no adoption lands in this plan even where the plan text would otherwise allow a
same-session fix; every genuine finding below is recorded as an **ADOPTION CANDIDATE** for owner
review, not implemented. `git diff --stat Sources/` is empty for this plan (only
`Tests/TandemMessagesTests/ResponseParityTests.swift` gained two additive assertions in the
existing `currentActiveIdpValuesResponseParses` test plus one new `@Test` function).

### Toolchain

JDK 21 **was found and used** this session (Homebrew `openjdk@21` at
`/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home` — `OracleRunner.swift`'s default
`javaPath` already points here, no env var needed). Built the oracle JAR fresh
(`cd vendor/pumpx2-oracle && JAVA_HOME=... ./gradlew :cliparser:shadowJar` → `BUILD SUCCESSFUL`).
`./scripts/test.sh --filter ResponseParityTests` (39 tests) and `--filter HistoryLogEventsTests`
(5 tests, 3 suites) both pass, green, no regressions. **No task is toolchain-blocked.**

### Live upstream re-verification (superseding RESEARCH.md's 2026-08-15 snapshot — one day stale)

- **`jwoglom/pumpx2` `main` vs pin:** `git -C vendor/pumpx2-oracle rev-parse HEAD` = `dad3eea2a3f6ae1bb1a6fdc6b3eac37f3ac7132b`; `git ls-remote https://github.com/jwoglom/pumpx2 main` = same SHA. **Confirmed: `main` has not moved.** (D-02)
- **A `dev` branch genuinely exists on BOTH repos** (confirms the plan's corrected premise over RESEARCH.md's "no dev branch" finding — that finding is now definitively superseded, not just stale): `gh api --paginate repos/jwoglom/pumpx2/branches --jq '.[].name'` and the `controlX2` equivalent both list a branch literally named `dev`.
- **pumpx2 `dad3eea...dev` compare:** `{"ahead_by":42,"behind_by":2,"status":"diverged"}` — **42 commits, not the ~8 the plan's premise cited** (upstream moved substantially in the ~24h since RESEARCH.md was written). The `behind_by 2` are `8b622df2d` ("v1.9.1" tag) and `dad3eea2a` ("update readme") — release/doc commits on `main` not reachable from `dev`, not protocol-relevant.
  - Commit log (`dad3eea...dev`, oldest→newest, merges collapsed to their PR number below): op 11/12 history-log parsing+cargo fix (`ea361236c`) → bolus history-log serialization/dispatch/field-semantics fix (`319dace58`, PR #104) → DailyBasal battery-charge fix (`73fa21332`, PR #105) → 12-bit typeId mask + `typeIdBytes()` helper (`c8a8adc7f`, `0618045ac`) → six `buildCargo`-offset fixes for opcodes 69/70/71/97/151/279 (PRs #106–#111) → registration of 6 previously-unregistered history-log classes in `HistoryLogParser` (`993bda70c`) → captured-record regression tests for CGM/fills/settings/CIQ/basal/alarms/reminders (PRs #112–#115) → header-high-nibble round-trip support + typeId-truncation-above-255 fix (`6926f1307`, PRs #116–#118) → remaining Control-IQ/Dex-CGM-alert payload field decoding (`d3d209c24`, PR #119) → `BolusDelivery` bolusType bitmask semantics correction + `BolexActivated` serializer alignment (`c07687db4`, PR #120).
  - **All PRs #103–#120 are MERGED to `dev`** (confirmed via the merge-commit messages in the compare). Only **PR #121** (dev, opened 2026-08-16, today) remains open against `dev`: renames 3 `CGMAlertStatusResponse.CGMAlert` placeholder enum ids (`DEFAULT_CGM_ALERT_45/46/48` → named, sourced from `tconnectsync`'s cloud-export dictionary) — cosmetic, no byte-layout change. ⚠ PR #121's body cites a "companion PR: jwoglom/TandemKit#304" — **verified this does not exist** (`gh api repos/jwoglom/TandemKit` → 404; `gh pr view 304 --repo faBolus-app/TandemKit` → not found). Recorded as an observed anomaly (likely a hallucinated cross-reference by whichever agent authored PR #121) — not actionable, not chased further.
  - **PR #102 ("Protocol correctness and security fixes") remains open against `main`**, unmerged, owner comment unchanged (`gh api repos/jwoglom/pumpx2/issues/102/comments`, jwoglom 2026-08-06): *"I'm not going to be able to merge this PR as is. But I can make some smaller fixes from this summary."* PRs #103–#111 above are confirmed to be exactly those "smaller fixes."
- **controlX2 `main...dev` compare:** `{"ahead_by":10,"behind_by":0,"status":"ahead"}` — matches the plan's cited count exactly. All 10 commits are app/UI-level (error-card UI, CI speedups, Time-In-Range display, quick-action notification buttons, xDrip bolus-duplicate fix, wear location-permission cap) — **surface-only, no protocol-layer content**, confirming RESEARCH's characterization.
- **Open PRs, both repos** (`gh pr list --state open`): pumpx2 → #121 (dev, today) + #102 (main, unmerged since 2026-08-06). controlX2 → #158 "Fix duplicate xDrip bolus treatments" (dev, a *follow-up* refinement to the already-merged `0045798b5` timestamp/duplicate fix — a second dedup pass needed after real-device testing found the first fix didn't cover mid-poll REQUESTING/DELIVERING state transitions; controlX2's own xDrip integration, architecturally unrelated to TandemKit), #156 "History log fetcher and tests" (dev, since 06-30), #155 "Extended bolus UI" (dev, since 06-27), #147 "Update robolectric screen sizes" (dev, since 04-27), #138 "Nightscout sync/extended bolus UI/chart fixes" (dev, since 04-05). All five controlX2 PRs beyond #158 are UI/test-infra, LOW priority per D-03, deferred to Plan 02 stub per the plan's own instruction.

### Task 1 — CurrentActiveIdpValuesResponse (priority-1 spine): GENUINE GAP FOUND, NOT ADOPTED

**`gh pr diff 102 --repo jwoglom/pumpx2`** read directly (not WebFetch-summarized, per Pitfall 3). The literal diff for `CurrentActiveIdpValuesResponse.java`:

- **Old (pre-fix, matches the current pinned `main`/submodule) doc'd layout:** byte 4 = padding, bytes 5-6 = `currentTargetBg` (uint16, overlapping byte 6 with `currentInsulinDuration`).
- **PR #102's fixed layout:** bytes 4-5 = `currentTargetBg` (uint16, non-overlapping), bytes 6-7 = `currentInsulinDuration`, bytes 8-9 = `currentIsf`.
- **The fix is backed by a genuine hardware capture already present in upstream's OWN test suite before PR #102** (`testCurrentActiveIdpValuesResponse_parseCargo_CapturedPayload`, cargoHex `7017000073002c012800`) — PR #102 only corrects a previously-WRONG assertion on that pre-existing capture (was asserting `currentTargetBg == 11264`, now asserts `115`) and fixes `parse()`/`buildCargo()` to match. This is not a hypothetical fix; it's a correction against real pump bytes already checked into the test suite.

**Independent re-derivation (hand-decoded the literal hex myself, not trusting the PR's stated values):** `raw = [0x70,0x17,0x00,0x00,0x73,0x00,0x2c,0x01,0x28,0x00]`.
  - `carbRatio` = u32LE@0 = 6000 (6.0 g/U) — same under every layout.
  - **TandemKit's CURRENT implementation** (`Sources/TandemMessages/Responses/Responses.swift:767`, `currentTargetBg = Int(raw[5])`) decodes this capture's `currentTargetBg` = `raw[5]` = **`0x00` = 0**.
  - PR #102's fixed layout (u16LE@4) decodes `raw[4],raw[5]` = `0x73,0x00` = **115** — matches the real captured value the PR cites.
  - The OLD pre-fix upstream layout (u16LE@5, overlapping) decodes `raw[5],raw[6]` = `0x00,0x2c` = **11264** — matches the PR's stated "before" bug value.
  - `currentInsulinDuration` = u16LE@6 = `0x2c,0x01` = 300 ✓ (unaffected by the targetBg question either way). `currentIsf` = u16LE@8 = `0x28,0x00` = 40 ✓.
  - **TandemKit's single-byte read at offset 5 matches NEITHER the old-buggy (11264) NOR the PR-fixed (115) upstream value — it produces a THIRD, independently-wrong result (0) on this real captured payload.** TandemKit's own doc-comment justification ("upstream reads targetBg as `readShort(raw,5)`... we read only its low byte (raw[5])") assumed the field's real position was byte 5 (matching the OLD buggy code's low byte); the real captured-hardware evidence says the field's actual position is byte **4**, with byte 5 as its (normally-zero) high byte — TandemKit reads the wrong byte entirely.

**Assessment:** `currentTargetBg` currently **always decodes as 0** on real Tandem pump hardware whenever bytes 4-5 encode a nonzero target BG the way the captured payload does (target 115 mg/dL is a completely ordinary IDP target). This is a genuine, real-world decode bug in a dose-path-adjacent status-read message (bolus-calculator target BG), not a hypothetical.

**Per explicit executor instruction, this was NOT adopted.** No edit was made to `Responses.swift` (confirmed: `git diff --stat Sources/TandemMessages/Responses/Responses.swift` is empty for this plan; an attempted temporary fault-injection edit to the same file was in fact blocked by the harness's own dose-path safety classifier, which is itself a meaningful confirmation that this file sits in the highest-scrutiny tier). The fault-injection control that Task 1's TDD flow calls for was instead confirmed **arithmetically** (not via source mutation): for the new oracle vector added below (`targetBg=200, duration=400`), an overlapping 2-byte read at offset 5 would decode `200 + 144*256 = 37064` (WRONG, would go RED) vs. the correct 200 (GREEN, current behavior) — confirming the added test *would* catch that specific fault, though it cannot catch the byte-4-vs-5 fault this session actually found (see caveat in the test file comment).

**Test changes (additive only):** extended `ResponseParityTests.swift`'s existing `currentActiveIdpValuesResponseParses` case is unchanged; added one new `@Test func currentActiveIdpValuesResponseParsesAcrossDurationByteBoundary()` with a second oracle vector (`json: "[6000, 200, 400, 45]"`, duration=400 crosses the byte-6 boundary the same way the pre-existing 300 vector does, with a distinct targetBg). This vector is oracle-green under the CURRENTLY PINNED (pre-PR#102) oracle's `buildCargo`, which is self-consistent with TandemKit's current read — **it does not, and cannot, resolve the byte-4-vs-5 question**, because the pinned oracle's `buildCargo` only knows how to construct the old (possibly-wrong) layout, not the real captured-hardware layout. This limitation is documented inline in the test file.

**>>> ADOPTION CANDIDATE #1 (HIGH priority, dose-path-adjacent, STOP-FLAGGED FOR OWNER REVIEW <<<**
- **What:** `CurrentActiveIdpValuesResponse.currentTargetBg` should read `Bytes.readShort(raw, 4)` (or equivalently `Int(raw[4])`, since targetBg is always < 256 per every observed value), not `Int(raw[5])`.
- **Evidence:** a genuine pre-existing hardware capture in upstream's own test suite (cargoHex `7017000073002c012800`), independently hand-decoded this session (not trusting the PR's stated values).
- **Why not adopted here:** per this plan's explicit safety scoping (investigate/triage only), and reinforced by the harness's own classifier blocking a source edit to this file.
- **Recommended next step:** a dedicated fix plan (Plan 02 or a new plan) that (a) adds a `ResponseDirectTests.swift` case pinning the literal captured hex `7017000073002c012800` → `currentTargetBg==115` (the oracle's pinned `buildCargo` cannot construct this byte pattern, so `OracleRunner`-based `ResponseParityTests` cannot be the vehicle — needs the direct-byte-comparison pattern the codebase already uses for oracle-CLI-unconstructable shapes), (b) changes the read to offset 4, (c) re-runs the full oracle suite, (d) lands on `experimental` behind §1.4 (dose-path-adjacent, per this plan's prohibitions) pending Phase 11 saline-bench confirmation that the pump's live bolus-calculator target BG now decodes correctly.
- **Note:** `PINNED.md`'s bench log already captures a bolus-calculator snapshot with `targetBG 110 mg/dL` (2026-08-07 legacy-pump probe) — if that specific value was read via a path that happens not to go through `CurrentActiveIdpValuesResponse` (e.g. `IDPSegmentResponse`, which per PR #102's doc comment already packs the trio contiguously as uint32/uint16/uint16 with no overlap ambiguity), it would not have surfaced this bug; worth checking during the fix plan whether the two responses ever disagree in practice.

### Task 2 — history-log spot-checks (buildCargo PRs + dev-merged fixes)

**All six `buildCargo`-offset PRs are confirmed buildCargo-only** (spot-checked all six, not just #111 as RESEARCH did — generalizes Assumption A3): fetched each commit's diff (`ca25921de` op69, `aef01d7f0` op70, `628a902fe` op71, `1717a1e31` op97, `f2fdb5d0c` op151, `10c2d61cc` op279) via `gh api .../commits/<sha> -H "Accept: application/vnd.github.v3.diff"`. Every one of the six touches only `buildCargo()` (inserting the padding bytes `parse()` already implicitly skipped), never `parse()`. Cross-checked TandemKit's existing decode offsets against each fix's stated authoritative `parse()` offset:

| Opcode | Class | Authoritative parse offset (from fix commit) | TandemKit's Swift offset | Verdict |
|---|---|---|---|---|
| 69 | IdpActionHistoryLog | `name`@18 | `name = Bytes.readString(raw, 18, 8)` | **N/A — confirmed correct** |
| 70 | IdpBolusHistoryLog | `insulinDuration`@14 | `insulinDuration = Bytes.readShort(raw, 14)` | **N/A — confirmed correct** |
| 71 | IdpListHistoryLog | `slot1`@14 | `slot1 = Int(raw[14])` | **N/A — confirmed correct** |
| 97 | ParamChangeRemSettingsHistoryLog | `lowBgThreshold`@14 | `lowBgThreshold = Bytes.readShort(raw, 14)` | **N/A — confirmed correct** |
| 151 | CgmDataSampleHistoryLog | `value`@19 | `value = Bytes.readShort(raw, 19)` | **N/A — confirmed correct** |
| 279 | BasalDeliveryHistoryLog | `commandedRate`@14/`profileBasalRate`@16/`algorithmRate`@18/`tempRate`@20 | same offsets exactly | **N/A — confirmed correct** |

All six: **N/A to this decode-only port, offsets confirmed** — the Anti-Pattern warning (buildCargo-only ≠ parse() bug) holds for every one, not just the spot-checked #111.

**Dev-merged fixes, deeper-than-buildCargo (fetched full diffs, `gh api commits/<sha> -H "Accept: .../vnd.github.v3.diff"`):**

- **12-bit typeId mask (`0618045ac`/`6926f1307`, `HistoryLogParser.java`/`HistoryLog.java`):** upstream's OLD dispatch computed typeId via signed-byte arithmetic (`rawStream[0]` + 256×`rawStream[1]` with a sign-correction hack) that did NOT mask off the high nibble of byte 1 — a genuine Mobi-generation record (high nibble = 1) computed the wrong typeId (e.g. opcode 55 → 4151) and missed dispatch entirely (recovered only by a warning-logging retry ladder). **TandemKit's own dispatch (`HistoryLogEvents.swift:194`, `let typeId = Bytes.readShort(raw, 0) & 0x0FFF`) ALREADY masks correctly** — confirmed by direct read, not inference. **N/A — TandemKit was already ahead of this upstream bug**, independently arriving at the same masking fix. (The companion "log generation" nibble itself — 0=t:slim X2, 1=Mobi — is NOT exposed by TandemKit; recorded separately below as a deliberate-scope omission, not a bug, since faBolus targets t:slim X2 only.)
- **Op 11/12 (`PumpingSuspendedHistoryLog`/`PumpingResumedHistoryLog`, `ea361236c`):** this is a genuine **parse()-side field ADDITION**, not an offset correction — upstream added `preSuspendState`/`preResumeState` (uint32@10, previously unparsed padding) and `rpaTimeout` (byte@17, `PumpingSuspendedHistoryLog` only). The PRE-EXISTING fields (`insulinAmount`@14, `reasonId`@16) are UNCHANGED in the diff. TandemKit's existing `insulinAmount`@14/`reasonId`@16 reads remain correct; TandemKit is simply MISSING the two new fields. Recorded as a Task 4 gap below (informational-only, does not corrupt any currently-read field).
- **Bolus history-log serialization/dispatch/field-semantics (`319dace58`, PR #104):** three sub-findings:
  1. **`BolusActivatedHistoryLog` byte 12 is a real field (`selectedIob`), not padding** — `iob`@14/`bolusSize`@18 offsets are UNCHANGED in the diff (only the padding byte 12-13 gained meaning). TandemKit's `iob`@14/`bolusSize`@18 remain correct; TandemKit is MISSING `selectedIob`. Task 4 gap.
  2. **Semantic enum decoding added** (`BolusRequestedMsg1HistoryLog.BolusType`, `BolusRequestedMsg2HistoryLog.BolusOption`/`SelectedIOBType`) — TandemKit already captures the RAW numeric values at the correct offsets (`bolusTypeId`@12, `options`@12, `selectedIOB`@24, all confirmed correct by direct read) but has no enum wrapper for any of them. Task 4 gap, LOW priority (values are captured, just undecoded).
  3. **`getBolusType()` semantics corrected from a bitmask read to a scalar enum read** for `BolusRequestedMsg1HistoryLog` specifically (previously misread via `BolusDeliveryHistoryLog.BolusType.fromBitmask()`, a DIFFERENT field with a different encoding, per the PR's own doc comment) — TandemKit stores only the raw `bolusTypeId` int with no interpretation layer, so this bitmask-vs-scalar confusion cannot currently manifest in TandemKit; N/A as a bug, but the semantic annotation gap (item 2 above) is what would need fixing before TandemKit could offer a `getBolusType()`-equivalent at all.
- **DailyBasal battery-charge fix (`73fa21332`, PR #105, upstream issue #56):** Java's old code read `batteryChargeRaw = raw[23]` as a SIGNED byte (Java's `byte` is signed -128..127) and then applied a bizarre non-linear scaling formula (`100*((batteryChargeRaw+256.0)/512.0)`) to a value that the pump actually reports as an already-unscaled 0-100 percent — the old formula was simply wrong (e.g. it reported a real 20% battery as 53.9%). **TandemKit's `Sources/TandemMessages/Responses/HistoryLogEvents.swift:469`, `batteryChargeRaw = Int(raw[23])`, is immune to the signed-byte half of this bug by construction** (Swift's `[UInt8]` is unsigned, so `raw[23]` is already 0-255) **and TandemKit never ported the buggy percent-scaling formula at all** — it exposes `batteryChargeRaw` as a raw Int with no `getBatteryChargePercent()`-equivalent method. **N/A — confirmed correct, and in fact never had upstream's bug to begin with.**
- **Six previously-unregistered history-log classes (`993bda70c`: `AlarmAckHistoryLog`, `AlertAckHistoryLog`, `ReminderActivatedHistoryLog`, `ReminderDismissedHistoryLog`, `CgmPairingCodeG7HistoryLog`, `TipsErrorHistoryLog`)** — these Java classes existed upstream but were missing from `HistoryLogParser`'s dispatch table until this commit. **TandemKit already has Swift structs for all six AND all six are already registered** in its own dispatch (`add(<Name>.self)` — verified by direct grep for each). **N/A — TandemKit's independent port never had this registration gap.**

### Task 3 — coverage-gap enumeration + priority-2 firmware-gate search

**`python3 scripts/coverage_report.py --missing` output (captured in full):**
```
=== request: 128/139 ported (11 missing) ===
  ✗ AbstractCentralChallengeRequest
  ✗ NonexistentDetectingCartridgeStateStreamRequest .. NonexistentPumpingStateStreamRequest (9 "Nonexistent*" placeholders)
=== response: 129/145 ported (16 missing) ===
  ✗ AbstractCentralChallengeResponse, AbstractPumpChallengeResponse, ControlIQInfoAbstractResponse,
    ControlStreamMessages, CurrentBatteryAbstractResponse, Jpake1aResponse, Jpake1bResponse, Jpake2Response,
    Jpake3SessionKeyResponse, Jpake4KeyConfirmationResponse, LastBolusStatusAbstractResponse,
    LoadCartridgeStateStreamResponse, PrimeNudgeStateStreamResponse, PumpFeaturesAbstractResponse,
    PumpingStateStreamResponse, QualifyingEvent
=== historyLog: 134/136 ported (2 missing) ===
  ✗ HistoryLog, HistoryLogParser
=== TOTAL: 391/420 upstream message classes present as Swift structs ===
```
Triaged (see Task 4 for the QualifyingEvent and Jpake*Response items, which are the only two rows here that are genuine findings rather than tool-naming artifacts):
- `Abstract*`/`*AbstractResponse` (6 items) — Java OOP base classes; concrete variants (`ControlIQInfoV1/V2Response`, `CurrentBatteryV1/V2Response`, `LastBolusStatusV2Response`, `PumpFeaturesV1/V2Response`) all confirmed present by direct grep. **N/A by design** (Swift doesn't need the abstract-base ceremony).
- `Nonexistent*` (9 items) — literally named "Nonexistent" upstream (placeholder classes for states with no request). **N/A by design.**
- `HistoryLog`/`HistoryLogParser` — Java's abstract base + static dispatcher classes; TandemKit's architecture uses a `HistoryLogEvent` protocol + a registry function instead (134/136 concrete event types present). **N/A — naming/architecture mismatch, not missing functionality.**
- `ControlStreamMessages` — a Java message-catalog/registry class, not itself a wire message. **N/A by design.**
- `LoadCartridgeStateStreamResponse`/`PrimeNudgeStateStreamResponse`/`PumpingStateStreamResponse` — cartridge-fill stream responses. **Already tracked** as WIP item 3 ("CONTROL_STREAM (A3) cartridge-fill progress feedback deferred" — requests ported, stream consumer not, bench-gated, blocks nothing today).
- `Jpake1aResponse`..`Jpake4KeyConfirmationResponse` (5 items) and `QualifyingEvent` — see Task 4 below; these are the two genuine, non-tooling-artifact findings from this report.

**Priority-2 (firmware-compat gates) search — RESOLVED, empty result:** searched `gh pr list --repo jwoglom/pumpx2 --state open` (2 results: #121 cosmetic enum rename, #102 unmerged) and the 42-commit `dev` delta (enumerated above) for any `ApiVersion`/`PumpFeature`/capability-bitmask-gating content — **none found**. `PINNED.md`'s own bench work (API-2.5-vs-CIQ+-firmware-family distinctions, the 2026-08-07 legacy-pump probe's exhaustive "every newer CIQ/Mobi-era signed CONTROL opcode is NACKed on API 2.5" finding) remains the most current firmware-gate knowledge; upstream has not added anything new in this area since the Phase-3 pin. **Recorded: reviewed, no post-baseline firmware-gate activity found** (Open Question 1 closed, not silently skipped).

### Task 4 — systematic silently-dropped gap inventory (5 dimensions, both upstreams)

**(1) Message classes/opcodes with no Swift counterpart:**

| Gap | Upstream source | Relevance | Dose-path risk |
|---|---|---|---|
| `QualifyingEvent` bitmask decode + suggested-follow-up-request catalog | `vendor/pumpx2-oracle/.../response/qualifyingEvent/QualifyingEvent.java` — a 27-flag bitmask enum (ALERT, ALARM, BOLUS_CHANGE, PUMP_SUSPEND/RESUME, BASAL_CHANGE, BATTERY, CONTROL_IQ_INFO, etc.) with a `groupSuggestedHandlers()` helper that maps each flag to the requests worth re-sending after that push notification | **MEDIUM** — TandemKit's `Characteristic.swift` already knows the `.qualifyingEvents` BLE characteristic UUID (`7B83FFF7-...`) and lists it among enumerated characteristics, but there is no bitmask-decode type and no subscription/consumption logic found anywhere in `Sources/TandemBLE`. This means TandemKit currently has no reactive "the pump just told me X changed" channel — any live-status UI must poll instead of react to push notifications. Architecturally significant (efficiency/responsiveness), not a correctness bug. | **LOW** — informational bitmask only, no wire-write, no delivery decision hinges on it today (nothing currently consumes it to be wrong about). |
| `Jpake1aResponse`/`Jpake1bResponse`/`Jpake2Response`/`Jpake3SessionKeyResponse`/`Jpake4KeyConfirmationResponse` | `messages/.../response/authentication/` | **NOT a gap — deliberate architecture difference.** `Sources/TandemAuth/PairingCoordinator.swift` dispatches these opcodes inline (`case (.sent1a, 33): // Jpake1aResponse` etc.) and feeds raw bytes directly into `JpakeAuth.readServerRound1/readServerRound2/verifyServerRound4`, rather than parsing them as discrete typed `ResponseMessage` structs registered with `ResponseParser`. `coverage_report.py`'s class-name-matching heuristic cannot see this. Already hardware-validated (`PINNED.md`'s 2026-07-18 JPAKE pairing pass). | **N/A** — already validated on real hardware, not actually missing functionality. |

**(2) Request/response fields present upstream but dropped from the Swift struct:**

| Gap | Struct | Offset | Relevance | Dose-path risk |
|---|---|---|---|---|
| `preSuspendState` (uint32) + `rpaTimeout` (byte) | `PumpingSuspendedHistoryLog` (typeId 11) | @10, @17 | New upstream fields (added `ea361236c`, this session's dev-delta); TandemKit's existing `insulinAmount`@14/`reasonId`@16 unaffected/correct | **LOW** — history-log decode-only, informational (reservoir-state tracking, alert-timeout diagnostics), no write path |
| `preResumeState` (uint32) | `PumpingResumedHistoryLog` (typeId 12) | @10 | Same commit; `insulinAmount`@14 unaffected/correct | **LOW** — same rationale |
| `selectedIob` (byte) | `BolusActivatedHistoryLog` (typeId 55) | @12 | Added `319dace58`; `iob`@14/`bolusSize`@18 unaffected/correct | **LOW** — diagnostic-only (tracks which IOB algorithm the calculator used), not itself a dose value |

**(3) MessageProps annotations dropped — GENERALIZES the SetSleepScheduleRequest seed pattern to the ENTIRE port, not a one-off:**

**>>> ADOPTION CANDIDATE #2 (HIGH priority — architectural, STRUCTURAL, STOP-FLAGGED FOR OWNER REVIEW <<<**
- **What:** `Sources/TandemMessages/Core/MessageProps.swift`'s `MessageProps` struct has **ZERO fields** for `supportedDevices` or `minApi` — confirmed by `grep -rn "supportedDevices\|minApi" Sources/TandemMessages/` returning **0 hits** anywhere in the entire Swift port. This is not a per-message oversight (like the SetSleepScheduleRequest MOBI_ONLY/MOBI_API_V3_5 omission the 09.10 pass found) — it is a **structural, type-system-level absence**: TandemKit's `MessageProps` currently CANNOT express "this message requires API version ≥ X" or "this message is Mobi-only" for ANY message, ever.
- **Scale:** upstream has `minApi=` on **32** request classes and `supportedDevices=` on **14** request classes (counted via `grep -rl` over `messages/src/main/java/.../pump/messages/request`; the response side was not separately counted but is expected to add more).
- **How upstream uses this today:** `QualifyingEvent.groupSuggestedHandlers()`'s `supportsApiVersion()` helper filters follow-up requests by `message.props().minApi()` before sending — i.e., upstream's own architecture treats this annotation as load-bearing for deciding what's safe to send to a given pump.
- **Dose-path risk: MEDIUM** (downgraded from what the annotation's upstream USE would suggest, based on TandemKit's own bench evidence) — `PINNED.md`'s exhaustive 2026-08-07 legacy-pump probe found that **every** newer/Mobi-era signed CONTROL opcode sent to an API-2.5 pump was cleanly rejected (`op-77 UNDEFINED_ERROR`) and dropped the link, never silently misexecuted. So the pump's own firmware currently fail-closes on an unsupported opcode. The risk is not "wrong insulin action from an unsupported command" (not observed) but (a) unnecessary BLE link drops/reconnects on the therapy-critical connection when probing unsupported ops, and (b) no structural guarantee that EVERY future opcode will fail equally safely if this gating is never added.
- **Recommended next step:** a dedicated fix plan that (a) adds `supportedDevices: [PumpModel]?` and `minApi: ApiVersion?` fields to `MessageProps`, (b) back-fills them for the SetSleepScheduleRequest case the 09.10 pass already found plus the 32+14 upstream-tagged classes, (c) is NOT itself dose-path-adjacent in the sense of changing wire bytes (it's additive metadata), but should still go through the same discipline given its stated purpose is gating what gets sent to the pump.

**(4) History-log event types decoded upstream but absent from the port:** **NONE FOUND.** `scripts/coverage_report.py --missing --category historyLog` reports 134/136, and the 2 "missing" (`HistoryLog`, `HistoryLogParser`) are Java's abstract-base/dispatcher classes, not concrete event types (Task 3). The 6 classes upstream itself only just registered in its own dispatch table (`993bda70c`) were already present AND already registered in TandemKit (Task 2). **This dimension is clean.**

**(5) controlx2-side quirk/workaround handling not ported:**
- **"avoid dirty BLE shutdown" pairing-loop fix (controlx2 main, 2026-05-04)** — RESEARCH.md flagged this as needing a deeper read against `PumpBLEClient`'s disconnect/teardown path; **not attempted this session either** (time budget, and it is explicitly Priority-3 per D-03, stubbed for Plan 02 by this plan's own Task 3 instruction). Carried forward unchanged, not silently dropped.
- **Log-generation nibble (0=t:slim X2, 1=Mobi, `HistoryLog.getLogGeneration()`)** — TandemKit does not expose this. **Recorded as N/A / deliberate scope**, not a gap: faBolus targets t:slim X2 exclusively (`PINNED.md`'s pump-firmware section), and every fixture in TandemKit's own history-log tests is t:slim-generation (0). No action needed unless faBolus later supports Mobi.

### Divergence ledger (deliberate, not "missing")

| Item | Why deliberate |
|---|---|
| No git submodule for `controlx2` | It's a full Android/Kotlin app, not a byte-oracle library; reviewed manually for quirks per RESEARCH's "Alternatives Considered." |
| `io.particle` package (upstream JPAKE crypto vendor) | TandemKit uses its own `CMbedTLSJPAKE`/mbedTLS-backed `EcJpakeContext`, not a port of `io.particle`. |
| Abstract Java base classes (`Abstract*Request/Response`) | Swift's concrete-struct-per-message model has no OOP-inheritance analog; each concrete variant (V1/V2, etc.) is ported directly. |
| `Nonexistent*` placeholder classes | Named "Nonexistent" upstream itself — literally not real messages. |
| Mobi log-generation nibble | t:slim-X2-only scope (see dimension 5 above). |

### Summary

- **2 ADOPTION CANDIDATES flagged for owner review** (Task 1's `CurrentActiveIdpValuesResponse.currentTargetBg` offset bug — HIGH priority, dose-path-adjacent; Task 4's `MessageProps` missing `supportedDevices`/`minApi` fields — HIGH priority, architectural). **Neither adopted in this plan.**
- **All 6 buildCargo-offset PRs + all 4 substantive dev-merged history-log fixes**: confirmed N/A to this decode-only port (offsets already correct, or TandemKit already ahead of the upstream bug).
- **Coverage gaps**: 29/420 upstream classes absent as Swift structs; 27 are N/A-by-design (abstract/Nonexistent/architecture-mismatch/already-tracked-cartridge-stream), 2 are genuine findings (`QualifyingEvent` decode — MEDIUM relevance/LOW risk; `Jpake*Response` — not a gap, architecturally different).
- **historyLog dimension is fully clean** — 134/136, no genuine gaps.
- **`git diff --stat Sources/` is empty for this entire plan.** Only additive test vectors landed (`ResponseParityTests.swift`).
- **No `PumpTransactionCoordinator.swift` edit** (D-05 respected — read nothing, touched nothing).
