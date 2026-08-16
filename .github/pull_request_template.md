<!--
TandemKit is the Tandem pump protocol library (messages / auth / BLE). A wrong byte can misdose
insulin. Delivery disposition is NO-GO for real insulin; keep it that way unless changing it is this
PR's explicit subject. Fill in what applies; delete what doesn't. See CONTRIBUTING.md, AGENTS.md, and
BRANCHES.md.
-->

## What & why

<!-- One or two sentences. What changes, and the problem it solves. -->

## Branch target

- [ ] `main` — meets every §1.4 promotion criterion (see faBolus/BRANCHES.md)
- [ ] `experimental` — not yet promotable (§1.2)

## The golden rule: byte-exact vs the oracle

- [ ] No message bytes / response parse changed — **or** they did, with a matching **oracle-parity
      test** added/kept green
- [ ] `swift test` green including the byte-exact oracle suites (needs JDK 21 for the cliparser oracle)
- [ ] Did **not** set `PUMPX2_ALLOW_ORACLE_SKIP` (it silently drops all byte-parity coverage)

## Safety

- [ ] Does **not** loosen the `WritePolicy` interlock or the pairing/signing path
- [ ] Signed / insulin-affecting messages set `modifiesInsulinDelivery: true`
- [ ] Delivery disposition unchanged (**NO-GO for real insulin delivery**) — or this PR's explicit
      subject is changing it, and says so
- [ ] Any field whose meaning is unverified on-device is marked as such in the doc-comment (no guessing)

## Versioning / consumers (§1.3)

- [ ] Public API change → semver note in the PR **and** a `CHANGELOG.md` entry
- [ ] Aware the pin contract is **MET via a `url:`+`revision:` pin** (not an annotated tag+version,
      due to `.unsafeFlags`; WIP item 8 tracks the deferred refactor that would allow tag+version) —
      did not silently change how consumers depend on this package

## Hardware

- [ ] Compile-only vs hardware-tested noted. The BLE path is validated on hardware through the
      `TandemBenchHarness` executable, **not** `swift test` (see PINNED.md).
