// swift-tools-version: 6.0
// PumpX2Kit — Swift port of the jwoglom/pumpx2 Tandem pump protocol.
// Independent, open-source project in development for experimental use; not FDA-cleared.
// Not affiliated with, endorsed by, or a product of Tandem Diabetes Care or Dexcom.
import PackageDescription

let package = Package(
    name: "TandemKit",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13), // for command-line tests + the harness
    ],
    products: [
        .library(name: "TandemMessages", targets: ["TandemMessages"]),
        .library(name: "TandemAuth", targets: ["TandemAuth"]),
        .library(name: "TandemBLE", targets: ["TandemBLE"]),
        .executable(name: "TandemBenchHarness", targets: ["TandemBenchHarness"]),
    ],
    targets: [
        // Portable protocol: framing, opcodes, message models, packetization.
        // No platform dependencies — compiles everywhere.
        .target(name: "TandemMessages"),

        // Vendored mbedTLS EC-JPAKE (secp256r1/SHA-256), pinned submodule at
        // vendor/mbedtls (v3.6.7, Apache-2.0). The needed mbedTLS .c files are symlinked into
        // mbedtls_lib/ (see scripts/link-mbedtls.sh) and compiled as separate TUs alongside
        // our shim. Only cmbedtls_jpake.h is exposed to Swift — mbedTLS headers are reached
        // via header search paths, so the full (unparseable-under-min-config) header tree is
        // never turned into a module. Custom minimal config drops PSA/SSL/entropy.
        .target(
            name: "CMbedTLSJPAKE",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("../../vendor/mbedtls/include"),
                .headerSearchPath("../../vendor/mbedtls/library"),
                // D3 (§1.3 version-pin): `.define` instead of `.unsafeFlags(["-D…"])`. SwiftPM forbids
                // `.unsafeFlags` in any target reached by a URL+version dependency, which is exactly what
                // blocked pinning PumpX2Kit by version. `.define(_, to:)` emits the identical
                // `-DMBEDTLS_CONFIG_FILE="mbedtls_config_min.h"` (quotes retained for the `#include`), so
                // the minimal-config selection is byte-for-byte unchanged. The header-search paths stay —
                // they resolve inside the package root (vendor/mbedtls is a submodule SwiftPM fetches).
                .define("MBEDTLS_CONFIG_FILE", to: "\"mbedtls_config_min.h\""),
            ]
        ),

        // Pairing handshake (legacy CentralChallenge + modern JPAKE) and per-command
        // HMAC signing. Depends on Messages for message shapes and byte helpers.
        .target(name: "TandemAuth", dependencies: ["TandemMessages", "CMbedTLSJPAKE"]),
        // (CMbedTLSJPAKE compiles the vendored mbedTLS EC-JPAKE sources; see above.)

        // Core Bluetooth central transport. Platform-agnostic (iOS + watchOS): imports
        // CoreBluetooth only, never UIKit. Built in Swift 5 language mode: this target is
        // CoreBluetooth delegate glue. Builds in the package's Swift 6 language mode: CB's
        // non-Sendable objects are main-queue-confined (the central uses `queue: .main`), so the
        // delegates hop via `MainActor.assumeIsolated` and `@preconcurrency import CoreBluetooth`
        // lets CB-typed callback params cross into the main-actor closures.
        .target(
            name: "TandemBLE",
            dependencies: ["TandemMessages", "TandemAuth"]
        ),

        // Oracle/test CLI: connect → status → bolus → cancel.
        .executableTarget(
            name: "TandemBenchHarness",
            dependencies: ["TandemMessages", "TandemAuth", "TandemBLE"],
            // Not a SwiftPM resource — it's embedded into the binary via the linker flag below.
            exclude: ["Info.plist"],
            // Embed an Info.plist carrying NSBluetoothAlwaysUsageDescription into the executable's
            // __TEXT,__info_plist section. macOS ABORTS a process that touches CoreBluetooth without
            // this key (TCC privacy violation), so the harness must carry it to scan/connect. The
            // `swift test` suite can NOT carry this (its host process is Apple's swiftpm-testing-helper),
            // which is why hardware validation runs through THIS executable, not the test target.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TandemBenchHarness/Info.plist",
                ])
            ]
        ),

        // Tests. The oracle (cliparser) tests live in TandemMessagesTests.
        .testTarget(name: "TandemMessagesTests", dependencies: ["TandemMessages"]),
        .testTarget(name: "TandemAuthTests", dependencies: ["TandemAuth"]),
        .testTarget(name: "TandemBLETests", dependencies: ["TandemBLE"]),

        // Tier-1 hardware bench harness (LOCAL / manual-only, never in public CI). The whole
        // suite is GATED on a real pump + env being present (`HardwareGate.connected`), mirroring
        // the oracle gate `@Suite(.enabled(if: OracleRunner.isAvailable))` — with no pump it SKIPS
        // (stays green), it never fails. Drives the real `PumpBLEClient` behind the two delivery
        // walls (WritePolicy default `.readOnly`; Packetize `actionsAffectingInsulinDeliveryEnabled`).
        // Run: `swift test --filter TandemHardwareTests`.
        .testTarget(
            name: "TandemHardwareTests",
            dependencies: ["TandemMessages", "TandemAuth", "TandemBLE"]
        ),
    ]
)
