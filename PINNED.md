# Pinned upstream

The Swift port tracks a specific, known-good commit of the upstream protocol library. This
is deliberate: for an insulin-delivery path, upstream changes must be reviewed and
re-validated before adoption (see the upstream-sync workflow in the plan / README).

| What | Value |
| --- | --- |
| Upstream repo | [`jwoglom/pumpx2`](https://github.com/jwoglom/pumpx2) |
| Submodule path | `vendor/pumpx2-oracle` |
| Pinned commit | `dad3eea2a3f6ae1bb1a6fdc6b3eac37f3ac7132b` |
| Ported by | Swift port in `Sources/` (hand-ported, not generated) |

## Upstream controlX2 watch

controlX2 ([`jwoglom/controlx2`](https://github.com/jwoglom/controlx2)) is the companion Android
app — a full app, never vendored or compiled. The recurring drift-detector
(`.github/workflows/upstream-drift.yml`) tracks it with a lightweight tracked-SHA baseline (not a
git submodule, unlike pumpx2 above) and measures drift against these values every cycle.
`dev` is the PRIMARY baseline (upstream's active integration branch, per the owner's
DEV-BRANCH TRUST RULE); `main` is tracked for reference. See
[`docs/UPSTREAM-SYNC-RUNBOOK.md`](docs/UPSTREAM-SYNC-RUNBOOK.md) for how to triage a fired drift
issue and when to advance these values.

| What | Value |
| --- | --- |
| Upstream repo | [`jwoglom/controlx2`](https://github.com/jwoglom/controlx2) |
| Last-reviewed dev commit | `8d3ad3115bd7ac200e8bd16bd372dbc0da58f058` |
| Last-reviewed main commit | `45e3795bad357472c1ff736dbfd7013e574dd28c` |
| Reviewed date | 2026-08-16 |
| Review notes | 09.8-01-SUMMARY.md + WIP-REGISTER.md "09.8-01"/"09.8-02" upstream-sync triage sections (10-commit dev delta, all app/UI-level, surface-only — no protocol-layer content) |

## Pump firmware

Recorded from the pump's Pump Info screen (2026-07-18). The protocol can break on a
future firmware update; this port is pinned to this firmware and treated as disposable against
vendor changes.

| Field | Value |
| --- | --- |
| Pump model | Tandem **t:slim X2** |
| t:slim Software | **Control-IQ+ 7.10.2** |
| ARM S/W Version | `da8923cc9d010d07` |
| MSP S/W Version | `da8923cc9d010d07` |
| S/W Part Number | `1017490 000` |
| Pairing type | **6-digit JPAKE** (firmware ≫ v7.7) |

**Implication:** pairing uses the modern EC-JPAKE handshake (`TandemAuth.JpakeAuth`, mbedTLS
secp256r1/SHA-256).

## Spare bench pump — legacy V1 (pre-v7.7), 16-char pairing (added 2026-08-07)

There is now a **SECOND, distinct** pump on the bench: a spare **t:slim X2** running **older
firmware (< v7.7)** that pairs with a **16-character alphanumeric pairing code** via the **legacy V1
CentralChallenge → PumpChallenge** handshake — NOT the 6-digit EC-JPAKE scheme the primary pump
above uses. Discovered while bringing the spare up on the hardware harness; the V1 library support
this needed now exists (`PairingAuth.createV1`, `LegacyPairingCoordinator`, op-17/19 parsers,
`PairingAuth.detectType`), and `LiveSession.beginPairing()` auto-selects V1 vs JPAKE from the code.

> **The two pumps are DIFFERENT FIRMWARE FAMILIES and must be validated separately.** A behavior
> observed on one (capability bitmask contents, "Mobi-only" write acceptance, remote time-set,
> txId-match, API-version-gated message variants) does **not** transfer to the other. The harness
> captures a `PumpFirmwareProfile` (API version + pump SW version + auth scheme) and prints it at the
> top of each run — **every validation-log entry below must record which pump/firmware it was
> observed on** (see the log's tagging rule).

## Validation log

> **Tagging rule (required):** every entry must state the **pump + firmware + pairing scheme** it was
> observed on — e.g. `[t:slim X2 · CIQ+ 7.10.2 · JPAKE]` or `[t:slim X2 · <fw> · V1/16-char]`. Results
> are firmware-scoped; an untagged entry is ambiguous now that two firmware families are on the bench.
> The 2026-07-18 entries below all refer to the **primary** pump `[t:slim X2 · CIQ+ 7.10.2 · JPAKE]`.

- **2026-07-18 — read-only monitor PASSED on hardware.** `swift run TandemBenchHarness monitor`
  against this pump: BLE scan → connect → discover, **6-digit JPAKE pairing succeeded**
  (signing key derived), and status reads parsed correctly. Insulin-remaining (70 u) and
  battery (35%) matched the pump exactly; all state-changing writes stayed blocked (read-only
  interlock). This validates the full stack — CoreBluetooth transport, EC-JPAKE pairing, and
  response parsing — end to end on the real pump.
  - **Finding:** the pump's displayed IOB matches **`swan6hrIOB`**, not `mudaliarIOB` — so
    `ControlIQIOBResponse.iobUnits` now uses `swan6hrIOB` (4.32 u observed = pump display).
- **2026-07-18 — additional reads confirmed on hardware:** glucose (CGM EGV V2), basal, last
  bolus, and the bolus-calculator snapshot (carb ratio, ISF, target BG) all matched the pump
  screens. Signing timestamp = `TimeSinceResetResponse.currentTime`.
- **2026-07-18 — SIGNED WRITE validated on hardware (permission test):** a signed
  BolusPermissionRequest was ACCEPTED (granted=true) and released — no insulin delivered.
- **2026-07-18 — 🎯 MILESTONE 1 DoD MET: signed bolus delivered.** `bolus 100` delivered
  **0.10 u**: permission → signed InitiateBolus (FOOD2) accepted → LastBolusStatus
  reported 0.10 u (id 1774); the **pump screen agreed**. Signed CancelBolus round-trips.
  Full delivery path (BLE + JPAKE + signed permission + signed initiate + status + cancel) is
  proven on the real pump, with every outgoing message byte-exact vs the cliparser oracle.
- **Pending niceties — BOOKED as one saline session, see [`docs/BENCH-SESSION-PLAN.md`](docs/BENCH-SESSION-PLAN.md):**
  cancel *mid*-delivery (extended/large bolus) for partial-delivery reporting (group B indeterminate
  case, WIP item 5); whether the pump echoes the request txId in `frame[1]` (WIP item 12, gates
  retiring R3-D delivery-class serialization); and a mass/accuracy check at a larger dose. Bundled
  because all three need the same pump+saline+Mac setup — run in one sitting, not piecemeal.

> The 2026-08-07 entries below refer to the **spare legacy** pump
> `[t:slim X2 · API 2.5 · V1/16-char]` (no cartridge, no CGM).

- **2026-08-07 — 🎯 legacy V1 (16-char) pairing PASSED on hardware.** `TandemBenchHarness monitor`
  (read-only, no cartridge, no CGM) against the spare older pump: BLE scan → connect → **legacy V1
  CentralChallenge→PumpChallenge pairing succeeded** (16-byte signing key derived = the pairing
  code's UTF-8 bytes) and status reads parsed. First validation of the `LegacyPairingCoordinator`
  path on real hardware. Firmware profile line (tag for all entries here):
  `API 2.5 (t:slim X2 family) · pairing=LONG_16CHAR · pumpSW=0 armSW=1057734815 model=1002717`.
  Reads OK: IOB 0.0 u, insulin remaining 0 u (no cartridge — expected), battery 100%.
  Log: `bench-runs/2026-08-07-0956-legacyv1-monitor.log`.
- **2026-08-07 — silent V1 re-challenge on reconnect CONFIRMED** `[t:slim X2 · API 2.5 · V1/16-char]`.
  After each link drop the harness reconnected and re-ran the **full CentralChallenge→PumpChallenge
  silently** — no new code, no on-screen confirm — re-deriving the key every time (observed dozens of
  cycles). Answers open Q1: V1 reconnect is silent. (JPAKE-resume is not applicable to this pump.)
- **2026-08-07 — FINDING (CONFIRMED): `CurrentEgvGuiDataV2` read is rejected → pump DROPS the link**
  `[t:slim X2 · API 2.5 · V1/16-char]`. Every cycle: IOB/insulin/battery reads succeed → the
  **`CurrentEgvGuiDataV2`** read (a Control-IQ-era CGM read) draws a generic **`ErrorResponse` (op 77,
  errorCode 0 = UNDEFINED_ERROR, requestCodeId 0 — the pump does NOT echo the failing opcode in cargo)**
  → the pump **disconnects (`CBError` Code 7)** → harness silently re-pairs → repeats. Identified by
  **txId correlation** (the pump DID echo the request txId `152/164` on the error frame — a positive
  datapoint for the txId-match / B7 question, on error frames at least). Real legacy-firmware behavior,
  not a harness bug. **`ErrorResponse` byte layout confirmed byte-exact vs the oracle.** Harness fix:
  the monitor now **skips `CurrentEgvGuiDataV2` on a V1-paired (legacy) pump** so the link stays up
  (kept for modern/JPAKE pumps), and `startPolling()` now invalidates its prior timer (a leaked-timer
  bug that stacked overlapping polls on each reconnect and clobbered txId→name attribution).
- **2026-08-07 — STABLE read-only sweep confirmed on the legacy pump** `[t:slim X2 · API 2.5 ·
  V1/16-char]` (advertised `tslim X2 ***693`). With the CGM read skipped, the monitor holds a stable
  connection across repeated poll cycles (no disconnect loop). Reads that PARSE: IOB, insulin remaining
  (0 u — no cartridge), battery (100%), basal (0.0 u/hr), last bolus (0.0 u, id 0), and the
  **bolus-calculator snapshot** — carbRatio 11.0 g/u, ISF 70 mg/dL/u, targetBG 110 mg/dL,
  carbEntryEnabled, maxBolus 6.0 u. Log: `bench-runs/2026-08-07-*-legacyv1-stable.log`.
  NOT yet exercised on this pump (all doable without cartridge/CGM): the fuller settings sweep
  (TimeSinceReset signing-timestamp check, ProfileStatus, IDP, GlobalMaxBolus/BasalLimit, ControlIQInfo
  V1/V2, HomeScreenMirror, HistoryLogStatus/records); a dedicated **txId-match (B7)** probe on read
  responses (only the incidental echo on the op-77 error frame is observed so far); the **signed-write
  acceptance** test (`permission-test` — signed BolusPermissionRequest → grant → release, NO delivery),
  which would prove V1 signing works for writes; and the **"Mobi-only" write probes** (ChangeTimeDate /
  temp-basal / SetModes) that the owner wants to empirically test on a t:slim.
- **2026-08-07 — COMPREHENSIVE probe (reads + signed writes, NO delivery)** `[t:slim X2 · API 2.5 ·
  V1/16-char]` — `swift run TandemBenchHarness probe`. Log: `bench-runs/2026-08-07-*-legacyv1-probe.log`.
  - **Signing:** `signingTimestamp == currentTime` (586953966) ✓ — the signed-write timestamp rule holds on V1.
  - **Read sweep — ALL parse:** profileStatus (8B), globalMaxBolus (4B), basalLimit (8B), **controlIQInfoV1
    `closedLoopEnabled=true`** (Control-IQ IS on this pump), homeScreenMirror (9B), activeIDP (10B),
    historyLogStatus (first=1523712 last=1824641). Only `CurrentEgvGuiDataV2` is rejected (see prior entry).
  - **txId-match (B7): YES** — the pump echoes the request txId on read responses (req=13→13, 14→14, 15→15,
    16→16; 4/4). Informs WIP item 12 (R3-D serialization): legacy pump echoes reliably on reads.
  - **Signed-write ACCEPTANCE: YES (headline)** — a signed `BolusPermissionRequest` returned a valid
    `BolusPermissionResponse` (op 0xa3), so **the pump validated our V1 HMAC (signing key = 16-char code
    UTF-8)** — the full signed-write path works on legacy. `granted=false` = no-cartridge business-logic
    deny, NOT a signature failure (the JPAKE pump returned granted=true on 2026-07-18 with insulin loaded).
  - **"Mobi-only" write probes — all REJECTED (op-77 control error), pump drops link after each:**
    - `SetModes` (0xCC sleepOn) → REJECTED **with its precondition (CIQ ON) MET** → strong evidence SetModes
      is genuinely unsupported on t:slim API 2.5 (supports the "Mobi-only" assumption).
    - `SetTempRate` (0xA4 80%/30m) → REJECTED, but **CONFOUNDED**: temp-basal requires Control-IQ OFF and CIQ
      was ON, so the rejection may be the precondition, not Mobi-exclusivity. Disambiguate by retrying with
      CIQ disabled (a further signed-settings write) — NOT yet done.
    - `ChangeTimeDate` (0xD6, no-op re-set to current time) → REJECTED/dropped → remote time-set via this
      command is not accepted on this firmware (informs the t:slim remote time-set question — leans NO).
  - **Harness gap:** the 26-byte CONTROL-variant `ErrorResponse` (op-77) isn't registered in ResponseParser,
    so a rejected control write surfaces as a raw `[frame] CONTROL hex=4d…` (`0x4d`=77) instead of a decoded
    ⚠️ line. For the repo session: register the 26-byte control ErrorResponse variant (`requestCodeId` was
    still zeroed by the pump, as with reads).
- **2026-08-07 — temp-basal CONFOUND RESOLVED → genuinely Mobi-only** `[t:slim X2 · API 2.5 · V1/16-char]`.
  Control-IQ was turned OFF **manually on the pump** (the *remote* `ChangeControlIQSettings` disable is itself
  REJECTED op-77, so CIQ cannot be toggled remotely on this firmware). With CIQ confirmed off
  (`controlIQInfoV1 closedLoopEnabled=false`), `SetTempRate 80%/30m` was **STILL REJECTED** (op-77 → drop) — so
  temp-basal is **genuinely unsupported on this t:slim, not merely blocked by the CIQ-ON precondition.**
  Reads, BolusPermission acceptance, and txId-echo were unchanged with CIQ off.
  **Consolidated verdict — every newer CIQ/Mobi-era signed CONTROL opcode is NACKed on API 2.5:** ChangeTimeDate
  (0xD6), SetTempRate (0xA4), SetModes (0xCC), ChangeControlIQSettings (0xCA) — always a generic op-77
  `UNDEFINED_ERROR` then a link drop. What DOES work: signed `BolusPermission` (0xA2) acceptance + all reads
  except `CurrentEgvGuiDataV2`. Net: this legacy t:slim exposes the read + signed-auth path but none of the
  CIQ/Mobi-era therapy-control writes → strong empirical support for the "Mobi-only" assumption on those
  commands. Log: `bench-runs/2026-08-07-*-legacyv1-probe-ciqoff-manual.log`.

  **This closes the no-cartridge/no-CGM bench objectives for the spare legacy pump.** Remaining items require a
  (saline) cartridge or a CGM: saline bolus delivery + history verify, temp-basal *delivery* verification, CGM
  live/history reads.
- **2026-08-07 — capability bitmask (PumpFeaturesV1, op 78/79) IS answered on the legacy pump**
  `[t:slim X2 · API 2.5 · V1/16-char]`: `featureBitmask = 0x7624dd9a`, derived `controlIQSupported`
  (bit 1024) = **true**. Partially answers open Q2 (op-79 is NOT unsupported on API 2.5). ⚠️ A CIQ bit
  set on an API-2.5 pump is surprising — flag for deeper study; do not treat as ground truth for CIQ
  availability without corroboration. Pump version fields (armSW/model) are raw and may be
  offset-shifted on this older API — treat as unverified.
- **2026-08-07 — HARNESS FINDING: the `swift test --filter PumpX2HardwareTests` suite cannot exercise
  CoreBluetooth on macOS.** It runs under Apple's `swiftpm-testing-helper`, which lacks
  `NSBluetoothAlwaysUsageDescription`, so macOS **TCC-aborts (SIGABRT)** at `startScan()` before any
  pairing (crash report `swiftpm-testing-helper-2026-08-07-094726.ips`). All prior "exit 0" runs of
  that suite only hit the no-hardware skip path. **Hardware validation must go through the
  `TandemBenchHarness` executable** (Info.plist with the Bluetooth usage string embedded via
  `-sectcreate __TEXT __info_plist`), run from an **interactive GUI Terminal** (the agent/CI shell
  can't be granted Bluetooth). The runbook/handback instruction to validate via `swift test` is wrong
  for the BLE path. For the repo-owning session: either convert the hardware harness to an
  executable-driven runner or document this. (Separately, the code review found a low-severity gap:
  the auth op17/op19 path doesn't validate the frame CRC — systemic incl. JPAKE, read-risk only, no
  delivery-wall impact.)

## Toolchain notes

- Oracle build (cliparser) requires **JDK 17+** — the pinned Gradle 9.x refuses JDK 11.
  This environment uses Homebrew `openjdk@21`; select it via
  `JAVA_HOME=$(/usr/libexec/java_home -v 21)`.
- `swift test` requires the swift-testing framework, which ships with the CLT but needs
  extra search/rpath flags there — use `scripts/test.sh` until full Xcode is installed.
