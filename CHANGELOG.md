# Changelog

Notable changes to TandemKit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are annotated
git tags (`vX.Y.Z`).

## [Unreleased]

## [0.7.0] — 2026-11-12

The link clears the pump's qualifying events when it becomes ready, and after a signed write that held a
clear back. faBolus pins this release.

### Fixed

- The qualifying-events characteristic is cleared once when the link becomes ready, as t:connect does
  after authenticating, so notices from the handshake or an earlier connection are not left set.
- A notice that arrives while a signed write is on the wire is still cleared, as soon as the write's
  reply, failure or deadline frees the wire. Before, its clear was skipped and never sent.

## [0.6.0] — 2026-11-11

The CGM state, Check BG and EGV status, the calculator snapshot's ACK, glucose and auto-fill bytes, and
P2's support entries without the rejections an old app recorded. faBolus pins this release.

### Added

- `HomeScreenMirrorResponse.cgmAlertIcon` (`CGMAlertIcon`, with `isStartup`) and `isCheckBG` for trend
  icons 8-13; `EGVStatus` and `egvStatus` on the EGV replies.
- `BolusCalcDataSnapshotResponse.isAck` (byte 0), `glucoseReading` (bytes 1-2) and `isAutopopAllowed`
  (byte 37); `LastBolusStatusV2Response.isValid` (byte 0).

### Changed

- `BolusCalcDataSnapshotResponse.correctionFactor` is now unavailable (breaking): use `glucoseReading`.
  Bytes 1-2 hold a glucose reading in recorded snapshots, and the correction factor is `isf`, so code
  that read it as a correction factor now fails to compile instead of sizing doses from a glucose.
- `maxBolusHourlyTotal` is documented as the insulin bolused in the last hour, not a configured ceiling.
- `SupportMatrix`: P2 no longer lists InsulinStatus, HomeScreenMirror and CurrentBatteryV2 as rejected.
  Those entries came from an app that counted any error reply as a rejection; only LoadStatus stays.

## [0.5.0] — 2026-11-11

The bench tools for the t:slim bench runs, and a fix to the 6-digit pairing. faBolus pins this release.

### Added

- The `BenchWrites` package trait, off by default (tools version 6.1). With it, `SupportMatrix` allows two
  more signed writes, UserInteraction and ChangeTimeDate, for bench runs. Only the bench package enables
  it, so an app's build has neither.
- Bench: read-only diagnostics in `TandemBenchHarness` (`features`, `history`, `snapshot`, `cgm`,
  `lastbolus`, `statusreads`, `api`, `notices`, and `monitor`'s reconnect, notice and battery logs),
  transcripts of every run, the bench writes (`userinteraction`, `settime`, `clearcheck`) and the
  saline-only `bolus` command.

### Fixed

- `PairingCoordinator`: a J-PAKE key confirmation that doesn't verify is reported as
  `PairingError.keyConfirmationFailed`, which the link counts as the pump rejecting the code. Before, a
  wrong 6-digit code (or a stored secret the pump no longer has) was taken as a lost frame, and the link
  retried the same code.

## [0.4.0] — 2026-11-01

The library as the rebuilt faBolus app uses it. faBolus 0.4.0 pins this release. The last `main` before
it is tagged `v1-final`.

### Added

- `TandemLink`: the connection as a pure state machine. `LinkReducer.reduce(state, input)` returns the new
  state and the effects, and owns the phases, the reconnect ladder, the one-in-flight request queue with
  txId matching, op-77 classification and probing. `PumpConnection` (TandemBLE) runs it over
  CoreBluetooth and replaces `PumpBLEClient`.
- `SupportMatrix`: which commands a pump answers, with evidence per unit and firmware, replacing the
  static minimum-API floor. `allowedSignedWrites` lists the signed writes ever sent; the link refuses any
  other before a byte is built.
- `PumpConnection.send(_:allowing:)` grants write risk for one call, so no elevation can stick.
- Every history-log type pumpx2 decodes, field for field, and upstream's alert identifiers and firmware
  names.
- `BolusPermissionRelease` among the allowed signed writes.

### Changed

- The pumpx2 oracle is re-pinned to `456018a5`, and the parity tests run it as one long-lived JVM.
- The bench tooling moved into its own package, `Bench/`, which the library never links.
- The quality gates run on Xcode 27.2 through `scripts/check.sh`.

### Fixed

- EC-JPAKE sends full-length proof scalars and accepts short incoming rounds, as pumpx2 does. Before,
  a scalar written a byte short corrupted round 1, and roughly 1 pairing in 100 failed.
- The HMAC on an op-77 error reply on the CONTROL characteristic is verified, like every signed reply.
- `Packetize` rejects input it can't frame.

## [v1-final] — 2026-10-31

The last `main` before the rebuild. Since 0.2.0 it added legacy (16-character) pairing for older
firmware (`PairingAuth.createV1`, `LegacyPairingCoordinator`, chosen automatically from the code) and the
26-byte CONTROL form of the op-77 error reply, both checked on an API 2.5 t:slim X2.

## [0.2.0] — 2026-07-20

### Changed

- The top-level `build/` directory is git-ignored.

## [0.1.0] — 2026-07-18

### Added

- The protocol stack: `TandemMessages` (framing, opcodes, request and response models, packetization),
  `TandemAuth` (6-digit EC-JPAKE pairing and per-command HMAC signing, through vendored Mbed TLS) and
  `TandemBLE` (the CoreBluetooth central), with every outgoing message byte-exact against pumpx2's
  `cliparser` oracle. A signed 0.10 U saline bolus was delivered on a pump.

[Unreleased]: https://github.com/faBolus-app/TandemKit/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/faBolus-app/TandemKit/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/faBolus-app/TandemKit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/faBolus-app/TandemKit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/faBolus-app/TandemKit/compare/v1-final...v0.4.0
[v1-final]: https://github.com/faBolus-app/TandemKit/compare/v0.2.0...v1-final
[0.2.0]: https://github.com/faBolus-app/TandemKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/faBolus-app/TandemKit/releases/tag/v0.1.0
