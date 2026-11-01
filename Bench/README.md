# TandemKit bench tooling

A separate SwiftPM package so none of this can be linked into an app. It depends on the parent
package's library products and adds:

| Target | What it is |
| --- | --- |
| `TandemBench` | Bench session planning, the command-coverage matrix and the bench-bolus planner. |
| `TandemBenchHarness` | The bench CLI against a real pump, on the app's `PumpConnection`: `scan`, `monitor`, `dismiss`. |
| `TandemBenchTests` | Unit tests for the planner and matrix (no hardware). |

## Running it

From the repository root:

```bash
swift build --package-path Bench
```

```bash
swift test --package-path Bench
```

Hardware runs go through the executable, not `swift test`: macOS aborts a process that touches
CoreBluetooth without a Bluetooth usage string, and only the executable embeds one (see
`Package.swift`):

```bash
swift run --package-path Bench TandemBenchHarness monitor
```

- `scan` lists pumps in pairing range.
- `monitor` pairs (`PUMP_PAIRING_CODE`, optionally `PUMP_PERIPHERAL_ID`), holds the link, reads status
  every minute, and reports every drop with its reason and the telemetry every 10 minutes. It's the
  24-hour hold check.
- `dismiss <reminder|alert|alarm|cgm> <id>` dismisses one pump notification once the link has held,
  and reports whether the pump accepted it or doesn't support it.

Every request goes through the link's own gates: the support matrix (kept between runs in
`~/.tandemkit-bench/support-matrix.json`, or `PUMP_SUPPORT_MATRIX`), careful probing, and the six
allowed signed writes. The only signed write the harness sends is DismissNotification.

The committed `bench-coverage/` matrix is the T-1 run on the old t:slim X2 (API 2.5, legacy pairing,
no cartridge, no CGM), which `SupportMatrix` cites as evidence. The sweep runner that produced it was
removed with the old client; `docs/BENCH-COVERAGE.md` and `docs/BENCH-SESSION-PLAN.md` record how.
