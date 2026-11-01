> [!CAUTION]
> **Not a medical device — do not use it for treatment decisions.** TandemKit is experimental software
> under active development. It is **not FDA-cleared or approved** and has **not** been clinically
> validated, and its insulin-dosing path is treated as unproven. **Do not rely on it to make or carry out
> any insulin-dosing, treatment, or other clinical decision.** It is for software development and
> evaluation only — always confirm every reading and dose directly on your pump and CGM.

# TandemKit

A Swift port of the reverse-engineered [`jwoglom/pumpx2`](https://github.com/jwoglom/pumpx2)
protocol for the Tandem **t:slim X2 / Mobi** insulin pump. It provides the shared
protocol / auth / BLE core that the [`faBolus`](../faBolus) app and its watch /
Garmin remotes build on.

> [!WARNING]
> **Experimental — in development.** TandemKit is an independent, open-source project in
> development for experimental use. It is **not FDA-cleared**, and the insulin-dosing path is
> treated as unproven; if you build or use it, you assume all responsibility. **Not affiliated
> with, endorsed by, or a product of Tandem Diabetes Care or Dexcom.**

## Modules

| Target | Purpose |
| --- | --- |
| `TandemMessages` | Message framing, opcodes, request/response models, packetization. Portable, no platform deps. |
| `TandemAuth` | Pairing handshake (legacy CentralChallenge + modern JPAKE) and per-command HMAC signing. **Safety-critical.** |
| `TandemBLE` | Core Bluetooth central: scan / connect / bond / discover / notify. Platform-agnostic (iOS + watchOS). |

Bench tooling lives in a separate package, [`Bench/`](Bench/README.md): the `TandemBenchHarness` CLI,
its session planner and coverage matrix, and the gated hardware tests. The library never links it.

## Use it in your project

TandemKit is a reusable SwiftPM package (iOS 16+, watchOS 9+, macOS 13+). Add it as a dependency and
import the products you need:

```swift
// Package.swift
.package(url: "https://github.com/faBolus-app/TandemKit.git", from: "0.1.0")
// then, per target:
.product(name: "TandemMessages", package: "TandemKit"),  // message framing + models
.product(name: "TandemAuth", package: "TandemKit"),      // pairing (JPAKE/legacy) + HMAC signing
.product(name: "TandemLink", package: "TandemKit"),      // the connection state machine
.product(name: "TandemBLE", package: "TandemKit"),       // the link over Core Bluetooth
```

Typical entry points: `PumpConnection` (pair, keep the link up, send requests and get typed results),
`SupportMatrix` (what each pump answers), and the request/response types in `TandemMessages`. For a
worked example, see `Bench/Sources/TandemBenchHarness`. To build a non-faBolus app on it, depend on
these products directly — you don't need faBolus. Contributions go
through PR, not fork; see [`CONTRIBUTING.md`](CONTRIBUTING.md).

## The cliparser oracle

Every outgoing message must **byte-match** the upstream `cliparser` output ("byte-exact or
fail"). The upstream `pumpx2` repo is pinned as a git submodule at `vendor/pumpx2-oracle`
(see [`PINNED.md`](PINNED.md)); its `cliparser` shadow JAR is the byte-level oracle.

Build the oracle (requires **JDK 17+** — the pinned Gradle 9.x will not run on JDK 11):

```sh
cd vendor/pumpx2-oracle
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home ./gradlew :cliparser:shadowJar
# → cliparser/build/libs/cliparser.jar  (shadow/fat jar)
```

Generate reference bytes for a message:

```sh
java -jar cliparser.jar encode <txId> <MessageName> '<jsonParams>'
# prints JSON incl. a "packets" array of hex — the bytes Swift output is compared against
# e.g. encode 0 ApiVersionRequest '{}' → packets ["00002000005a4a"]
```

## Build & test

```sh
swift build
swift test
```

## Status

**Milestone 1 definition-of-done met** — read-only monitor, 6-digit JPAKE pairing, and a
signed bolus have been validated on real hardware (see [`PINNED.md`](PINNED.md) for the
log). Every outgoing message is byte-exact against the `cliparser` oracle in CI.

## The app built on this

[`faBolus`](https://github.com/faBolus-app/faBolus) is the iPhone app that
consumes TandemKit (the Garmin remote lives in
[`faBolusGarmin`](https://github.com/faBolus-app/faBolusGarmin)). Its documentation — a
no-experience-required build guide, usage, and customization — is the best starting point:

### 👉 <https://fabolus.org/>
