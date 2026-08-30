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

## Style + advisory tooling
- **Run the formatter before you commit:** `./scripts/format.sh` (`--lint` to check only). Use the
  script, not bare `swift-format`: it filters the vendored trees, which must never be restyled, and
  prints the version it used. swift-format's output is version-dependent, so CI pins Homebrew's build
  (`brew install swift-format`); override with `SWIFT_FORMAT=/path/to/swift-format`. The committed
  `.swift-format` turns off every rule except `DoNotUseSemicolons`, so it reflows whitespace but does
  not rewrite code. Leave the rules off: `GroupNumericLiterals` would punch underscores through the
  capability bitmasks in `Responses.swift` (`has(8388608)` -> `has(8_388_608)`, hiding that each one
  is a single bit), and `NoAccessLevelOnExtensionDeclaration` would explode every `public extension`
  into per-member modifiers.
- `swiftlint lint --quiet` is advisory. Read `.swiftlint.yml` first: the metric rules fire on
  wire-message constructors, and `case foo = "foo"` records a wire contract. Never rename a wire
  field to satisfy a linter.
- `semgrep --config <faBolus>/.semgrep/deslop.yml --metrics=off .` flags AI-process residue. The
  ruleset lives in the faBolus repo; CI fetches it by raw URL. Advisory — a genuine oracle citation
  (`HistoryLogResponse.java:35`) can look like a drifted line reference, and is a KEEP.
- CI: `style` (format + SwiftLint, advisory), `semgrep` (advisory), the build/test job, and
  `codeql.yml` on push. Only the build/test job gates.

## Consumed by
`../faBolus` via SwiftPM. App-level UI and `AccessPolicy` live there; the wire format lives here.
