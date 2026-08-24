# Bench command-coverage harness

A resumable, per-command coverage matrix for validating **every** TandemKit command across **every** pump
+ peripheral configuration, safely, on the **saline bench**. This complements the cliparser/OracleRunner
**byte-parity** CI check (which proves the bytes we *compose* match upstream): coverage proves each command
is *accepted and behaves* on real hardware, across models/firmware/cartridge/CGM, with delivery verified by
the pump's **own history log**.

> SAFETY: the harness runs ONLY on a pump that is NOT connected to a human (saline-attested, or otherwise
> disconnected). Both software delivery walls stay armed at all times; a delivery is attempted only when the
> saline gate is explicitly opened, and is verified by the pump's own recorded units — never fabricated.
> Nothing here is "verified" without a real pump; the committed matrix is the PLAN until a bench fills it.

## The axes (why it must be resumable)

Testing happens across MANY sessions, whenever the owner can obtain a given hardware config — not all at
once. The matrix is keyed on five axes:

| axis | values |
|---|---|
| pump model | `tslim`, `mobi` |
| firmware / SW | e.g. `API 2.5` (old t:slim X2), `API 3.4` (new t:slim X2), `API 3.6` (Mobi) — a behavior on one firmware may not hold on another |
| cartridge | present (saline) / absent |
| CGM | present / absent |
| command | every request type under `Sources/TandemMessages/Requests` (125 today) |

Each session fills only the cells its **current** config allows; results **accumulate across sessions** in a
persistent matrix, so coverage grows session-by-session as hardware becomes available.

## Cell states

| state | meaning |
|---|---|
| `pass` | exercised and confirmed (typed response parsed / delivery history-log read-back == requested) |
| `fail` | exercised and the check failed |
| `gap` | no safe harness affordance in this lane (e.g. a destructive command) — recorded, never auto-fired |
| `notApplicable` | not valid for this session's model — belongs to another model's matrix |
| `deferred` | prerequisites unmet **this** session, coverable in a future session with the right config |
| `untested` | planned exercisable, not yet run |

The pure classifier (`BenchCoverage.plan(for:in:)`) decides the disposition; the runner then upgrades
exercisable cells to `pass`/`fail`. Merge precedence guarantees a real result is never clobbered by a
"can't-test-here" placeholder from a wrong-config session (see `BenchCoverageMatrix.shouldReplace`).

## Per-command prerequisite metadata (derived, not hardcoded)

`BenchCommandCatalog` derives every fact from the command's existing `MessageProps` so the classification
does not rot as messages are added:

- `modifiesDelivery` ← `props.modifiesInsulinDelivery`
- `requiresCartridge` ← `modifiesDelivery` (a delivery needs a cartridge to dispense + read back)
- `applicablePumpModels` ← `props.supportedDevices ?? [all]`
- `minApi` ← `props.minApi`
- `requiresCGM` ← a documented name-token predicate (`cgm`/`egv`/`dexcom`/`sensor`/`transmitter`/`g6`/`g7`)
- `lane` ← AUTHORIZATION → `pairing`; `modifiesInsulinDelivery` → `delivery`; signed/CONTROL → `signedWrite`; else `read`

### Delivery surface (14 = 3 universal + 11 Mobi-only)

- **Universal** (t:slim + Mobi): `InitiateBolusRequest`, `AdditionalBolusRequest`, `EnterChangeCartridgeModeRequest`
- **Mobi-only** (need a Mobi session): `SetModesRequest`, `SetActiveIDPRequest`, `FillCannulaRequest`,
  `EnterFillTubingModeRequest`, `SetTempRateRequest`, `StopTempRateRequest`, `SuspendPumpingRequest`,
  `ResumePumpingRequest`, `CreateIDPRequest`, `DeleteIDPRequest`, `RenameIDPRequest`

On a t:slim session the 11 Mobi-only deliveries record as `notApplicable`; only a Mobi saline session covers them.

