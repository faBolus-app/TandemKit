# Contributing to TandemKit

TandemKit is a reusable Swift library for the Tandem t:slim X2 Bluetooth protocol; faBolus is one user of
it. Contributions are welcome by pull request. Until the rebuild merges, target `rebuild`; after that,
`main` (see [BRANCHES.md](BRANCHES.md)).

## The rule: byte-exact against the oracle

Every outgoing message and every parsed response must byte-match pumpx2's `cliparser` oracle. When you add
or change a message:

1. Build the oracle once with JDK 21 (README, "The cliparser oracle").
2. Add an oracle-parity test (`Tests/TandemMessagesTests/OracleParityTests.swift`), or a direct byte test
   (`ResponseDirectTests.swift`) for a message the oracle can't construct.
3. Run the gates.

## Adding a message

- Requests live in `Sources/TandemMessages/Requests/`, responses in `Sources/TandemMessages/Responses/`.
- Give it correct `MessageProps`: opcode, size, characteristic, `signed`, `responseOpCode`, and
  `modifiesInsulinDelivery` for an insulin-affecting message. A signed response needs `signed: true` too.
- Register a new response in `ResponseParser`, which dispatches on characteristic and opcode (opcodes
  aren't unique across characteristics).
- A new signed write is refused by the link until it's added to `SupportMatrix.allowedSignedWrites`.
- Keep `TandemMessages` free of platform imports.
- If a field isn't confirmed on a pump, say so in its doc comment, and record it in faBolus's
  `docs/UNVERIFIED-GUESSES.md` if the app reads it.

## The gates

`./scripts/check.sh` runs every gate, and CI runs the same script, one gate per step, on Xcode 27.2:

| Gate | What fails it |
| --- | --- |
| `build` | A compiler warning (warnings as errors). |
| `test` | A failing test, oracle parity among them. CI builds the oracle JAR first; locally, the parity tests need it built (`PUMPX2_JAVA` or `JAVA_HOME` names the Java to run it). |
| `bench` | The `Bench/` package failing to build or test. |
| `format` | `xcrun swift-format lint --strict`. `./scripts/format.sh` fixes it. |
| `swiftlint`, `shell`, `actions`, `markdown` | SwiftLint, ShellCheck, actionlint, markdownlint. |

Tools: `brew install swiftlint shellcheck actionlint openjdk@21` and
`npm install --global markdownlint-cli2@0.24.0`.

## Public API

`TandemMessages`, `TandemAuth`, `TandemLink` and `TandemBLE` are an API other apps depend on. Prefer
additive changes; a breaking change gets a version bump and a note in the pull request. Releases are
tagged `vX.Y.Z` and recorded in [CHANGELOG.md](CHANGELOG.md). faBolus pins TandemKit by revision in its
`Packages/PumpSession/Package.swift`; read the pin there.

## Before you open a pull request

- `./scripts/check.sh` passes.
- The products still build for iOS and watchOS, which `check.sh` doesn't cover:
  `xcodebuild -scheme TandemAuth -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO build`,
  and likewise for `TandemBLE`, `TandemLink` and `TandemMessages`, and for `generic/platform=iOS`.
- Say what was tested on a pump and what only in tests.
