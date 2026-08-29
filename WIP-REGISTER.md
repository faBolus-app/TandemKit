# Standing open work — TandemKit

This is **not** a phase diary. Capture-day archaeology, P16 close-out tables, and the 09.8-01 upstream-sync novel live in git history of this file.

Branch policy: [`BRANCHES.md`](BRANCHES.md) (pointer to faBolus). Hardware log: [`PINNED.md`](PINNED.md). Saline session: [`docs/BENCH-SESSION-PLAN.md`](docs/BENCH-SESSION-PLAN.md).

faBolus consumes this kit by `url:` + `revision:` in `project.yml`, not a version tag. The old `.unsafeFlags` / SwiftPM pin is **MET** for that contract — do not revive it as unmet.

## Open

| Item | Why it stays listed |
|---|---|
| CONTROL_STREAM cartridge-fill progress | Requests are ported; the stream consumer is not. faBolus has no cartridge UI. |
| Protocol port is partial | `scripts/coverage_report.py` lists upstream message classes with no Swift type. |
| Undecoded fields inside PORTED types | `coverage_report.py` cannot see these — the type exists, some of its wire bytes are just never read. Still open: `PumpingSuspendedHistoryLog` (typeId 11) reads bytes 2/6/14/16 but not `preSuspendState` uint32@10 or `rpaTimeout` byte@17; `PumpingResumedHistoryLog` (typeId 12) reads 2/6/14 but not `preResumeState` uint32@10; `BolusActivatedHistoryLog` (typeId 55) reads 2/6/10/14/18 but nothing at byte 12 (`selectedIob` — a real field, not padding; the two `selectedIOB` reads in this file are @24 and @22 on *other* types). Existing reads are correct; these are additive gaps. |
| Larger-dose accuracy + mid-delivery cancel | Bench-gated. Mid-delivery cancel is the indeterminate race. Booked in BENCH-SESSION-PLAN. |
| txId-match vs FIFO correlation | t:slim echo confirmed on reads; delivery-class serialization stays until a saline confirmation. Matching a txId the pump does not echo would fail every correlation. |
| `PUMPX2_ALLOW_ORACLE_SKIP=1` | **Never set.** Silently drops byte-parity for the FOUR suites gated on `OracleRunner.isAvailable`: `OracleParityTests`, `ResponseParityTests`, `HistoryLogOracleParityTests`, `SignedResponseHmacVerifyTests` (the last is HMAC verification — the worst to lose silently). `JpakeInteropTests` is NOT in this set: it gates on its own `JpakeOracle.available` jar check, which this variable does not touch. Re-derive with `grep -rl "enabled(if: OracleRunner.isAvailable)" Tests/` rather than trusting the number here. CI must not set it; local Swift-only iteration only. |
| Bench harness | Manual, `PUMPX2_DELIVER_SALINE=1`. No test target by design. |

## Do not "fix"

- Do not set `PUMPX2_ALLOW_ORACLE_SKIP` to green a build.
- Do not drop delivery-class serialization until saline confirms txId echo on delivery-class traffic.
- Do not treat `scripts/test.sh` or committed mbedTLS symlinks as open defects.
