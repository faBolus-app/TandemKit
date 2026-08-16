# PumpX2LoopKit

A [LoopKit](https://github.com/LoopKit/LoopKit) `PumpManager` driver for Tandem pumps, built on
**PumpX2Kit**. It is the *reverse direction* from the faBolus app: instead of faBolus commanding the
pump through its own neutral abstractions, this lets **any LoopKit/Loop-style host drive a Tandem pump
through PumpX2Kit** — the same reverse-engineered protocol, exposed as an off-the-shelf LoopKit driver.

> ## ⚠️ UNVERIFIED — NOT FOR REAL INSULIN
> This is a **reverse-engineered** Tandem pump protocol driver. It is **NOT FDA-cleared**, **NOT**
> affiliated with or endorsed by Tandem Diabetes Care or Dexcom, and **NOT for use with real insulin**.
> For research and simulation **with saline only**. The pump — never this library — is the sole
> authority on how much insulin was actually delivered.

## Why this is a separate package

This package is **intentionally not a target of the root `PumpX2Kit/Package.swift`.** LoopKit is an
iOS-15 framework that pulls in HealthKit (and, transitively via `LoopKitUI`, SwiftCharts). Keeping it in
its own package guarantees:

- `swift build` / `swift test` and the **byte-exact `cliparser` oracle-parity job** in the PumpX2Kit
  root never resolve, fetch, or compile LoopKit. The pure `PumpX2Messages` core stays zero-dependency
  and cross-platform (iOS/watchOS/macOS).
- The driver is **iOS-only** and depends only on the zero-external-dependency `LoopKit` *library
  product* (not `LoopKitUI`), so its own dependency graph stays small.

This mirrors how the ConnectIQ/Garmin bridge is walled off from CI: an optional integration that lives in
the repo but never gates the core.

## Building

Requires a full Xcode toolchain and an iOS SDK (LoopKit does not build for macOS).

```bash
cd integrations/PumpX2LoopKit
xcodebuild -scheme PumpX2LoopKit -destination 'generic/platform=iOS' build
xcodebuild -scheme PumpX2LoopKit -destination 'generic/platform=iOS' test   # or a booted simulator
```

`swift build` on a macOS host will **not** work — LoopKit declares `platforms: [.iOS("15.0")]` only.
Use `xcodebuild` with an iOS destination (the driver's tests inject a fake transport, so no CoreBluetooth
hardware or booted device is required for the unit suite; a simulator destination runs them).

## Dependency pinning

- **PumpX2Kit** is consumed by path (`../..`) — required, because PumpX2Kit's `CMbedTLSJPAKE` target
  uses `.unsafeFlags`, which SwiftPM forbids in a URL+version dependency but allows via a path dependency.
- **LoopKit** is pinned by revision (`a5beee96`, the LoopKit PR-599 BLE-heartbeat merge). `Package.resolved`
  locks LoopKit and its transitive SwiftCharts revision so the build is reproducible.

To track a newer LoopKit, bump the `revision:` in `Package.swift`, re-resolve, and re-run the mapping
tests — the LoopKit `PumpManager` surface can change between revisions.

## What maps, and what deliberately does not

| LoopKit surface | Tandem mapping |
|---|---|
| `enactBolus` | `InitiateBolusRequest` — **accepted ≠ delivered**; the delivered amount is read back from the pump's own `LastBolusStatusV2Response` / history log, never the programmed value. |
| `cancelBolus` | `CancelBolusRequest` — a cancel is only a request; the authoritative delivered amount still comes from the pump. |
| `enactTempBasal` | `SetTempRateRequest` — **lossy**: LoopKit passes absolute U/hr, Tandem is percent-of-scheduled. Converted against the live scheduled rate; the *effective* achievable rate is reported back, not the requested one. Mobi-gated on real hardware. |
| `suspendDelivery` / `resumeDelivery` | `SuspendPumpingRequest` / `ResumePumpingRequest`. |
| `syncDeliveryLimits` | `SetMaxBolusLimitRequest` / `SetMaxBasalLimitRequest` (Mobi-gated; echoes limits where unsupported). |
| `syncBasalRateSchedule` | IDP segment writes (Mobi-gated; first cut may fail/echo on t:slim). |
| history → `NewPumpEvent`/`DoseEntry` | dose-bearing history logs, deduped by a stable `(serial, sequenceNum)` sync identifier. |
| **Extended/combo bolus, pump modes (Exercise/Sleep), CGM session** | **Omitted** — no `PumpManager` surface for them. |

## Safety model (reverse-direction export)

1. **The pump is the sole authority on delivered insulin.** Every reported delivered amount comes from
   the pump's own record.
2. **Fail-closed on the indeterminate path.** A write issued but not confirmed → uncertain delivery,
   dose kept mutable, new deliveries blocked until reconciled against pump history by id on reconnect.
3. **Least-privilege writes.** The BLE write policy stays read-only and is elevated to allow delivery
   only for the signed initiate/cancel window.
4. **No silent capability widening.** Mobi-gated writes return honest failures on t:slim rather than
   pretending success.
