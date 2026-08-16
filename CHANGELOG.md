# Changelog

All notable changes to TandemKit are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Releases are annotated git tags (`vX.Y.Z`). Two non-version pointers track goodness over time and are
described in [`BRANCHES.md`](BRANCHES.md): `safe-baseline/*` (the moving last-known-good rollback
target) and `deprecated/*` (an immovable pre-round-3 snapshot — **not** a supported fallback).

> **Not FDA-cleared. Disposition: NO-GO for real insulin delivery.** Every entry below preserves that
> disposition; none of it enables or changes delivery/dosing behavior.

## [Unreleased]

### Added
- Legacy **V1 (16-character) pump pairing** at the library layer: `PairingAuth.createV1`,
  `LegacyPairingCoordinator`, op-17/op-19 response parsers, and `PairingAuth.detectType` /
  `LiveSession.beginPairing()` auto-selecting the legacy CentralChallenge→PumpChallenge handshake vs
  the modern 6-digit EC-JPAKE scheme from the pairing code (#8).
- **Legacy-V1 hardware harness** and bench-validated results (#9): `TandemBenchHarness` V1 wiring,
  `PumpFirmwareProfile` capture (API version + pump SW + auth scheme), and the 26-byte CONTROL-variant
  `ErrorResponse` (op-77). Validated on a spare t:slim X2 (API 2.5): legacy V1 pairing, a read sweep,
  txId echo, and signed `BolusPermission` acceptance — logged in [`PINNED.md`](PINNED.md).

### Notes
- `safe-baseline/2026-08-04` advanced to the P12 cold-launch retrieve-before-scan commit (#6).
- Consuming TandemKit as a URL+version SwiftPM dependency remains **UNMET** by owner decision — see
  the §1.3 versioning contract in [`CONTRIBUTING.md`](CONTRIBUTING.md) / [`AGENTS.md`](AGENTS.md) and
  WIP item 8. faBolus continues to consume this package by local path.

## [0.2.0] — 2026-07-20

### Changed
- Build hygiene: gitignore the top-level `build/` directory (xcodebuild dependency output).
  (Lightweight tag `v0.2.0`.)

## [0.1.0] — 2026-07-18

### Added
- **Milestone 1** — the end-to-end pump protocol stack: `TandemMessages` (framing, opcodes,
  request/response models, packetization), `TandemAuth` (6-digit EC-JPAKE pairing + per-command HMAC
  signing, via vendored Mbed TLS), and `TandemBLE` (Core Bluetooth central). A signed **0.10 u saline
  bolus was delivered on real hardware**, with every outgoing message byte-exact against the
  jwoglom/pumpx2 `cliparser` oracle. (Annotated tag `v0.1.0`.)

[Unreleased]: https://github.com/faBolus-app/TandemKit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/faBolus-app/TandemKit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/faBolus-app/TandemKit/releases/tag/v0.1.0
