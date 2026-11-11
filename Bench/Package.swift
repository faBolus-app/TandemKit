// swift-tools-version: 6.1
// TandemKit bench tooling: the hardware harness, its session planner and coverage matrix, and the
// gated hardware tests. A separate package so nothing here can be linked into an app: the library
// products live in the parent package, and this one only depends on them.
import PackageDescription

let package = Package(
    name: "TandemKitBench",
    platforms: [.macOS(.v13)],
    dependencies: [
        // BenchWrites: the bench's two extra signed writes (UserInteraction, ChangeTimeDate). Only this
        // package enables it; an app's dependency doesn't, so they are compiled out of every app.
        .package(name: "TandemKit", path: "..", traits: ["BenchWrites"])
    ],
    targets: [
        // Bench session planning, the coverage matrix, and the bench-bolus simulator.
        .target(
            name: "TandemBench",
            dependencies: [.product(name: "TandemMessages", package: "TandemKit")]
        ),

        // The bench CLI against a real pump: scan, the read-only diagnostics, monitor and dismiss.
        .executableTarget(
            name: "TandemBenchHarness",
            dependencies: [
                "TandemBench",
                .product(name: "TandemMessages", package: "TandemKit"),
                .product(name: "TandemAuth", package: "TandemKit"),
                .product(name: "TandemLink", package: "TandemKit"),
                .product(name: "TandemBLE", package: "TandemKit")
            ],
            // Not a SwiftPM resource — it's embedded into the binary via the linker flag below.
            exclude: ["Info.plist"],
            // Embed an Info.plist carrying NSBluetoothAlwaysUsageDescription into the executable's
            // __TEXT,__info_plist section. macOS aborts a process that touches CoreBluetooth without
            // this key, so the harness must carry it to scan or connect. `swift test` can't (its host
            // process is Apple's testing helper), which is why hardware runs go through this executable.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/TandemBenchHarness/Info.plist"
                ])
            ]
        ),

        .testTarget(
            name: "TandemBenchTests",
            dependencies: ["TandemBench", .product(name: "TandemMessages", package: "TandemKit")]
        )
    ]
)
