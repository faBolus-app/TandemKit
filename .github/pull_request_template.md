<!--
TandemKit is the Tandem pump protocol library (messages / auth / BLE). A wrong byte can misdose
insulin. Fill in what applies; delete what doesn't. See CONTRIBUTING.md, AGENTS.md, and BRANCHES.md.
-->

## What & why

<!-- One or two sentences. What changes, and the problem it solves. -->

## The golden rule: byte-exact vs the oracle

- [ ] No message bytes / response parse changed — **or** they did, with a matching **oracle-parity
      test** added/kept green
- [ ] `swift test` green including the byte-exact oracle suites (needs JDK 21 for the cliparser oracle)
- [ ] Did **not** set `PUMPX2_ALLOW_ORACLE_SKIP` (it silently drops all byte-parity coverage)

## Safety

- [ ] Does **not** loosen the per-call risk gate (`send(_:allowing:)`) or the pairing/signing path
- [ ] Signed / insulin-affecting messages set `modifiesInsulinDelivery: true`
- [ ] Any field whose meaning is unverified on-device is marked as such in the doc-comment (no guessing)

## Versioning / consumers

- [ ] Public API change → semver note in the PR **and** a `CHANGELOG.md` entry
- [ ] No `.unsafeFlags` in the library's own targets (`Package.swift`; `Bench/` is a separate package):
      faBolus pins a release by version, and SwiftPM refuses unsafe flags in a version-pinned dependency

## Hardware

- [ ] Compile-only vs hardware-tested noted. The BLE path is validated on hardware through the
      `TandemBenchHarness` executable, **not** `swift test` (see PINNED.md).
