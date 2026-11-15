import Foundation
import Testing
@testable import TandemMessages

/// `BolusEndReason` is pumpX2's `LastBolusStatusAbstractResponse.BolusStatus`, value for value. The
/// oracle's command line prints the id, never the name, so the names are read from the vendored source
/// itself: the oracle, not this repo's code, is what's read here.
@Suite struct BolusEndReasonOracleTests {
    static let source = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(
            "vendor/pumpx2-oracle/messages/src/main/java/com/jwoglom/pumpx2/pump/messages/response/currentStatus/LastBolusStatusAbstractResponse.java"
        )

    /// The oracle's `BolusStatus` constants, name to id.
    static func oracleBolusStatus() throws -> [String: Int] {
        let text = try String(contentsOf: source, encoding: .utf8)
        let start = try #require(text.range(of: "public enum BolusStatus {"))
        let end = try #require(text[start.upperBound...].range(of: ";"))
        let body = text[start.upperBound..<end.lowerBound]
        var constants: [String: Int] = [:]
        for match in body.matches(of: /([A-Z_]+)\((\d+)\)/) {
            constants[String(match.output.1)] = Int(match.output.2)
        }
        return constants
    }

    @Test func everyOracleValueHasACaseAndNoneMore() throws {
        let oracle = try Self.oracleBolusStatus()
        let names: [BolusEndReason: String] = [
            .userAbort: "STOPPED_USER_TERMINATED", .alarm: "STOPPED_ALARM", .malfunction: "STOPPED_MALFUNCTION",
            .completed: "COMPLETE", .stoppedWireless: "STOPPED_WIRELESS", .rejectedWireless: "REJECTED_WIRELESS",
            .autoSuspend: "TERMINATED_PLGS"
        ]
        #expect(oracle.count == BolusEndReason.allCases.count)
        for reason in BolusEndReason.allCases {
            let name = try #require(names[reason])
            #expect(oracle[name] == reason.rawValue, "\(reason)")
        }
    }
}
