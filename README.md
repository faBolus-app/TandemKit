> [!CAUTION]
> TandemKit is experimental, in-development software — not a medical device and not FDA-cleared. It is for
> experimental and demonstration use. Not medical advice. If you build or use it, you assume all
> responsibility.

# TandemKit

A Swift port of [`jwoglom/pumpx2`](https://github.com/jwoglom/pumpx2), the reverse-engineered Bluetooth
protocol of the Tandem t:slim X2 insulin pump: messages, pairing, signing and the connection. It's the
pump library under the [faBolus](https://github.com/faBolus-app/faBolus) app, and any app can use it.

> [!NOTE]
> TandemKit is an independent, open-source project. It is not affiliated with Tandem Diabetes Care or
> Dexcom.

## Products

| Product | What it is |
| --- | --- |
| `TandemMessages` | Message framing, opcodes, request and response types, packetization, and `SupportMatrix` (which commands a pump answers). No platform dependencies. |
| `TandemAuth` | Pairing (legacy CentralChallenge with the 16-character code, and EC-JPAKE with the 6-digit code, through vendored mbedTLS) and per-command HMAC signing. |
| `TandemLink` | The connection as a state machine: `LinkReducer.reduce(state, input)` returns the new state and the effects to perform, with no CoreBluetooth import. |
| `TandemBLE` | `PumpConnection`, which runs the reducer over CoreBluetooth: scan, connect, bond, discover, notify, and one request in flight. |

Bench tooling is a separate package, [`Bench/`](Bench/README.md): a CLI for a real pump, its session
planner and coverage matrix. The library never links it.

## Use it

TandemKit is a SwiftPM package for iOS 16+, watchOS 9+ and macOS 13+. Pin it by a release tag (or by
revision):

```swift
// Package.swift
.package(url: "https://github.com/faBolus-app/TandemKit.git", exact: "0.5.0"),
// then, per target:
.product(name: "TandemMessages", package: "TandemKit"),
.product(name: "TandemAuth", package: "TandemKit"),
.product(name: "TandemLink", package: "TandemKit"),
.product(name: "TandemBLE", package: "TandemKit"),
```

SwiftPM fetches the submodules with it. The library builds from mbedTLS; the pumpx2 oracle is only used by
the tests.

The entry point is `PumpConnection`: pair, keep the link up, and send requests and get typed results.
`send(_:allowing:)` grants write risk for that one call, and a signed write outside
`SupportMatrix.allowedSignedWrites` is refused before a byte is built. For a worked example, see
`Bench/Sources/TandemBenchHarness`; for a full app, faBolus's `Packages/PumpSession`.

## The cliparser oracle

Every outgoing message must byte-match upstream's `cliparser` output. pumpx2 is pinned as a submodule at
`vendor/pumpx2-oracle` (see [`PINNED.md`](PINNED.md)), and its `cliparser` JAR is the oracle.

Build the oracle (JDK 21, which the parity tests need too):

```sh
git submodule update --init
cd vendor/pumpx2-oracle
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew :cliparser:shadowJar
# → cliparser/build/libs/cliparser.jar
```

Reference bytes for a message:

```sh
java -jar cliparser.jar encode <txId> <MessageName> '<jsonParams>'
# prints JSON with a "packets" array of hex: the bytes the Swift output is compared against
# e.g. encode 0 ApiVersionRequest '{}' → packets ["00002000005a4a"]
```

## Build and test

```sh
./scripts/check.sh      # every gate, as CI runs it
swift test              # the suite alone
```

The suite needs the oracle JAR built (above) and JDK 21; without them the oracle gate fails rather than
skip parity. `PUMPX2_ALLOW_ORACLE_SKIP=1` skips it for local Swift-only work, never in CI.
`./scripts/test.sh` runs the suite on a Mac with only the Command Line Tools. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## The app built on this

[faBolus](https://github.com/faBolus-app/faBolus) is the iPhone app that uses TandemKit; its watch app is
[faBolusGarmin](https://github.com/faBolus-app/faBolusGarmin). The documentation, with a build guide that
needs no programming, is at <https://fabolus.org/>.

## Acknowledgments

TandemKit is a port of James Woglom's ([@jwoglom](https://github.com/jwoglom)) pumpx2. His
reverse-engineering is the foundation of this library. See [NOTICE.md](NOTICE.md).

## License and trademark

MIT (see [LICENSE](LICENSE)). faBolus™ is a trademark of Zev Granowitz; see [NOTICE.md](NOTICE.md).
