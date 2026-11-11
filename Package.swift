// swift-tools-version: 6.1
// TandemKit — Swift port of the jwoglom/pumpx2 Tandem pump protocol.
// Independent, open-source project in development for experimental use; not FDA-cleared.
// Not affiliated with, endorsed by, or a product of Tandem Diabetes Care or Dexcom.
import PackageDescription

let package = Package(
    name: "TandemKit",
    platforms: [
        .iOS(.v16),
        .watchOS(.v9),
        .macOS(.v13)  // for command-line tests
    ],
    products: [
        .library(name: "TandemMessages", targets: ["TandemMessages"]),
        .library(name: "TandemAuth", targets: ["TandemAuth"]),
        .library(name: "TandemLink", targets: ["TandemLink"]),
        .library(name: "TandemBLE", targets: ["TandemBLE"])
    ],
    // Off unless a dependent names it. Only the bench package (Bench/Package.swift) does: an app's
    // dependency on TandemKit names no trait, so the bench's extra signed writes are compiled out of it.
    traits: [
        .trait(
            name: "BenchWrites",
            description: "Bench only: adds UserInteraction and ChangeTimeDate to the signed writes the link sends.")
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
                // `.define` instead of `.unsafeFlags(["-D…"])`: SwiftPM forbids `.unsafeFlags` in any target
                // reached by a URL+version dependency, so they would stop apps pinning a TandemKit release
                // by version. `.define(_, to:)` emits the identical
                // `-DMBEDTLS_CONFIG_FILE="mbedtls_config_min.h"` (quotes retained for the `#include`), so
                // the minimal-config selection is byte-for-byte unchanged. The header-search paths stay —
                // they resolve inside the package root (vendor/mbedtls is a submodule SwiftPM fetches).
                .define("MBEDTLS_CONFIG_FILE", to: "\"mbedtls_config_min.h\"")
            ]
        ),

        // Pairing handshake (legacy CentralChallenge + modern JPAKE) and per-command
        // HMAC signing. Depends on Messages for message shapes and byte helpers.
        .target(name: "TandemAuth", dependencies: ["TandemMessages", "CMbedTLSJPAKE"]),
        // (CMbedTLSJPAKE compiles the vendored mbedTLS EC-JPAKE sources; see above.)

        // The connection state machine: a pure transition function with no CoreBluetooth import, so
        // every transition is tested on any platform. TandemBLE drives it.
        .target(name: "TandemLink", dependencies: ["TandemMessages"]),

        // The CoreBluetooth adapter and the driver that runs TandemLink's state machine. Platform-
        // agnostic (iOS + watchOS): imports CoreBluetooth only, never UIKit. CB's non-Sendable objects
        // are main-queue-confined (the central uses `queue: .main`), so the delegates hop via
        // `MainActor.assumeIsolated` and pass only plain values on.
        .target(
            name: "TandemBLE",
            dependencies: ["TandemMessages", "TandemAuth", "TandemLink"]
        ),

        // Tests. The oracle (cliparser) tests live in TandemMessagesTests. The bench tooling and the
        // hardware tests are a separate package, Bench/, which the library never links.
        .testTarget(name: "TandemMessagesTests", dependencies: ["TandemMessages"]),
        .testTarget(name: "TandemAuthTests", dependencies: ["TandemAuth"]),
        .testTarget(
            name: "TandemLinkTests", dependencies: ["TandemLink"],
            resources: [.copy("Fixtures")]),
        .testTarget(name: "TandemBLETests", dependencies: ["TandemBLE", "TandemLink"])
    ]
)
