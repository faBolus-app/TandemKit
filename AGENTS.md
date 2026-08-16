# AGENTS.md — TandemKit

Working notes for AI coding agents (and humans). Companion to [`llms.txt`](llms.txt) (the map). This is
a Swift port of the Tandem t:slim X2 / Mobi Bluetooth protocol (from jwoglom's pumpX2), consumed by the
faBolus app. **Safety-critical: a wrong byte can misdose insulin.** Read the doc-comment of anything
you touch first.

## The golden rule
Every request's bytes and every response's parse are verified **byte-exact** against the vendored Java
oracle (`vendor/pumpx2-oracle/`). **Never change message bytes without adding/keeping a matching
oracle-parity test.** Doing otherwise can silently misdose.

## Commands
- **Full suite incl. oracle parity:** `./scripts/test.sh` (needs **JDK 21** for the oracle).
- **Swift-only / single test:** `swift test` · `swift test --filter <Name>`
- Golden regeneration + tooling live under `scripts/` / `tools/` where present.

## Layout (SPM products)
- `Sources/TandemMessages/` — messages + framing. `Requests/…`, `Responses/Responses.swift`,
  `Core/MessageProps.swift` (per-message `opCode`, `size`, `signed`, `characteristic`,
  `modifiesInsulinDelivery`, `responseOpCode`). `ResponseParser` dispatches on **(characteristic,
  opCode)** — opcodes are NOT globally unique.
- `Sources/TandemAuth/` — `PairingCoordinator` (client JPAKE state machine), `JpakeAuth`/
  `EcJpakeContext` (EC-JPAKE via vendored mbedTLS), `Crypto` (HMAC/HKDF).
- `Sources/TandemBLE/` — `PumpBLEClient` (CoreBluetooth central; state restoration; the `WritePolicy`
  interlock `.readOnly`/`.allowNonDelivery`/`.allowDelivery`).
- `Tests/TandemMessagesTests/` — parity tests (`OracleParityTests`, `ResponseParityTests`, …).

## How to add a message
1. Add the request/response under `Sources/TandemMessages/…` with correct `MessageProps` (opcode, size,
   `signed`, `characteristic`, `modifiesInsulinDelivery`, `responseOpCode`).
2. Register the response type in `ResponseParser`.
3. Add a **byte-exact test from an oracle vector** (encode → compare cargo; parse → compare fields).
4. Signed / insulin-affecting messages must set `modifiesInsulinDelivery: true` so the client's
   `WritePolicy` gate applies.

## Conventions
- Match the oracle exactly; each type's doc-comment cites its Java origin. If a field's meaning is
  unverified on-device, say so in the doc-comment — don't guess.
- Swift 6 concurrency: keep CoreBluetooth delegate isolation correct.

## Consumed by
`../faBolus` (the app, via SwiftPM). App-level safety layering + UI live there; the wire format lives
here. Keep them in step.

## Governance & versioning (§1.3/§1.4)
Branch policy is **canonical in faBolus, not here.** The three-branch model
(`deprecated`/`main`/`experimental`), the §1.2 experimental gate, and the §1.4 promotion criteria are
defined once in [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md) and govern all three code repos in
lockstep (§1.3). See the local [`BRANCHES.md`](BRANCHES.md) stub and [`CHANGELOG.md`](CHANGELOG.md). Do
not restate or fork those rules.

**Version-pinning contract (§1.3).** The intended shape is an annotated `vX.Y.Z` tag consumed by
`url:` + version, with a committed `Package.resolved` and a documented local-path override for dev.

**Status: MET (Phase 3, pin bump `6efdd43` → current TandemKit pin `1a09dba`).** faBolus now consumes
this package via a `url:` + `revision:` pin in `faBolus/project.yml` (with a documented
`FABOLUS_TANDEM_LOCAL=1` local-path override for day-to-day dev), not an annotated `vX.Y.Z`
tag+version — the **revision** form, a deliberate D-01 owner override of the tag+version approach,
because SwiftPM refuses a URL+**version** dependency on a package with `.unsafeFlags` but a
URL+**revision** dependency is unrestricted. There are still **two** `.unsafeFlags` sites:
`Package.swift:37` (the `-DMBEDTLS_CONFIG_FILE` flag on `CMbedTLSJPAKE` — the real blocker, because
it is in the closure of the `TandemAuth`/`TandemBLE` products faBolus consumes) and
`Package.swift:69` (a harness linker flag on the `TandemBenchHarness` executable, which faBolus does
not consume). Removing them requires vendoring the Mbed TLS config/headers in-tree and rehoming the 13
committed `CMbedTLSJPAKE/mbedtls_lib/*.c` symlinks — a build-graph/vendoring refactor gated only by the
oracle byte-parity + hardware-pairing tests. **That refactor remains deferred** (it is not required
for §1.3, since the revision-form pin already satisfies the contract) and is NOT attempted here.
Tracked as WIP item 8.
