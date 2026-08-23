import Foundation
import TandemMessages

// CoverageArtifacts — persistence for the resumable bench coverage matrix (deliverable #5).
//
// The matrix accumulates ACROSS bench sessions. This store loads the accumulated JSON (if any), and
// after a session writes back BOTH a machine-readable `COVERAGE-MATRIX.json` (the source of truth that
// the next session resumes from) and a human-readable `COVERAGE-MATRIX.md`. All pure Foundation file I/O
// — the merge/classification/rendering logic it calls lives in TandemMessages and is unit-tested.

enum BenchCoverageStore {
    /// Directory holding the coverage artifacts. Override with `PUMPX2_BENCH_COVERAGE_DIR`; defaults to
    /// `./bench-coverage` relative to the process working dir (the package root under `swift run`).
    static var directory: URL {
        if let env = ProcessInfo.processInfo.environment["PUMPX2_BENCH_COVERAGE_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: env, isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("bench-coverage", isDirectory: true)
    }

    static var jsonURL: URL { directory.appendingPathComponent("COVERAGE-MATRIX.json") }
    static var markdownURL: URL { directory.appendingPathComponent("COVERAGE-MATRIX.md") }

    /// Load the accumulated matrix, or an empty one if none exists yet (first session).
    static func load() -> BenchCoverageMatrix {
        guard let data = try? Data(contentsOf: jsonURL),
              let matrix = try? JSONDecoder().decode(BenchCoverageMatrix.self, from: data) else {
            return BenchCoverageMatrix()
        }
        return matrix
    }

    /// Persist the accumulated matrix (JSON, canonical) + a rendered Markdown view.
    static func save(_ matrix: BenchCoverageMatrix, generatedAt: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(matrix).write(to: jsonURL)
        try matrix.renderMarkdown(generatedAt: generatedAt).data(using: .utf8)!.write(to: markdownURL)
    }

    static func iso8601Now() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: Date())
    }
}

// MARK: - Offline self-test / artifact seeder (NO Bluetooth)

/// The representative bench sessions the owner intends to run (the matrix's known axes). Nothing here is
/// hardware — it PLANS each session and persists the accumulated matrix, so the committed artifact honestly
/// shows the pre-bench state: exercisable cells `untested`, model-restricted cells `n/a`, missing-config
/// cells `deferred`, destructive/settings writes `gap`. Nothing is ever marked PASS without a real pump.
enum BenchCoverageSelfTest {
    // Firmware labels are the DEFAULT live-run labels ("API x.y" — what `coverage` produces without a
    // PUMP_FIRMWARE_TAG), so a real bench session on the same (model, API, cartridge, CGM) lands on the
    // SAME matrix key and its real PASS/FAIL cleanly overwrites this seed's placeholder (merge precedence),
    // rather than accumulating a duplicate row.
    static let representativeSessions: [BenchSessionConfig] = [
        // old t:slim X2 (legacy V1, no cartridge, no CGM) — the RUNNABLE-NOW config.
        BenchSessionConfig(model: .tslim, apiVersion: .v2_5, firmwareLabel: "API 2.5",
                           pairingScheme: .legacyV1, cartridgePresent: false, cgmPresent: false,
                           salineAttested: false, deliveryEnabled: false),
        // new t:slim X2 (JPAKE), saline cartridge, no CGM.
        BenchSessionConfig(model: .tslim, apiVersion: .v3_4, firmwareLabel: "API 3.4",
                           pairingScheme: .jpake, cartridgePresent: true, cgmPresent: false,
                           salineAttested: true, deliveryEnabled: true),
        // new t:slim X2 (JPAKE), saline cartridge + CGM.
        BenchSessionConfig(model: .tslim, apiVersion: .v3_4, firmwareLabel: "API 3.4",
                           pairingScheme: .jpake, cartridgePresent: true, cgmPresent: true,
                           salineAttested: true, deliveryEnabled: true),
        // Mobi (JPAKE), saline cartridge, no CGM — the only config that can cover the 11 Mobi-only deliveries.
        BenchSessionConfig(model: .mobi, apiVersion: .mobi_v3_6, firmwareLabel: "API 3.6",
                           pairingScheme: .jpake, cartridgePresent: true, cgmPresent: false,
                           salineAttested: true, deliveryEnabled: true),
        // Mobi (JPAKE), saline cartridge + CGM.
        BenchSessionConfig(model: .mobi, apiVersion: .mobi_v3_6, firmwareLabel: "API 3.6",
                           pairingScheme: .jpake, cartridgePresent: true, cgmPresent: true,
                           salineAttested: true, deliveryEnabled: true),
    ]

    static func run() {
        let ts = BenchCoverageStore.iso8601Now()
        var matrix = BenchCoverageMatrix()
        for cfg in representativeSessions {
            matrix.record(BenchCoverage.planSession(cfg, timestamp: ts))
            print("planned session: \(cfg.label)")
        }
        let rolls = matrix.rollups()
        var counts: [BenchCellState: Int] = [:]
        for r in rolls { counts[r.best, default: 0] += 1 }
        print("\n\(BenchCommandCatalog.all.count) commands enumerated · \(matrix.cells.count) cells across "
            + "\(representativeSessions.count) representative configs")
        print("rolled-up dispositions: "
            + BenchCellState.allCases.filter { (counts[$0] ?? 0) > 0 }
                .map { "\($0.rawValue)=\(counts[$0]!)" }.joined(separator: "  "))
        do {
            try BenchCoverageStore.save(matrix, generatedAt: ts)
            print("\nwrote \(BenchCoverageStore.jsonURL.path)")
            print("wrote \(BenchCoverageStore.markdownURL.path)")
        } catch { print("⚠️ failed to write artifacts: \(error)") }
        print("\nNOTE: this is the PLAN only — no cell is PASS because no pump was involved. Run the real")
        print("`coverage` subcommand at the bench to fill cells in; results accumulate across sessions.")
    }
}

// MARK: - Session-config detection from env + live pump reads

enum BenchSessionDetect {
    private static func flag(_ key: String) -> Bool { ProcessInfo.processInfo.environment[key] == "1" }

    /// Build the session config from live-read model/API + the env axes. `isMobi`/`major`/`minor` come
    /// from the pump's own `ApiVersionResponse`; the cartridge/CGM/saline axes come from env (a read
    /// cannot tell saline from insulin, nor reliably that a cartridge is physically loaded).
    static func config(isMobi: Bool, apiMajor: Int, apiMinor: Int, pairingScheme: BenchPairingScheme,
                       firmwareTag: String?) -> BenchSessionConfig {
        let model: PumpModel = isMobi ? .mobi : .tslim
        let api = ApiVersion(major: apiMajor, minor: apiMinor)
        let label = firmwareTag ?? "API \(apiMajor).\(apiMinor)"
        return BenchSessionConfig(
            model: model, apiVersion: api, firmwareLabel: label, pairingScheme: pairingScheme,
            cartridgePresent: flag("PUMP_CARTRIDGE_LOADED"),
            cgmPresent: flag("PUMP_CGM_PRESENT"),
            salineAttested: flag("PUMP_SALINE_ATTESTED"),
            deliveryEnabled: flag("PUMPX2_DELIVER_SALINE"))
    }
}
