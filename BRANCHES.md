# Branch model — TandemKit

TandemKit uses the **three-branch model** shared by all three faBolus code repos:

| Branch | What it is |
|---|---|
| `deprecated` | A frozen pre-round-3 snapshot of `main`; forensics / bisection only — **not a supported fallback**. Tag `deprecated/2026-08-04-v0.1.0-build1`. |
| `main` | The current CI-green baseline. Every outgoing message is byte-exact against the cliparser oracle. |
| `experimental` | Work that is not yet promotable under the §1.4 criteria. |

The moving last-known-good rollback pointer is the `safe-baseline/*` tag, **not** `deprecated`.

## The policy is canonical in faBolus — this file only points to it

The branch policy, the **§1.2 experimental gate**, and the **§1.4 promotion criteria** are defined
once in [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md) and govern all three repos —
**faBolus**, **TandemKit**, **faBolusGarmin** — in lockstep (§1.3). This stub is a pointer, not a
fork: **do not restate or diverge the rules here.** For contributor workflow and the versioning
contract see [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`AGENTS.md`](AGENTS.md); for the release
history see [`CHANGELOG.md`](CHANGELOG.md).
