# TandemKit bench tooling

A separate SwiftPM package so none of this can be linked into an app. It depends on the parent
package's library products and adds:

| Target | What it is |
| --- | --- |
| `TandemBench` | Bench session planning, the command-coverage matrix and the bench-bolus planner. |
| `TandemBenchHarness` | The bench CLI against a real pump (`scan`, `monitor`, `probe`, `coverage`, and more). |
| `TandemBenchTests` | Unit tests for the planner and matrix (no hardware). |
| `TandemHardwareTests` | Hardware cases, including the read-only txId-match probe. Gated on a pump being present; with none they skip. |

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

`monitor` is read-only. Anything that writes keeps both delivery walls armed: `PumpBLEClient`'s write
policy defaults to `.readOnly`, and `Packetize` refuses a delivery message unless delivery is enabled
for that one call. TandemKit sends only six signed writes (`SupportMatrix.allowedSignedWrites`); the
client refuses any other before a byte is built, so the planner marks the rest as never sent.

The coverage runner reads and writes `Bench/bench-coverage/COVERAGE-MATRIX.{json,md}`, wherever it is
started from (`PUMPX2_BENCH_COVERAGE_DIR` overrides it). The committed
matrix is the T-1 run on the old t:slim X2 (API 2.5, legacy pairing, no cartridge, no CGM), which
`SupportMatrix` cites as evidence. See `docs/BENCH-COVERAGE.md` and `docs/BENCH-SESSION-PLAN.md`.
