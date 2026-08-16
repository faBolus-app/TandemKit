# Upstream sync runbook

What to do when `.github/workflows/upstream-drift.yml` fires (a daily/`workflow_dispatch` issue
titled "Upstream pumpx2/controlx2 drift detected"). The detector **opens issues only — it never
auto-merges anything** (see the workflow's top-of-file comment). Merge-after-green-CI is an
**operator discipline**, not a configured GitHub auto-merge setting.

## DEV-NOT-TRUSTED rule

**Every item in the issue's dev tier is a triage CANDIDATE, never adopted on sight.** `dev` is
upstream's active integration branch — useful as an early heads-up on what's coming — but it is
**not** trusted ground truth. Trusted ground truth for this port is, in order:

1. Real hardware captures (the bench pumps, `PINNED.md`'s validation log).
2. The `cliparser` oracle (`vendor/pumpx2-oracle`) — byte-exact parity is the golden rule.
3. Upstream `main` / our own pinned commit.

A `dev`-sourced change is surfaced to the owner **before** any adoption. `main`-tier drift is
higher-confidence (upstream already merged it) but still goes through the same triage steps below
— "higher confidence" is not "adopt without review."

## Triage steps (run in order)

**(a) Enumerate the gap.**
Run `python3 scripts/coverage_report.py --missing` to see which upstream message classes have no
Swift port yet. Cross-reference against the drift issue's changed-files list (main tier) and the
dev-tier "coming soon" list.

**(b) Prioritize per D-03** (locked order — do not force-adopt lower-priority churn):

1. New/changed opcodes + response-field parsing.
2. Firmware-compatibility gates.
3. Connection / pairing / reconnect fixes.
4. Anything on a bolus or status-read path.

Lower-priority upstream churn (cosmetic renames, unrelated app/UI-only controlX2 changes, docs) is
triaged and recorded, not force-adopted.

**(c) For each ADOPTED item, add or extend a test before merging the port.** An oracle-parity test
(`Tests/TandemMessagesTests/OracleParityTests.swift`) for anything the oracle can construct, or a
history-log-record test for history-log types the oracle can't reach. **Never change message bytes
without a matching byte-exact test** (`CONTRIBUTING.md`'s golden rule) — this applies to
dev-sourced adoptions exactly as it does to main-sourced ones.

**(d) Route dose-path items through the full review discipline.** Anything that sets
`modifiesInsulinDelivery: true`, or touches a bolus/status-read path, follows faBolus
`BRANCHES.md` §1.4's promotion criteria: it stays on `experimental` (never lands directly on
`main`), gets an adversarial audit in addition to the oracle-parity test, and is
**saline-bench-only — never real insulin — until validated in Phase 11.** This applies
identically whether the source was upstream `main` or upstream `dev`; `dev` provenance is never a
shortcut around this gate.

**(e) Update the baselines only AFTER the adoption PR merges.** Bump `PINNED.md`'s pumpx2 submodule
pin (`vendor/pumpx2-oracle`) and/or the `## Upstream controlX2 watch` tracked dev/main SHA at merge
time, not before — the baseline is what the detector measures against on the *next* cycle, so
moving it early would silently swallow anything landed in between.

## dev → main promotion rule

`dev` is the **default landing zone** for adopted upstream deltas — matching how upstream itself
develops. A change is **fast-tracked to `main`** only when it is urgent (actively breaking
something in production) or a confident, well-evidenced fix for something outright wrong (the kind
of "this is just a bug and the fix is obviously correct" finding, backed by a hardware capture or
oracle byte-diff). Anything else waits on `experimental`/`dev` until it has soaked.

**Any promotion to `main` that touches a bolus or status-read path still clears the full NO-GO
discipline** from step (d) above regardless of urgency: oracle/test-backed, faBolus `BRANCHES.md`
§1.4-reviewed, `experimental`-first, and saline-bench-only until Phase 11. Urgency justifies
*skipping the queue*, never skipping the safety gate.

## Reminders

- The drift-detector is **issue-only** — no PR/merge write API is ever called from it. If a future
  edit adds one, that is itself a regression to flag and revert.
- Merge-after-green-CI for the adoption PR itself is **operator discipline** (a human clicks
  merge once CI is green) — there is no GitHub branch-protection auto-merge configured for this,
  and none should be assumed.
- Open PRs surfaced in the issue's "Open PRs" section are a **preview**, not a substitute for
  watching `dev` — a PR can be abandoned, rebased, or split before it ever lands.
