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

## Lanes and the safety gate for auto-firing

- **Lane A — reads / status / query:** always bench-safe; sent read-only; PASS when a typed response parses.
- **Lane A — curated signed writes:** only `BolusPermissionRequest` (+ release) and `PlaySoundRequest` are
  auto-fired (accept/NACK probe; self-reversing). Every other signed non-delivery write (settings edits,
  factory reset, disconnect, shelf mode, IDP CRUD, alerts/reminders …) is a `gap` — it needs a hand-written
  reversible affordance; drive it via the curated `probe` subcommand, never a blind auto-fire.
- **Lane B — delivery:** attempted ONLY behind the saline gate (cartridge + `PUMP_SALINE_ATTESTED=1` +
  `PUMPX2_DELIVER_SALINE=1`). The runner drives the `InitiateBolus` **history-log oracle** (deliver 0.10 u
  saline, then poll `LastBolusStatusV2` until recorded units == requested). Other delivery commands are
  recorded as `gap` in `coverage` and covered by the declarative `TandemHardwareTests` BenchCases.
- **Pairing:** exercised implicitly on connect; attributed by scheme (JPAKE vs legacy V1) + API floor.

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

## Missing affordances wired into `coverage`

1. **Raw `currentTargetBg` cargo logging** — logs the raw `CurrentActiveIdpValuesResponse` cargo hex + the
   byte-4 vs byte-5 targetBg decode (BENCH-SESSION-PLAN Obj 4 / D-07) before trusting the typed value.
2. **`setDeviceContext(model:apiVersion:)` send-gate wiring** — after reading `ApiVersion`, the runner
   activates the D-08 device/API send gate so model/API-restricted messages are refused client-side (the
   same gate faBolus relies on in production).
3. **`PUMPX2_NO_CARTRIDGE_BOLUS_PROBE`** — drives a bolus through both software walls with no cartridge and
   records the pump's rejection (recorded under a distinct synthetic command so it does not mark the real
   delivery oracle covered).

## What is unit-tested (CI, no CoreBluetooth)

`Tests/TandemMessagesTests/BenchCoverageTests.swift` proves the pure logic the runner rests on: command
enumeration (count + no duplicates), per-model applicability, `requiresCGM`, lane classification,
prerequisite gating (`plan`), matrix cell classification, and accumulation/merge across sessions. The BLE
driving itself can only be validated on a real pump at the bench — **nothing in the committed matrix is a
verified PASS until a bench session records one.**
