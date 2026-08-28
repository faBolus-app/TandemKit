# Standing open work — TandemKit

This is **not** a phase diary. Capture-day archaeology, P16 close-out tables, and the 09.8-01 upstream-sync novel live in git history of this file.

Branch policy: [`BRANCHES.md`](BRANCHES.md) (pointer to faBolus). Hardware log: [`PINNED.md`](PINNED.md). Saline session: [`docs/BENCH-SESSION-PLAN.md`](docs/BENCH-SESSION-PLAN.md).

faBolus consumes this kit by `url:` + `revision:` in `project.yml`, not a version tag. The old `.unsafeFlags` / SwiftPM pin is **MET** for that contract — do not revive it as unmet.

## Open

| Item | Why it stays listed |
|---|---|
| CONTROL_STREAM cartridge-fill progress | Requests are ported; the stream consumer is not. faBolus has no cartridge UI. |
| Protocol port is partial | `scripts/coverage_report.py` lists upstream message classes with no Swift type. |
| Larger-dose accuracy + mid-delivery cancel | Bench-gated. Mid-delivery cancel is the indeterminate race. Booked in BENCH-SESSION-PLAN. |
| txId-match vs FIFO correlation | t:slim echo confirmed on reads; delivery-class serialization stays until a saline confirmation. Matching a txId the pump does not echo would fail every correlation. |
| `PUMPX2_ALLOW_ORACLE_SKIP=1` | **Never set.** Silently drops byte-parity for four suites. CI must not set it. Local Swift-only iteration only. |
| Bench harness | Manual, `PUMPX2_DELIVER_SALINE=1`. No test target by design. |

## Do not "fix"

- Do not set `PUMPX2_ALLOW_ORACLE_SKIP` to green a build.
- Do not drop delivery-class serialization until saline confirms txId echo on delivery-class traffic.
- Do not treat `scripts/test.sh` or committed mbedTLS symlinks as open defects.
