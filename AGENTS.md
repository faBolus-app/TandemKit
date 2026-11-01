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

- **Full suite (Xcode):** `swift test`
- **CLT-only wrapper:** `./scripts/test.sh`
- **Single test:** `swift test --filter <Name>`
- Oracle parity needs a built `cliparser.jar` (Gradle, **JDK 17+**; CI uses JDK 21). See README.

## Layout (SPM products)

- `Sources/TandemMessages/` — messages + framing. `MessageProps` per type (`opCode`, `size`, `signed`,
  `characteristic`, `modifiesInsulinDelivery`, `responseOpCode`). `ResponseParser` dispatches on
  **(characteristic, opCode)** — opcodes are not globally unique.
- `Sources/TandemAuth/` — `PairingCoordinator`, `JpakeAuth` / `EcJpakeContext` (EC-JPAKE via vendored
  mbedTLS), `Crypto`.
- `Sources/TandemBLE/` — `PumpBLEClient`. `WritePolicy` is risk-tiered: `.readOnly` (default),
  `.allowBenignControl`, `.allowNonDelivery`, `.allowDestructive`, `.allowDelivery`. `send()` enforces
  `message.operationRisk ≤ policy.maxRisk`. Prefer `withWritePolicy` so elevation cannot stick.
- `Tests/TandemMessagesTests/` — `OracleParityTests`, `ResponseParityTests`, `ResponseDirectTests`.

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
  faBolus's TandemKit pin lives in `faBolus/project.yml`.

## Quality gates

- `./scripts/check.sh` runs every gate; CI runs the same script, one gate per step, on Xcode 27.2.
  Each gate fails the build: compiler warnings, `swift test`, `xcrun swift-format lint --strict`,
  SwiftLint, ShellCheck, actionlint and markdownlint. Nothing is grandfathered. A suppression is
  written inline, names the rule and gives a reason.
- `./scripts/format.sh` formats in place with the toolchain's swift-format. `.swift-format` turns off
  every rule except `DoNotUseSemicolons`, so it reflows layout but never rewrites code. Leave the rules
  off: `GroupNumericLiterals` would punch underscores through the capability bitmasks in
  `Responses.swift` (`has(8388608)` -> `has(8_388_608)`, hiding that each one is a single bit).
- `.swiftlint.yml` is a short list of correctness rules. Never rename a wire field to satisfy a linter.
- Report only: Semgrep (faBolus's `.semgrep/deslop.yml`), Periphery, and CodeQL (`codeql.yml`).

## Consumed by

`../faBolus` via SwiftPM. App-level UI and `AccessPolicy` live there; the wire format lives here.