> ### ⚠️ BENCH-CONFIRM (dose path): InitiateBolus (opcode-158) bolus-type bitmask
>
> **CONFIRM-only — do NOT change any code now.** `InitiateBolusRequest.swift` labels the opcode-158
> request's bolus-type bits `FOOD1(1) / CORRECTION(2) / EXTENDED(4) / FOOD2(8)` (pre-#120 names). Upstream
> pumpX2 PR #120 (`c07687db`) re-labeled the bits from a 48k-record capture to
> `NOW(1) / LATER(2) / OVERRIDE(4) / CORRECTION(8) / CARB(16) / EATING_SOON(32)` — **but that came from
> opcode-280 HISTORY records, which may not share the opcode-158 REQUEST's bitmask meaning.**
>
> There is **NO demonstrated regression**: the wire bytes TandemKit emits are byte-verified against
> upstream's two real InitiateBolus captures (carb bolus → mask `1`; no-carb correction → mask `8`), and the
> byte-parity oracle is green. This is a confirmation gap, not a code gap — porting #120's labels blindly
> onto the request would be an unverified guess.
>
> **At the bench, for each dose type — {units-only, carb, correction, extended} — capture BOTH:**
> 1. what TandemKit SENDS (the emitted `bolusTypeBitmask`; the harness logs it in the InitiateBolus oracle), and
> 2. what the pump RECORDS in its history log (`BolusDeliveryHistoryLog` bolus-type),
>
> then confirm the emitted mask is what the pump expects for that dose type. Only after this confirmation on
> real hardware should any re-labeling of the opcode-158 bits be considered. Until then the current
> byte-locked masks stand (they match every captured vector). Tracked as a Phase-11 bench-confirm item; it
> does not block the reversible-affordance coverage above.

## Lanes and the safety gate for auto-firing

