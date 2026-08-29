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
- **Run the formatter before you commit:** `./scripts/format.sh` (`--lint` to check only). It prints
  the formatter version it used — swift-format's output is version-dependent, so CI pins Homebrew's
  build (`brew install swift-format`, 603.0.0, byte-identical to Xcode 26.6's 6.3.0). Override with
  `SWIFT_FORMAT=/path/to/swift-format` if your Xcode is older. The
  committed `.swift-format` disables every swift-format *rule* and keeps only the pretty-printer, so
  it reflows whitespace but never rewrites code — the disabled rules include ones that can widen
  access, delete a public memberwise init, or insert underscores into numeric literals INCLUDING
  OPCODES. CI reports (does not gate) on an unformatted tree.
- `swiftlint lint --quiet Sources Tests` is advisory. Read `.swiftlint.yml` before "fixing" a hit:
  the API-version cases keep their underscores because they are public API (`minApi: .v2_5`),
  `Bytes.readString` keeps its lossy decode on purpose, and the metric rules describe wire-message
  constructors. Never rename a wire field or public API to satisfy a linter.

## Consumed by
`../faBolus` via SwiftPM. App-level UI and `AccessPolicy` live there; the wire format lives here.
