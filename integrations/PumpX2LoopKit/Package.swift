// swift-tools-version: 6.0
// PumpX2LoopKit — a LoopKit `PumpManager` driver for Tandem pumps, built on PumpX2Kit.
//
// This is a SEPARATE, OPTIONAL package. It is intentionally NOT a target of the root
// PumpX2Kit Package.swift, so `swift build` / `swift test` / the byte-exact oracle-parity
// job in the PumpX2Kit root never resolve or compile LoopKit. See README.md.
//
// UNVERIFIED — reverse-engineered Tandem protocol; NOT FDA-cleared; NOT for use with real
// insulin. For research/simulation with saline only. No affiliation with Tandem/Dexcom.
import PackageDescription

let package = Package(
    name: "PumpX2LoopKit",
    // iOS-only: LoopKit is an iOS-15 framework, and a PumpManager is meaningless off-device.
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PumpX2LoopKit", targets: ["PumpX2LoopKit"]),
    ],
    dependencies: [
        // PumpX2Kit by path — this package lives inside the PumpX2Kit repo. A path (not a
        // version) dependency is REQUIRED: PumpX2Kit's CMbedTLSJPAKE target uses `.unsafeFlags`,
        // which SwiftPM forbids in a URL+version dependency but allows via a path dependency.
        .package(path: "../.."),
        // LoopKit pinned by revision (LoopKit/LoopKit @ a5beee96, the PR-599 BLE-heartbeat merge).
        // Only the zero-external-dependency `LoopKit` library product is consumed (NOT `LoopKitUI`,
        // which pulls SwiftCharts). Package.resolved locks LoopKit + its transitive SwiftCharts.
        .package(url: "https://github.com/LoopKit/LoopKit.git",
                 revision: "a5beee96d8e0770fc6999372a73ea5f523351a43"),
    ],
    targets: [
        .target(
            name: "PumpX2LoopKit",
            dependencies: [
                .product(name: "PumpX2Messages", package: "PumpX2Kit"),
                .product(name: "PumpX2Auth", package: "PumpX2Kit"),
                .product(name: "PumpX2BLE", package: "PumpX2Kit"),
                .product(name: "LoopKit", package: "LoopKit"),
            ],
            // Swift 5 language mode: LoopKit's PumpManager is a pre-concurrency (Swift 5.7) protocol
            // whose synchronous getters are read off the main thread; the whole LoopKit driver ecosystem
            // (OmniBLE included) uses a lock-guarded state under Swift 5 rather than fighting Swift 6
            // strict-concurrency conformance against a non-isolated dependency. The core PumpX2Kit
            // targets keep their own Swift 6 mode — this is scoped to the driver.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PumpX2LoopKitTests",
            dependencies: ["PumpX2LoopKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
