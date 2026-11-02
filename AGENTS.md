# AGENTS.md — TandemKit

Working notes for agents and humans. Swift port of the Tandem t:slim X2 / Mobi Bluetooth protocol
(from jwoglom's pumpX2), consumed by faBolus. **A wrong byte can misdose insulin.** Companion map:
[`llms.txt`](llms.txt). Branch policy is canonical in [`../faBolus/BRANCHES.md`](../faBolus/BRANCHES.md);
this repo's [`BRANCHES.md`](BRANCHES.md) is a pointer.

## The golden rule

Every request's bytes and every response's parse are verified **byte-exact** against the vendored Java
oracle (`vendor/pumpx2-oracle/`). **Never change message bytes without adding/keeping a matching
oracle-parity test.**

## Commands

- **Every gate:** `./scripts/check.sh` (CI runs the same script)
- **Full suite (Xcode):** `swift test`
- **CLT-only wrapper:** `./scripts/test.sh`
- **Bench package:** `swift test --package-path Bench`
- **Single test:** `swift test --filter <Name>`
- Oracle parity needs a built `cliparser.jar` and **JDK 21**. See README.

## Layout (SPM products)

- `Sources/TandemMessages/` — messages + framing. `MessageProps` per type (`opCode`, `size`, `signed`,
  `characteristic`, `modifiesInsulinDelivery`, `responseOpCode`). `ResponseParser` dispatches on
  **(characteristic, opCode)** — opcodes are not globally unique.
- `Sources/TandemMessages/Core/SupportMatrix.swift` — which commands a pump answers (supported,
  unsupported, untested), with evidence per pump unit and firmware, and the seven signed writes that
  are ever sent (`allowedSignedWrites`; the link refuses every other signed write).
- `Sources/TandemAuth/` — `PairingCoordinator`, `JpakeAuth` / `EcJpakeContext` (EC-JPAKE via vendored
  mbedTLS), `Crypto`.
- `Sources/TandemLink/` — the connection state machine: `LinkReducer.reduce(state, input)` returns the
  new `LinkState` and `[LinkEffect]`, with no CoreBluetooth import. It owns every piece of link state:
  phases, the reconnect ladder, the request queue (one in flight, txId matching), op-77
  classification, probing, the signed-reply freshness check and the telemetry.
- `Sources/TandemBLE/` — `PumpConnection` runs the reducer and performs its effects through a
  `LinkTransport` (`CoreBluetoothTransport`). `send(_:allowing:)` grants risk per call, so no
  elevation can stick; a message above it is refused before a byte is built.
- `Tests/TandemMessagesTests/` — `OracleParityTests`, `ResponseParityTests`, `ResponseDirectTests`.
- `Tests/TandemLinkTests/` — every transition, the replay of P1's reconnect-loop logs (`Fixtures/`) and
  the request rules. `Tests/TandemBLETests/` — `PumpConnection` over a scripted CoreBluetooth stand-in.
- `Bench/` — a separate package for bench runs against a real pump; the library never links it.

## How to add a message

1. Add request/response under `Sources/TandemMessages/` with correct `MessageProps`.
2. Register the response type in `ResponseParser`.
3. Add a byte-exact test from an oracle vector (or a direct byte test if the oracle cannot construct it).
4. Signed / insulin-affecting messages must set `modifiesInsulinDelivery: true`.

## Conventions

- Match the oracle exactly; each type's doc-comment cites its Java origin. If a field is unverified
  on-device, say so in the doc-comment — don't guess.
- Swift 6: keep CoreBluetooth delegate isolation correct.
- Comments explain why (safety, oracle, hardware). Do not add phase/ticket IDs or pin SHAs here.

## Quality gates

- `./scripts/check.sh` runs every gate; CI runs the same script, one gate per step, on Xcode 27.2.
  Each gate fails the build: compiler warnings, `swift test`, the `Bench/` package,
  `xcrun swift-format lint --strict`, SwiftLint, ShellCheck, actionlint and markdownlint. Nothing is grandfathered. A suppression is
  written inline, names the rule and gives a reason.
- `./scripts/format.sh` formats in place with the toolchain's swift-format. `.swift-format` turns off
  every rule except `DoNotUseSemicolons`, so it reflows layout but never rewrites code. Leave the rules
  off: `GroupNumericLiterals` would punch underscores through the capability bitmasks in
  `Responses.swift` (`has(8388608)` -> `has(8_388_608)`, hiding that each one is a single bit).
- `.swiftlint.yml` is a short list of correctness rules. Never rename a wire field to satisfy a linter.
- Report only: Semgrep (faBolus's `.semgrep/deslop.yml`), Periphery, and CodeQL (`codeql.yml`).

## Reviewing

<!-- Only facts a reviewer can't get from the diff. How to review is the review tool's job; don't restate it here. -->

Facts a reviewer needs that the diff doesn't show:

- The golden rule above names what matters most here.
- Out of scope: anything a `check.sh` gate already fails on.
- `vendor/` holds two upstream submodules, pumpx2 and mbedTLS. A diff can only move their pins, and
  moving pumpx2's changes what every parity test compares against.
- controlX2 has no license: it is read for structure, and nothing is copied from it.
- On API 2.5 pumps an unsupported command gets an op-77 error and the pump drops the link, so sending a
  new read, or retrying one, can cost a connection.
- Most past bugs were in the phone↔pump link: state kept outside a state machine, retry and reconnect
  loops, stuck states after a drop, suspension and relaunch, and replies lost, duplicated or reordered.

## Consumed by

`../faBolus` via SwiftPM. App-level UI and `AccessPolicy` live there; the wire format lives here.
