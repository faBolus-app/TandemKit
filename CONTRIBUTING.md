# Contributing to TandemKit

TandemKit is a **reusable Swift library** for the Tandem t:slim X2 / Mobi Bluetooth protocol — any
project can depend on it (faBolus is one consumer). Contributions are welcome by **PR, not fork**:
the goal is one well-tested library everyone builds on. All work is for **experimental use only**
(in development, not FDA-cleared).

## The one hard rule: byte-exact vs the oracle
Every outgoing (request) message and every parsed response must **byte-match** the upstream
`jwoglom/pumpx2` `cliparser` oracle. "Byte-exact or fail." When you add or change a message:
1. Build the oracle once (see README → "The cliparser oracle"; needs JDK 17+).
2. Add an oracle-parity test (see `Tests/PumpX2MessagesTests/OracleParityTests.swift`) or a direct
   byte test (`ResponseDirectTests.swift`) for messages the oracle can't construct.
3. Run the suite: `./scripts/test.sh` (works around the CLT swift-testing rpath issue).

## Adding a message / response
- Requests live in `Sources/PumpX2Messages/Requests/…`, responses in `…/Responses/…`.
- Give it correct `MessageProps` (opCode, size, characteristic, `signed`, `responseOpCode`). A
  **signed** control message needs `signed: true`; a **signed response** does too (that was the
  DismissNotification bug — the response was signed and had to be marked).
- Register new responses in `ResponseParser`.
- Keep `PumpX2Messages` free of platform imports (it's the portable core; it builds on iOS, watchOS,
  and macOS).

## Public API / stability
- `PumpX2Messages`, `PumpX2Auth`, `PumpX2BLE` are the public products. Treat their public surface as
  an API other apps depend on: additive changes preferred; breaking changes get a **minor/major
  version bump** (semver) and a note in the PR.
- Tag releases (`vX.Y.Z`); consumers pin to a tag. `v0.1.0` and `v0.2.0` exist; record every release
  in [`CHANGELOG.md`](CHANGELOG.md).

## Branch model & versioning (§1.3/§1.4)
Governance is **canonical in faBolus, not forked here.** The three-branch model
(`deprecated`/`main`/`experimental`), the §1.2 experimental gate, and the §1.4 promotion criteria are
defined once in [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md) and apply to all three code repos in
lockstep (§1.3). See the local [`BRANCHES.md`](BRANCHES.md) stub. Do not restate or diverge those rules.

**Version-pinning contract (§1.3).** Consumers of a faBolus backend should pin an explicit released
version: an annotated `vX.Y.Z` tag consumed by `url:` + version, with a committed `Package.resolved`
and a documented local-path override for development.

**Status: version-pinning is DECLARED UNMET here (owner decision, 2026-08-07).** faBolus consumes this
package by local path (`faBolus/project.yml` `path: ../TandemKit`), not a URL+version pin, and that
remains the consumption model. SwiftPM refuses a URL+version dependency on a package that uses
`.unsafeFlags`, and this package has **two** such sites: `Package.swift:37` (`-DMBEDTLS_CONFIG_FILE` on
`CMbedTLSJPAKE` — the actual blocker, since it is in the closure of the `PumpX2Auth`/`PumpX2BLE`
products faBolus consumes) and `Package.swift:69` (a harness linker flag on the `PumpX2BenchHarness`
executable, which faBolus does not consume). Removing them means vendoring the Mbed TLS config/headers
in-tree and rehoming the 13 committed `CMbedTLSJPAKE/mbedtls_lib/*.c` symlinks — a build-graph/vendoring
refactor guarded only by the oracle byte-parity + hardware-pairing tests. **That refactor is deferred
and is NOT attempted in this change.** This is declared unmet on purpose (not quietly satisfied by the
local path). Tracked as WIP-REGISTER item 8.

## Safety
- The dosing/signing path (`PumpX2Auth`, bolus/cancel/dismiss requests) is the most safety-critical
  code and gets extra review. Never loosen the write-policy interlock or signing.

## Before a PR
- `./scripts/test.sh` green (all suites, including oracle parity).
- Confirm the three library products still build for iOS **and** watchOS
  (`xcodebuild -scheme PumpX2Auth -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build`,
  likewise `PumpX2BLE`, `PumpX2Messages`).
- Note anything only compiled vs. tested on hardware.
