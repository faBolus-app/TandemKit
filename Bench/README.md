# TandemKit bench tooling

A separate SwiftPM package so none of this can be linked into an app. It depends on the parent
package's library products and adds:

| Target | What it is |
| --- | --- |
| `TandemBench` | Bench session planning, the command-coverage matrix, the bench-bolus planner and the decoders the harness prints with. |
| `TandemBenchHarness` | The bench CLI against a real pump, on the app's `PumpConnection`: the read-only diagnostics, `monitor` and `dismiss`. |
| `TandemBenchTests` | Unit tests for the planner, the matrix and the harness's decoders (no hardware). |

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

`swift run --package-path Bench TandemBenchHarness help` lists every command. Each one prints the
raw reply bytes with a decoded line and ends with `RESULT` lines, and each run writes a transcript to
`~/.tandemkit-bench/transcripts/` (or `PUMP_TRANSCRIPT_DIR`): every printed line plus every packet in
both directions, with the pairing exchange redacted. `PUMP_RECORD_PAIRING=1` keeps the pairing
exchange, for a pairing test built from a real one; a transcript made with it stays private, because
it can help someone work out the pairing code. A line typed during a run is stamped into it as a
`NOTE`, to mark what was done at the pump.

| Command | What it reads or does |
| --- | --- |
| `scan` | Lists pumps in pairing range. |
| `api` | The API version and the pump's software versions. |
| `features [all\|legacy\|N..]` | The PumpFeaturesV2 sets by index (main, control and Dexcom by default; `all` adds the rest), every set bit by its pumpX2 name, and main-set bits 28 (`BLE_PUMP_CONTROL_SUPPORTED`) and 10 (`CONTROL_IQ_SUPPORTED`) called out. Below API 2.5, the legacy PumpFeaturesV1. |
| `history [status\|anchor\|oldest\|cap..]` | The log's oldest and newest sequence numbers, which end of a page `startLog` names, and whether a page of 251-255 records is cut at 250. |
| `snapshot [samples] [seconds]` | The bolus-calculator snapshot byte by byte, and where the CGM reading and its timestamp sit in the bytes pumpX2 doesn't decode. |
| `cgm [minutes]` | The home-screen icons byte by byte (CGM alert, basal, bolus, Control-IQ state), the EGV status and the CGM session. |
| `statusreads` | InsulinStatus, HomeScreenMirror and CurrentBatteryV2, once each. |
| `lastbolus` | LastBolusStatus forms C (0xBA), B and A. Form C goes through a bench copy without the library's Mobi tag, so the link probes it on a t:slim. |
| `monitor [--poll S\|off] [--battery S] [--minutes M]` | Holds the link and reads status every S seconds, or with `off` only the battery. Logs every drop, every reconnect's timing, every pump notice (and the pump clock after a time-change notice), the battery trend and the request rate. The 24-hour hold check, the range edge and the battery cost of a held link. |
| `notices [minutes]` | `monitor --poll off`: the pump's notices with nothing else on the link, for notice bit 19. |
| `dismiss [--chunk 18] <kind> <id>` | Dismisses one pump notification once the link has held. `--chunk` re-cuts the control write's packets at that size in the bench transport, for the chunk-size check. |

`--retest` on any command forgets this pump's recorded result for each command before sending it, so
the link probes it again.

Every request goes through the link's own gates: the support matrix (kept between runs in
`~/.tandemkit-bench/support-matrix.json`, or `PUMP_SUPPORT_MATRIX`), careful probing, and the seven
allowed signed writes. The only signed write the harness sends is DismissNotification.

The committed `bench-coverage/` matrix is the T-1 run on the old t:slim X2 (API 2.5, legacy pairing,
no cartridge, no CGM), which `SupportMatrix` cites as evidence. The sweep runner that produced it was
removed with the old client; `docs/BENCH-COVERAGE.md` records how.
