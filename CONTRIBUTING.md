# Contributing to TandemKit

TandemKit is a **reusable Swift library** for the Tandem t:slim X2 / Mobi Bluetooth protocol — any
project can depend on it (faBolus is one consumer). Contributions are welcome by **PR, not fork**:
the goal is one well-tested library everyone builds on. All work is for **experimental use only**
(in development, not FDA-cleared). The delivery disposition is **NO-GO for real insulin
delivery** — keep it so.

## The one hard rule: byte-exact vs the oracle
Every outgoing (request) message and every parsed response must **byte-match** the upstream
`jwoglom/pumpx2` `cliparser` oracle. "Byte-exact or fail." When you add or change a message:
1. Build the oracle once (see README → "The cliparser oracle"; needs JDK 17+).
2. Add an oracle-parity test (see `Tests/TandemMessagesTests/OracleParityTests.swift`) or a direct
   byte test (`ResponseDirectTests.swift`) for messages the oracle can't construct.
3. Run the suite: `./scripts/test.sh` (works around the CLT swift-testing rpath issue).

## Adding a message / response
- Requests live in `Sources/TandemMessages/Requests/…`, responses in `…/Responses/…`.
- Give it correct `MessageProps` (opCode, size, characteristic, `signed`, `responseOpCode`). A
  **signed** control message needs `signed: true`; a **signed response** does too (that was the
  DismissNotification bug — the response was signed and had to be marked).
- Register new responses in `ResponseParser`.
- Keep `TandemMessages` free of platform imports (it's the portable core; it builds on iOS, watchOS,
  and macOS).

## Public API / stability
- `TandemMessages`, `TandemAuth`, `TandemBLE` are the public products. Treat their public surface as
  an API other apps depend on: additive changes preferred; breaking changes get a **minor/major
  version bump** (semver) and a note in the PR.
- Tag releases (`vX.Y.Z`); consumers pin to a tag. `v0.1.0` and `v0.2.0` exist; record every release
  in [`CHANGELOG.md`](CHANGELOG.md).

## Branch model & versioning
Governance is canonical in [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md). This repo's
[`BRANCHES.md`](BRANCHES.md) is a pointer — do not fork the rules here.

faBolus consumes this package via `url:` + `revision:` in `faBolus/project.yml` (with
`FABOLUS_TANDEM_LOCAL=1` for a sibling checkout). Read the pin from that file. Do not copy SHAs
into this document.

## Safety
- The dosing/signing path (`TandemAuth`, bolus/cancel/dismiss requests) is the most safety-critical
  code and gets extra review. Never loosen the write-policy interlock or signing.

## Before a PR
- `./scripts/test.sh` green (all suites, including oracle parity).
- Confirm the three library products still build for iOS **and** watchOS
  (`xcodebuild -scheme TandemAuth -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build`,
  likewise `TandemBLE`, `TandemMessages`).
- Note anything only compiled vs. tested on hardware.