- **Lane A — reads / status / query:** always bench-safe; sent read-only; PASS when a typed response parses.
- **Lane A — signed non-delivery writes (now driven via reversible affordances):** the runner drives every
  signed write that has a wired, self-reversing affordance in `BenchAffordanceCatalog` — NO
  `PUMPX2_DELIVER_SALINE` needed, because these do not dispense. Two strategies:
  - **captureReapply** — read the CURRENT value, re-send the SAME value (a provable no-op), verify the
    read-back is unchanged: `ChangeTimeDate`, `SetMaxBolusLimit`, `SetMaxBasalLimit`,
    `ChangeControlIQSettings`, `SetLowInsulinAlert`.
  - **benignProbe** — signed accept/NACK with no persistent setting change: the `BolusPermission`(+release)
    pair, `PlaySound`, `UserInteraction`, `RemoteCarbEntry`/`RemoteBgEntry` (benign metadata), and
    `CancelBolus` (with no active bolus).
  The `benchExercisableSignedWrites` allowlist is now **derived** from the affordance catalog, so it grows
  automatically. Everything else stays a documented `gap`: `.manualOnly` (destructive / irreversible /
  session-disrupting — owner-only) or `.bespokePending` (reversible but its generic driver isn't wired yet).
- **Lane B — delivery (14 commands):** attempted ONLY behind the SINGLE saline gate
  (`PUMPX2_DELIVER_SALINE=1`, plus cartridge + `PUMP_SALINE_ATTESTED=1` in the session detection). Every one
  of the 14 is now driven by a reversible affordance, verified by the pump's OWN read-back:
  - **deliverOracle** — `InitiateBolus` / `AdditionalBolus`: deliver a small saline dose, confirm via the
    pump's recorded units (history log) / current-bolus status.
  - **reversiblePair** — `SuspendPumping`↔`ResumePumping`, `SetTempRate`↔`StopTempRate`,
    `EnterFillTubingMode`↔exit, `EnterChangeCartridgeMode`↔exit: drive, confirm via read-back, ALWAYS restore.
  - **throwawayCreateDelete** — `CreateIDP`→`DeleteIDP`: create a throwaway profile, confirm, delete it.
  - **captureSetRestore** — `SetActiveIDP` / `SetModes` / `RenameIDP`: capture prior value, set, verify, restore.
  - **fill exercise** — `FillCannula`: a one-way saline prime (records + confirms; nothing to un-fill).
  Every restore is attempted even on a mid-sequence failure, and prints a LOUD warning if a restore is NACKed.
  The `PUMPX2_NO_CARTRIDGE_BOLUS_PROBE` escape (no-cartridge rejection test) is unchanged.
- **Pairing:** exercised implicitly on connect; attributed by scheme (JPAKE vs legacy V1) + API floor.

See **[Reversible affordances](#reversible-affordances)** below for the full per-command table and the
explicit MANUAL / owner-judgment exceptions, and the **[per-config runbook](#per-config-bench-runbook)** for
exactly what to run for each hardware config.

## How to run

The BLE path only runs from an **interactive GUI Terminal** (CoreBluetooth is TCC-aborted under `swift test`).

```sh
# 1) Offline: seed / regenerate the matrix artifacts (no Bluetooth, safe anywhere).
swift run TandemBenchHarness coverage-selftest

# 2) At the bench: pair + run the coverage sweep for THIS session's config.
export PUMP_PAIRING_CODE=<6-digit or 16-char code off the pump screen>
#   optional axis flags (absent = "no"):
export PUMP_CARTRIDGE_LOADED=1        # a cartridge is physically loaded
export PUMP_SALINE_ATTESTED=1         # human-attested the cartridge is SALINE (never insulin, never on a body)
export PUMP_CGM_PRESENT=1             # a CGM sensor is connected
export PUMP_FIRMWARE_TAG="SW7.6"      # optional: distinguish two same-API software versions
swift run TandemBenchHarness coverage

#   Lane B (delivery) additionally requires the ONE write-unblock flag:
export PUMPX2_DELIVER_SALINE=1        # the only flag that unblocks a delivery write; off in all CI

#   Opt-in no-cartridge delivery-rejection probe (its own flag; needs NO cartridge; can never dispense):
export PUMPX2_NO_CARTRIDGE_BOLUS_PROBE=1
```

`PUMPX2_ALLOW_ORACLE_SKIP` is never set by the harness. Artifacts are written to `bench-coverage/`
(override the dir with `PUMPX2_BENCH_COVERAGE_DIR`):

- `COVERAGE-MATRIX.json` — the machine-readable accumulator the next session resumes from.
- `COVERAGE-MATRIX.md` — the human-readable rendered matrix + a "still uncovered, and the config that would
  cover it" section.

At the end of each run the harness prints exactly which commands remain uncovered and which session config
would cover each — so you know what hardware to bring to the next sitting.

## Reversible affordances

The runner drives every state-changing command through a **reversible affordance** declared in the PURE,
unit-tested `Sources/TandemMessages/Bench/BenchAffordanceCatalog.swift`. The executable is a thin driver over
that metadata (exactly like `BenchCommandCatalog`); the affordance strategy, the restore partner, the oracle
read, and whether the runner can auto-drive it are all data, so they cannot rot as messages are added (a
completeness test asserts every delivery + signed-write command has an entry).

Strategies (`BenchAffordanceKind`):

| kind | what the runner does | oracle | examples |
|---|---|---|---|
| `deliverOracle` | deliver a small saline dose | pump's own history-log / bolus-status read-back | `InitiateBolus`, `AdditionalBolus` |
| `reversiblePair` | drive, confirm, ALWAYS send the restore partner | state read-back | `Suspend↔Resume`, `SetTempRate↔StopTempRate`, `EnterFillTubingMode↔exit`, `EnterChangeCartridgeMode↔exit` |
| `throwawayCreateDelete` | create a throwaway resource, confirm, delete it | `ProfileStatus` count | `CreateIDP→DeleteIDP` |
| `captureSetRestore` | read prior, set different, verify, restore prior | state read-back | `SetModes`, `SetActiveIDP`, `RenameIDP` |
| `captureReapply` | read current, re-send the SAME value, verify unchanged | the setting's read | `ChangeTimeDate`, `SetMaxBolusLimit`, `SetMaxBasalLimit`, `ChangeControlIQSettings`, `SetLowInsulinAlert` |
| `benignProbe` | signed accept/NACK; self-reversing or benign append | acceptance itself | `BolusPermission(+release)`, `PlaySound`, `UserInteraction`, `RemoteCarb/BgEntry`, `CancelBolus` |
| `manualOnly` | **never auto-fired** — documented GAP, owner decides at the bench | — | see below |
| `bespokePending` | reversible in principle, generic driver not yet wired — documented GAP | — | reminders, CGM alerts, IDP-segment/settings edits, sounds, sleep schedule, auto-off/snooze, prime-suspend |

**Every restore is attempted even if the drive step failed**, and a NACKed restore prints a LOUD warning
(`⚠️ VERIFY … on the pump`) so a bench operator never trusts an un-restored state.

### MANUAL / owner-judgment exceptions (never auto-fired — decide each at the bench)

These are `gap` on purpose and are listed in `COVERAGE-MATRIX.md`'s "Not auto-fired" section every run:

- **Destructive / irreversible:** `FactoryResetRequest`, `FactoryResetBRequest`, `ActivateShelfModeRequest`,
  `DisconnectPumpRequest` (drops the link the sweep needs).
- **CGM-session / pairing-disrupting:** `StartDexcomG6SensorSessionRequest`,
  `StopDexcomCGMSensorSessionRequest`, `SetSensorTypeRequest`, `SetG6TransmitterIdRequest`,
  `SetDexcomG7PairingCodeRequest`.
- **Undocumented / not-on-known-firmware:** `SendTipsControlGenericTestRequest`,
  `StreamDataPreflightRequest` (`minApi` API_FUTURE — defers on all known firmware).

To exercise any of these the owner drives it manually and records the result by hand — they are surfaced,
never silently dropped.

## Other affordances wired into `coverage`

1. **Raw `currentTargetBg` cargo logging** — logs the raw `CurrentActiveIdpValuesResponse` cargo hex + the
   byte-4 vs byte-5 targetBg decode (BENCH-SESSION-PLAN Obj 4 / D-07) before trusting the typed value.
2. **`setDeviceContext(model:apiVersion:)` send-gate wiring** — after reading `ApiVersion`, the runner
   activates the D-08 device/API send gate so model/API-restricted messages are refused client-side (the
   same gate faBolus relies on in production).
3. **`PUMPX2_NO_CARTRIDGE_BOLUS_PROBE`** — drives a bolus through both software walls with no cartridge and
   records the pump's rejection (recorded under a distinct synthetic command so it does not mark the real
   delivery oracle covered).

## Per-config bench runbook

The matrix accumulates across sessions; each hardware config you can obtain fills its own cells. Below is
the exact recipe for **every config the owner might get**. The owner has an **old t:slim X2 now** — start at
config **T-1** — but the whole grid is spelled out so any future pump is immediately actionable.

### Universal pre-flight safety checklist (EVERY session)

- [ ] The pump is a **bench / spare** — NOT the pump anyone wears, and NOT on a body.
- [ ] If a cartridge is loaded it is **SALINE** (never insulin) — human-attested. Dispensing into a container
      on a scale, never into tubing on a person.
- [ ] `PUMP_PAIRING_CODE` is the code off THIS pump's screen (6-digit → JPAKE; 16-char → legacy V1).
- [ ] Run from an **interactive GUI Terminal** (CoreBluetooth is TCC-aborted under `swift test`).
- [ ] `PUMPX2_ALLOW_ORACLE_SKIP` is **unset** (the harness never sets it; neither should you).
- [ ] After a delivery/write session, glance at the run log for any `⚠️ VERIFY …` restore warning and
      confirm that state on the pump UI.

### Common invocation

```sh
export PUMP_PAIRING_CODE=<code off the pump screen>
# axis flags (absent = "no"):
export PUMP_CARTRIDGE_LOADED=1    # a cartridge is physically loaded
export PUMP_SALINE_ATTESTED=1     # human-attested SALINE (never insulin, never on a body)
export PUMP_CGM_PRESENT=1         # a CGM sensor is connected
export PUMP_FIRMWARE_TAG="SW7.6"  # optional: distinguish two same-API software versions
# delivery (Lane B) — the ONE write-unblock flag (off in all CI):
export PUMPX2_DELIVER_SALINE=1
swift run TandemBenchHarness coverage
```

Set only the flags the config has. The runner auto-detects model + API from the pump and records only the
cells this config can fill; the rest stay `deferred`/`notApplicable`/`gap` for a future session.

### The configs

Legend for "fills": **reads** = all Lane-A status reads; **signed-writes** = the ~12 reversible signed
writes (captureReapply + benignProbe) — these need NO cartridge/CGM/saline; **universal delivery** =
`InitiateBolus`, `AdditionalBolus`, `EnterChangeCartridgeMode`; **Mobi delivery** = the 11 Mobi-only
delivery commands.

| # | config | command + flags | fills | notes |
|---|---|---|---|---|
| **T-1** | **old t:slim X2 · no cartridge · no CGM** (RUNNABLE NOW) | `coverage` with `PUMP_PAIRING_CODE` only | reads + **all reversible signed-writes** (no saline needed) | This is the biggest immediately-available win: it exercises every captureReapply + benignProbe signed write on the pump the owner already has. Delivery cells `deferred` (no cartridge); Mobi-only cells `notApplicable`. Legacy V1 pairing attributed. |
| **T-2** | **old t:slim X2 · saline cartridge · no CGM** | `coverage` + `PUMP_CARTRIDGE_LOADED=1 PUMP_SALINE_ATTESTED=1 PUMPX2_DELIVER_SALINE=1` | + **universal delivery** (bolus oracle, additional-bolus, cartridge-change pair) | Loads the 3 universal delivery affordances. `EnterChangeCartridgeMode` enters/exits reversibly; the bolus oracle delivers 0.10 u saline and reads it back. Mobi-only cells still `notApplicable`. |
| **T-3** | **old t:slim X2 · saline cartridge · CGM** | T-2 flags + `PUMP_CGM_PRESENT=1` | + **CGM-family reads** | Fills the CGM reads (`CurrentEgvGuiDataV2`, `CGMStatus`, …) that `deferred` without a sensor. CGM-family signed writes stay MANUAL (session-disrupting). |
| **N-1** | **new t:slim X2 (JPAKE) · no cartridge · no CGM** | `coverage`, JPAKE code | reads + all reversible signed-writes; JPAKE pairing | Same signed-write coverage as T-1 but on API 3.4 firmware + JPAKE pairing (a behavior on one firmware may not hold on another — the matrix keys on firmware). |
| **N-2** | **new t:slim X2 · saline cartridge · no CGM** | + saline delivery flags | + universal delivery on API 3.4 | Re-proves the universal delivery affordances on the newer firmware. |
| **N-3** | **new t:slim X2 · saline cartridge · CGM** | + `PUMP_CGM_PRESENT=1` | + CGM reads on API 3.4 | |
| **M-1** | **Mobi (JPAKE) · no cartridge · no CGM** | `coverage`, Mobi JPAKE code | reads + all reversible signed-writes on Mobi API 3.6 | |
| **M-2** | **Mobi · saline cartridge · no CGM** | + saline delivery flags | + universal delivery **+ all 11 Mobi-only delivery** | The ONLY config that covers the 11 Mobi-only deliveries: `SetModes`, `SetActiveIDP`, `FillCannula`, `EnterFillTubingMode`↔exit, `SetTempRate`↔`StopTempRate`, `SuspendPumping`↔`ResumePumping`, `CreateIDP`→`DeleteIDP`, `RenameIDP`. Preconditions the runner notes: `SetTempRate` needs Control-IQ **OFF**; `SetModes` needs it **ON**; `SetActiveIDP` needs **≥2 IDPs**. Each is reversible + read-back-verified. |
| **M-3** | **Mobi · saline cartridge · CGM** | + `PUMP_CGM_PRESENT=1` | + CGM reads on Mobi | Highest-coverage single session. |

At the end of every run the harness prints exactly which commands remain uncovered and which config would
cover each, and writes `COVERAGE-MATRIX.{json,md}`; the `.md` "Not auto-fired" section lists every MANUAL /
owner-judgment command so nothing is silently dropped.

### Two-build app plan (on-device app-UI objectives)

Command-coverage above is the *wire* surface. On-device **app-UI** objectives are run from BOTH faBolus
builds, because the shipped app deliberately hides surfaces the full build exposes:

- **`main` (shipped, narrow):** validate the production dose path + the surfaces a real user sees.
- **`experimental` (full surfaces):** exercise the advanced-control / Mobi / IDP / settings UI that `main`
  gates off, against the same bench pump.

Run each app-UI objective on the build that exposes it; the harness `coverage` sweep is build-independent
(it talks to the pump directly, not through the app).

## What is unit-tested (CI, no CoreBluetooth)

`Tests/TandemMessagesTests/BenchCoverageTests.swift` proves the pure logic the runner rests on: command
enumeration (count + no duplicates), per-model applicability, `requiresCGM`, lane classification,
prerequisite gating (`plan`), matrix cell classification, and accumulation/merge across sessions. The
`BenchAffordanceCatalogTests` suite additionally proves the reversible-affordance layer: every
state-changing command has an affordance (completeness), the 14 delivery affordances are saline-gated, the
reversible pairs are symmetric, all partner/oracle cross-references are real catalog commands, destructive
commands are `manualOnly` and never runner-drivable, the `benchExercisableSignedWrites` allowlist is derived
+ grown, and the Lane-B delivery planning is correct across configs. The BLE driving itself can only be
validated on a real pump at the bench — **nothing in the committed matrix is a verified PASS until a bench
session records one.**
