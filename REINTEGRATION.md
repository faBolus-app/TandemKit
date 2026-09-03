# REINTEGRATION.md — dev/loopkit (TandemKit repo)

## Feature preserved

The optional `TandemLoopKit` driver — a LoopKit `PumpManager` conformance layered above the
parity-verified core — removed from `main` by `cd7eec7` ("chore(narrow-main): remove TandemLoopKit
adapter + LoopKit CI from main"). LoopKit is iOS-only and HealthKit-bearing; the adapter was always a
SEPARATE SwiftPM package (its own `Package.swift`) that depends on the core, never the reverse, so
removing it from `main` does not touch the core build or the byte-exact oracle-parity graph.

- `integrations/TandemLoopKit/` — the whole nested SwiftPM package: `Package.swift`,
  `Package.resolved`, `README.md`, `.gitignore`, its 12 `Sources/TandemLoopKit/*.swift` files
  (`Delivery`, `DoseMapping`, `DoseProgress`, `Notice`, `PumpBLEConnection`, `StatusProjection`,
  `TandemDriverError`, `TandemPumpConnection`, `TandemPumpManager`, `TandemPumpManagerState`,
  `TandemUnfinalizedDose`, `TempBasalConversion`), and its 6 `Tests/TandemLoopKitTests/*.swift` files
  (`DeliveryTests`, `NoticeTests`, `PumpBLEConnectionSignedResponseTests`, `PureTests`, `TestSupport`).
- `.github/workflows/loopkit-driver.yml` — the non-blocking, LoopKit-only CI lane, re-triggered on this
  branch (its `push` trigger now names `dev/loopkit` instead of the dead `main` trigger, since the
  workflow file no longer exists on `main` at all).

**This branch carries the adapter's edits from AFTER its cut, not just the pre-removal snapshot:**
`043d7e3` (15-03 U1-06 / faBolus 14-02 Task 3 CX-T-11) forwards the adapter's session key into
`ResponseParser.parse` so signed responses on the LoopKit path are HMAC-verified and fail closed on a
bad/absent signature, plus its `PumpBLEConnectionSignedResponseTests` coverage, and the adjacent
`.unsupportedOnDevice` `ClientError`-map arm fix. Both landed on `main` first, inside the adapter,
before the removal — and moved here WITH the removal rather than being lost.

**Deliberately NOT preserved as a change here (stays true on `main` too):** the root `Package.swift`
never declared a LoopKit target (the adapter was always a separate package), so there is nothing to
restore there; and `ci.yml`'s "oracle graph stays LoopKit-free" guard is unaffected by this branch —
it enforces the narrow-main invariant that LoopKit must never enter the root dependency graph, on
`main` or on this branch.

## State at removal

This branch is cut from `cd7eec7`'s **parent**, so it still carries the full adapter pre-removal
(plus the `043d7e3` fix, which had already landed by the cut point). `main` has since:

1. Deleted `integrations/TandemLoopKit/` outright (22 files, 1952 lines) in `cd7eec7`. This branch's
   copy is intact.
2. Deleted `.github/workflows/loopkit-driver.yml` in the same commit. This branch's copy is intact,
   with its trigger since repointed from the dead `main` trigger to `dev/loopkit` (`20b25f9`) so the
   non-blocking driver lane actually runs on its home branch.
3. Left the root `Package.swift` and the `ci.yml` LoopKit-free oracle-graph guard byte-unchanged — this
   branch matches `main` in both respects; reintegration must not disturb either.

No signed-wire encode byte or dose-path logic was touched by the removal (per `cd7eec7`'s own
message). No JDK-21 oracle re-proof was required or performed for the removal itself.

## Reintegration path

1. Re-add `integrations/TandemLoopKit/` (the full nested SwiftPM package, Sources + Tests) from this
   branch's copy — it already includes the `043d7e3` session-key-forwarding fix, so no separate
   re-application of that fix is needed.
2. Re-add `.github/workflows/loopkit-driver.yml`, re-pointing its trigger back to `main` (or to
   whatever branch is the reintegration target) if it should fire there again.
3. Confirm the root `Package.swift` still does not declare a LoopKit target (it never should — the
   adapter stays a separate consumer package) and that `ci.yml`'s LoopKit-free oracle-graph guard
   still passes.
4. Re-run the adapter's own test suite (`DeliveryTests`, `NoticeTests`,
   `PumpBLEConnectionSignedResponseTests`, `PureTests`) before considering the driver live again —
   this branch's copy has not been kept current against the core's own evolution since the cut.
