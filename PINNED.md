# Pinned upstream

The Swift port tracks a specific, known-good commit of the upstream protocol library. Upstream changes
are reviewed and checked again before they're adopted; [`docs/UPSTREAM-SYNC-RUNBOOK.md`](docs/UPSTREAM-SYNC-RUNBOOK.md)
says how.

| What | Value |
| --- | --- |
| Upstream repo | [`jwoglom/pumpx2`](https://github.com/jwoglom/pumpx2) |
| Submodule path | `vendor/pumpx2-oracle` |
| Pinned commit | `456018a5eb10adcec578c54855af1a2f50befa31` (upstream `main`, 2026-10) |
| Ported by | Swift port in `Sources/` (hand-ported, not generated) |

## Upstream controlX2 watch

controlX2 ([`jwoglom/controlx2`](https://github.com/jwoglom/controlx2)) is the companion Android app. It
has no license, so it's read for structure and nothing is copied from it; it is never vendored or
compiled. `.github/workflows/upstream-drift.yml` reads the two commits below out of this table and reports
how far upstream has moved. `dev` is the primary baseline, upstream's active integration branch; `main` is
tracked for reference.

| What | Value |
| --- | --- |
| Upstream repo | [`jwoglom/controlx2`](https://github.com/jwoglom/controlx2) |
| Last-reviewed dev commit | `8d3ad3115bd7ac200e8bd16bd372dbc0da58f058` |
| Last-reviewed main commit | `45e3795bad357472c1ff736dbfd7013e574dd28c` |
| Reviewed date | 2026-08-16 |
| Review notes | The 10-commit `dev` delta was app and UI only, with no protocol change. |

## Pump firmware

Recorded from the pump's Pump Info screen (2026-07-18). A firmware update can change the protocol, so
results here are tied to this firmware.

| Field | Value |
| --- | --- |
| Pump model | Tandem **t:slim X2** |
| t:slim Software | **Control-IQ+ 7.10.2** |
| ARM S/W Version | `da8923cc9d010d07` |
| MSP S/W Version | `da8923cc9d010d07` |
| S/W Part Number | `1017490 000` |
| Pairing type | **6-digit JPAKE** (firmware ≫ v7.7) |

Pairing uses the EC-JPAKE handshake (`TandemAuth.JpakeAuth`, mbedTLS secp256r1/SHA-256).

## Spare bench pump: legacy pairing (added 2026-08-07)

A second t:slim X2 on the bench runs older firmware (before v7.7, API 2.5) and pairs with a 16-character
code through the legacy CentralChallenge → PumpChallenge handshake (`PairingAuth.createV1`,
`LegacyPairingCoordinator`; `PairingAuth.detectType` picks the scheme from the code).

The two pumps are different firmware families, and a result on one doesn't carry over to the other. The
bench harness records a `PumpFirmwareProfile` (API version, pump software version, pairing scheme) at the
start of each run, and every entry below names the pump it was seen on.

## Validation log

Every entry names the pump, firmware and pairing scheme, e.g. `[t:slim X2 · CIQ+ 7.10.2 · JPAKE]`. The
2026-07-18 entries are the primary pump.

- **2026-07-18: read-only monitor on hardware.** `TandemBenchHarness monitor`: scan, connect, discover,
  6-digit JPAKE pairing (signing key derived), and status reads parsed. Insulin remaining (70 U) and
  battery (35%) matched the pump; every state-changing write stayed blocked.
  - The pump's displayed IOB matches `swan6hrIOB`, not `mudaliarIOB` (4.32 U observed, as on the pump).
- **2026-07-18: more reads.** Glucose (CGM EGV V2), basal, last bolus and the bolus-calculator snapshot
  (carb ratio, ISF, target BG) matched the pump's screens. The signing timestamp is
  `TimeSinceResetResponse.currentTime`.
- **2026-07-18: signed write.** A signed BolusPermissionRequest was granted and released, with no insulin
  delivered.
- **2026-07-18: signed bolus delivered.** `bolus 100` delivered 0.10 U: permission, signed InitiateBolus
  (FOOD2) accepted, LastBolusStatus reported 0.10 U (id 1774), and the pump's screen agreed. A signed
  CancelBolus round-trips. Every outgoing message was byte-exact against the oracle.
- **Still to run**, on a pump with a saline cartridge: a cancel mid-delivery, to check partial-delivery
  reporting, and an accuracy check at a larger dose (faBolus `docs/UNVERIFIED-GUESSES.md` #21); and
  whether the pump echoes the request txId in `frame[1]` on a delivery reply (`WIP-REGISTER.md`).

The 2026-08-07 entries are the spare pump, `[t:slim X2 · API 2.5 · V1/16-char]`, with no cartridge and no
CGM.

- **2026-08-07: legacy pairing on hardware.** `TandemBenchHarness monitor`, read-only: scan, connect,
  legacy pairing (16-byte signing key, the code's UTF-8 bytes), and status reads parsed. Profile:
  `API 2.5 (t:slim X2 family) · pairing=LONG_16CHAR · pumpSW=0 armSW=1057734815 model=1002717`. IOB
  0.0 U, insulin remaining 0 U (no cartridge), battery 100%.
- **2026-08-07: reconnects re-pair silently.** After each drop the harness reconnected and re-ran the
  whole legacy challenge with no new code and no confirm on the pump, for dozens of cycles.
- **2026-08-07: `CurrentEgvGuiDataV2` is refused, and the pump drops the link.** Every cycle, the IOB,
  insulin and battery reads succeed, then `CurrentEgvGuiDataV2` draws an op-77 `ErrorResponse`
  (errorCode 0, UNDEFINED_ERROR; requestCodeId 0, so the pump doesn't name the failing opcode) and the
  pump disconnects (`CBError` 7). It was matched to the request by txId: the pump echoed the request's
  txId on the error frame. The `ErrorResponse` layout is byte-exact against the oracle.
- **2026-08-07: stable read sweep.** With that read skipped (advertised `tslim X2 ***693`), the link stays
  up. These parse: IOB, insulin remaining (0 U), battery (100%), basal (0.0 U/hr), last bolus (0.0 U,
  id 0), and the bolus-calculator snapshot (carb ratio 11.0 g/U, ISF 70 mg/dL/U, target 110 mg/dL, carb
  entry on, max bolus 6.0 U).
- **2026-08-07: probe of reads and signed writes, no delivery** (`TandemBenchHarness probe`).
  - Signing: `signingTimestamp == currentTime` (586953966).
  - Reads that parse: profileStatus (8 B), globalMaxBolus (4 B), basalLimit (8 B), controlIQInfoV1
    (`closedLoopEnabled=true`), homeScreenMirror (9 B), activeIDP (10 B), historyLogStatus (first 1523712,
    last 1824641). Only `CurrentEgvGuiDataV2` is refused.
  - txId echo on reads: yes, 4 of 4 (13→13, 14→14, 15→15, 16→16).
  - Signed-write acceptance: a signed `BolusPermissionRequest` got a valid `BolusPermissionResponse`
    (op 0xA3), so the pump accepted the legacy HMAC. `granted=false` is the no-cartridge refusal, not a
    signature failure.
  - Refused with op-77, then a dropped link: `SetModes` (0xCC, with Control-IQ on, its precondition),
    `SetTempRate` (0xA4, 80% for 30 min) and `ChangeTimeDate` (0xD6, a re-set to the current time).
- **2026-08-07: temp rate refused with Control-IQ off too.** With Control-IQ turned off on the pump itself
  (a remote `ChangeControlIQSettings` is also refused with op-77), `SetTempRate` was still refused. On
  API 2.5, every signed control write of the Control-IQ and Mobi era is refused with a generic op-77
  and a dropped link: ChangeTimeDate (0xD6), SetTempRate (0xA4), SetModes (0xCC) and
  ChangeControlIQSettings (0xCA). What works: signed `BolusPermission` (0xA2) and every read but
  `CurrentEgvGuiDataV2`. A saline cartridge or a CGM is needed for the rest: delivery, history, and CGM
  reads.
- **2026-08-07: the feature bitmask is answered.** PumpFeaturesV1 (op 78/79) returns
  `featureBitmask = 0x7624dd9a`, with the Control-IQ bit (1024) set. A Control-IQ bit on an API 2.5 pump
  is surprising; don't treat it as proof of Control-IQ without another source. The pump version fields
  (armSW, model) are raw and may be offset on this older API.
- **2026-08-07: hardware runs need the executable.** `swift test` runs under `swiftpm-testing-helper`,
  which has no Bluetooth usage string, so macOS aborts it at `startScan()`. Hardware runs go through the
  `TandemBenchHarness` executable (its Info.plist embeds the usage string) from a Terminal that has
  Bluetooth permission.

## Toolchain notes

- The oracle build (`cliparser`) needs a JDK; the parity tests need JDK 21. With Homebrew's `openjdk@21`,
  select it with `JAVA_HOME=$(/usr/libexec/java_home -v 21)`.
- With only the Command Line Tools, `swift test` needs extra search and rpath flags for swift-testing:
  use `scripts/test.sh`.
