import Testing
import Foundation

/// BLE unit tests must not construct a real `CBCentralManager` (`PumpBLEClient()`) — the `swift test`
/// host has no Bluetooth entitlement and TCC-aborts. Use `PumpBLEClient.forUnitTest()` or inject a
/// fake via `PumpBLEClient(central:)`. This source-scan fails if the bare initializer reappears.
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
        #expect(
            violations.isEmpty,
            """
            BLE unit tests must not construct a real CBCentralManager (TCC-aborts the swift-test host — \
            see InertCentral). Use PumpBLEClient.forUnitTest() or PumpBLEClient(central:) instead. \
            Found at: \(violations.joined(separator: ", "))
            """)
    }
}
