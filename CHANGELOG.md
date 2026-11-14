# Changelog

Notable changes to TandemKit. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are annotated
git tags (`vX.Y.Z`).

## [Unreleased]

## [0.12.0] — 2026-11-13

CGM status B and UserInteraction for a t:slim, the grace-period alert names, and a first pairing the pump
drops. faBolus pins this release.

### Added

- `LinkFailure.pairingDropped` (breaking for exhaustive switches): a first JPAKE pairing whose link drops
  during authentication twice in a row ends there instead of climbing the reconnect ladder, as Mobi takes
  a drop there for a wrong code. `LinkConfig.pairingDropsToFail` (2) and `ReconnectLadder.pairingDrops`.
- CGM alert names 28 (check sensor), 29 (ESA), 31 (grace period started) and 32 (grace period ending).

### Changed

- `CgmStatusV2Request` (CGM status B) is no longer Mobi-only, as t:connect asks a t:slim for it.
- `UserInteractionRequest` is on the signed-write allowlist (now eight), as t:connect sends it at API 3.0
  or later; it leaves the bench-only list.

### Removed

- CGM alert 39's name, which t:connect doesn't give it.

## [0.11.0] — 2026-11-13

Names and decodes for faBolus's cartridge marks and stopped-bolus names, and for its calculator taking the
snapshot's own reading; LastBolusStatus C can now go to a t:slim. faBolus pins this release.

### Added

- `InsulinStatusResponse.fillStatus` (byte 2: normal, plus, low, empty).
- `LastBolusStatusV2Response.endReason` (byte 13) and the shared `BolusEndReason`;
  `LastBolusStatusV3Response.standardBolusStatus` (no record, stopping, finished) and
  `standardBolusEndReason`.
- `BolusCompletedHistoryLog.completionStatus`, named.
- `BolusCalcDataSnapshotResponse.readingTimestamp`, `readingSecondsSincePumpReset` and `readingStatusId`
  (bytes 26, 30 and 34): when its reading was taken and the reading's status. Unverified on a t:slim;
  pumpX2's two recorded snapshots move both clocks by exactly the 1200 s between them.
- `PumpFeaturesV2Response.blePumpControlSupported`, read from the main feature set only.
- `ApiVersion.v3_1`.

### Changed

- `InsulinStatusResponse.isEstimate` is now `fillStatusId` (breaking).
- `LastBolusStatusV3Request` is no longer Mobi-only: it is floored at API 3.1, as t:connect asks a t:slim
  for it. The bench's untagged copy of it is removed.

## [0.10.0] — 2026-11-13

The home screen mirror's status and bolus icons are decoded, so faBolus can show a bolus or an automatic
bolus running, the transmitter out of range and a calibration due. faBolus pins this release.

### Added

- `HomeScreenMirrorResponse.statusIcon0Id` and `statusIcon1Id` (bytes 2 and 3), and `statusIcon0`,
  `statusIcon1` and `bolusStatusIcon` naming them and byte 4 with pumpX2's ids (the transmitter or the
  transmitter out of range; a calibration's blood drop; a bolus, an automatic bolus, two locks), or `nil`
  for an id outside each set. The offsets are pumpX2's, and which icon a t:slim shows when is unverified.

## [0.9.0] — 2026-11-13

The home screen mirror's basal icon is named, so faBolus can show a suspended pump and a pump-set temp
rate. faBolus pins this release.

### Added

- `HomeScreenMirrorResponse.basalStatusIcon`: byte 5 named with pumpX2's `BasalStatusIcon` ids (basal,
  zero basal, temp rate, zero temp rate, suspend, Basal-IQ suspend, increase, attenuated, hide), or `nil`
  for an id outside that set. Which icon a t:slim shows in which delivery state is unverified.
- Bench: `bolus cancel --overlap` writes the cancel while a CurrentBolusStatus read still waits for its
  reply, as Mobi writes a cancel, to check whether a t:slim takes two requests outstanding. The bench
  transport holds the read's write back until just before the cancel's; the link is unchanged.

### Fixed

- `HistoryLogRequest`'s doc: `startLog` is the newest entry wanted, and the pump streams down from it,
  newest first, as t:connect and Mobi send it. It said the entries start there.

## [0.8.0] — 2026-11-12

Reconnecting never gives up and waits t:connect's cooldown, and the pairing scan follows Mobi's rules.
faBolus pins this release.

### Changed

- Reconnecting never stops. After every drop or failed connect the link waits a cooldown, as t:connect does
  after a connection error, a drop after the link held included: 1 s, 3 s after a supervision timeout and
  10 s after a failed connect, doubled for each failure in a row since the link last held, up to 30 s.
  The wait is the same in the background. The fixed 5-10-20-30 s foreground ladder, its jitter, the
  8-flap stop and `LinkPhase.exhausted` are gone (`LinkConfiguration.backoff`, `backoffJitter`, `maxFlaps`).
- `PumpConnection` takes a `LinkBackgroundTime`, which keeps a cooldown timed in the background; when it
  ends first, or without one, the pending connect goes out at once.
- The pairing scan lists only pumps stronger than -75 dBm and reports repeated advertisements, so a pump
  brought closer appears. It fails as `pumpNotFound` after 120 s from its start, not 30 s, unless the
  strongest pump found advertises that it is accepting connections first, as Mobi does; the scan itself
  runs until a pump is picked. `TransportCommand.scan` says whether to report repeats; a listed pump is
  reported again only when its signal moves by 5 dB.
- A drop after the link held now counts toward the cooldown's doubling, and so toward
  `connectionUnstable`: a held drop and two quick ones after it report the link unstable.

### Added

- `PumpRegistrationState`, read from Tandem's manufacturer data, and `manufacturerData` on
  `LinkInput.discovered`.
- `LinkInput.backgroundTimeEnding`.

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

[Unreleased]: https://github.com/faBolus-app/TandemKit/compare/v0.12.0...HEAD
[0.12.0]: https://github.com/faBolus-app/TandemKit/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/faBolus-app/TandemKit/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/faBolus-app/TandemKit/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/faBolus-app/TandemKit/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/faBolus-app/TandemKit/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/faBolus-app/TandemKit/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/faBolus-app/TandemKit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/faBolus-app/TandemKit/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/faBolus-app/TandemKit/compare/v1-final...v0.4.0
[v1-final]: https://github.com/faBolus-app/TandemKit/compare/v0.2.0...v1-final
[0.2.0]: https://github.com/faBolus-app/TandemKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/faBolus-app/TandemKit/releases/tag/v0.1.0
