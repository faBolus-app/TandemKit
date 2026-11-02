# Standing open work — TandemKit

This is **not** a diary. Capture-day notes, old close-out tables and the upstream-sync history live in the git history of this file.

Branch policy: [`BRANCHES.md`](BRANCHES.md) (pointer to faBolus). Hardware log: [`PINNED.md`](PINNED.md). Open questions about pump behavior the app relies on: faBolus [`docs/UNVERIFIED-GUESSES.md`](https://github.com/faBolus-app/faBolus/blob/main/docs/UNVERIFIED-GUESSES.md).

faBolus pins a release of this kit by version (`exact:` in its `Packages/PumpSession` and `Packages/PhoneApp` manifests). A target with `.unsafeFlags` would break that: SwiftPM refuses them in a version-pinned dependency.

## Open

| Item | Why it stays listed |
|---|---|
| CONTROL_STREAM cartridge-fill progress | Requests are ported; the stream consumer is not. faBolus has no cartridge UI. |
| Protocol port is partial | `scripts/coverage_report.py` lists upstream message classes with no Swift type. |
| Undecoded fields inside PORTED types | `coverage_report.py` cannot see these — the type exists, some of its wire bytes are just never read. Still open: `PumpingSuspendedHistoryLog` (typeId 11) reads bytes 2/6/14/16 but not `preSuspendState` uint32@10 or `rpaTimeout` byte@17; `PumpingResumedHistoryLog` (typeId 12) reads 2/6/14 but not `preResumeState` uint32@10; `BolusActivatedHistoryLog` (typeId 55) reads 2/6/10/14/18 but nothing at byte 12 (`selectedIob` — a real field, not padding; the two `selectedIOB` reads in this file are @24 and @22 on *other* types). Existing reads are correct; these are additive gaps. |
| Larger-dose accuracy + mid-delivery cancel | Needs a pump with a saline cartridge. faBolus `docs/UNVERIFIED-GUESSES.md` #21. |
| txId echo on a delivery reply | `LinkReducer.matches` takes a reply only with the request's txId echoed in `frame[1]`. A t:slim echoes it on reads (4 of 4) and on the op-77 error frame (`PINNED.md`, 2026-08-07); a delivery reply (`InitiateBolus`, `CancelBolus`) isn't confirmed. One without the echo would go unmatched and the request would time out. |
| `PUMPX2_ALLOW_ORACLE_SKIP=1` | **Never set.** Silently drops byte-parity for the FOUR suites gated on `OracleRunner.isAvailable`: `OracleParityTests`, `ResponseParityTests`, `HistoryLogOracleParityTests`, `SignedResponseHmacVerifyTests` (the last is HMAC verification — the worst to lose silently). `JpakeInteropTests` is NOT in this set: it gates on its own `JpakeOracle.available` jar check, which this variable does not touch. Re-derive with `grep -rl '^@Suite(.enabled(if: OracleRunner.isAvailable))' Tests/` rather than trusting the number here — anchored to the line start and to `@Suite`, because the loose form also matches a prose mention in `HardwareGate.swift` and a single `@Test` in `OracleAvailabilityGateTests`, which is how this count got inflated to six before. CI must not set it; local Swift-only iteration only. |
| Bench harness | Manual: `scan`, `monitor` and `dismiss` against a real pump (`Bench/README.md`). No test target by design. |

## Do not "fix"

- Do not set `PUMPX2_ALLOW_ORACLE_SKIP` to green a build.
- Do not treat `scripts/test.sh` or committed mbedTLS symlinks as open defects.
