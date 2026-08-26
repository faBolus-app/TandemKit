import Testing
import Foundation

/// Regression guard for the intermittent full-suite SIGABRT (a TCC "no NSBluetoothAlwaysUsageDescription"
/// abort — see `InertCentral`). The bare `PumpBLEClient()` initializer builds a real `CBCentralManager`,
/// which the `swift test` host process is not entitled to touch; constructing one in a unit test crashes
/// the whole combined run at a nondeterministic point. Every BLE unit test must instead go through
/// `PumpBLEClient.forUnitTest()` (inert central) or inject its own fake via `PumpBLEClient(central:)`.
///
/// This scans the sibling `Tests/TandemBLETests` sources (resolved from `#filePath`, the project's
/// established source-scan-guard idiom) and fails if the bare initializer reappears in code. Line comments
/// are stripped first so the doc-comment mentions of the pattern (including this file's) don't self-trip,
/// and the needle is assembled at runtime for the same reason. The Info.plist-carrying bench harness and
/// the hardware-gated `LiveSession` legitimately use the real initializer and live in other directories,
/// so they are out of scope by construction.
@Suite struct NoBareCentralGuardTests {

    @Test func bleUnitTestsNeverConstructARealCentralManager() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty, "guard could not enumerate any TandemBLETests sources from \(dir.path)")

        // Assembled at runtime so this guard's own source never contains the literal it forbids.
        let needle = "PumpBLEClient" + "()"
        var violations: [String] = []
        for file in files.sorted(by: { $0.path < $1.path }) {
            guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (idx, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                // Drop any line comment so `///`/`//` mentions of the pattern aren't flagged as real uses.
                let code = rawLine.range(of: "//").map { String(rawLine[..<$0.lowerBound]) } ?? String(rawLine)
                if code.contains(needle) {
                    violations.append("\(file.lastPathComponent):\(idx + 1)")
                }
            }
        }
        #expect(violations.isEmpty, """
            BLE unit tests must not construct a real CBCentralManager (TCC-aborts the swift-test host — \
            see InertCentral). Use PumpBLEClient.forUnitTest() or PumpBLEClient(central:) instead. \
            Found at: \(violations.joined(separator: ", "))
            """)
    }
}
