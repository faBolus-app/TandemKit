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

**(b) Prioritize** in this order (do not force-adopt lower-priority churn):

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

**(d) Route dose-path items through the full review.** An adopted change lands on `main` by pull
request, with its oracle-parity (or history-record) test and a `/code-review`. Anything that sets
`modifiesInsulinDelivery: true`, or touches a bolus or status-read path, also gets an adversarial review.
Pump behavior a change relies on that isn't confirmed on hardware goes in faBolus
`docs/UNVERIFIED-GUESSES.md`. This applies whether the source was upstream `main` or upstream `dev`.

**(e) Update the baselines only AFTER the adoption PR merges.** Bump `PINNED.md`'s pumpx2 submodule
pin (`vendor/pumpx2-oracle`) and/or the `## Upstream controlX2 watch` tracked dev/main SHA at merge
time, not before — the baseline is what the detector measures against on the *next* cycle, so
moving it early would silently swallow anything landed in between.

## Where adoptions land

TandemKit has one branch, `main`. Every adopted upstream change goes there by pull request, after the
steps above; there is no separate landing branch. Urgency can move a change up the queue, never past
step (d).

## Reminders

- The drift-detector is **issue-only** — no PR/merge write API is ever called from it. If a future
  edit adds one, that is itself a regression to flag and revert.
- Merge-after-green-CI for the adoption PR itself is **operator discipline** (a human clicks
  merge once CI is green) — there is no GitHub branch-protection auto-merge configured for this,
  and none should be assumed.
- Open PRs surfaced in the issue's "Open PRs" section are a **preview**, not a substitute for
  watching `dev` — a PR can be abandoned, rebased, or split before it ever lands.
