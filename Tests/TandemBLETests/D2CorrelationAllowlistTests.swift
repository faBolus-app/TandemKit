import Testing
import Foundation
import TandemMessages
@testable import TandemBLE

/// `correlationMode` defaults `.opcodeFIFO` and is `public internal(set)` — out-of-module callers
/// cannot write it. The only elevation is `setPumpFamily(.tslim)`; `.mobi` / `.unknown` stay FIFO.
/// These drive the real `PumpBLEClient` seam, not a bare coordinator.
@Suite struct D2CorrelationAllowlistTests {

    // MARK: - End-to-end allowlist through PumpBLEClient

    /// A fresh `PumpBLEClient` reports the fail-closed default `.opcodeFIFO` through the public
    /// `transactions` seam — the default an app observes, not just the coordinator initializer.
    @MainActor @Test func defaultCorrelationModeIsFifoViaClient() {
        let client = PumpBLEClient.forUnitTest()
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    /// The only family that elevates: `setPumpFamily(.tslim)` puts the shared coordinator into `.txIdMatch`.
    @MainActor @Test func armingTslimElevatesToTxIdMatch() {
        let client = PumpBLEClient.forUnitTest()
        client.setPumpFamily(.tslim)
        #expect(client.transactions.correlationMode == .txIdMatch)
    }

    /// Mobi's txId echo is unconfirmed, so `setPumpFamily(.mobi)` must stay FIFO even though the caller asked for that family.
    @MainActor @Test func allowlistRejectsMobiStaysFifo() {
        let client = PumpBLEClient.forUnitTest()
        client.setPumpFamily(.mobi)
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    /// An unidentified pump fails closed to FIFO — `setPumpFamily(.unknown)` never elevates.
    @MainActor @Test func allowlistRejectsUnknownStaysFifo() {
        let client = PumpBLEClient.forUnitTest()
        client.setPumpFamily(.unknown)
        #expect(client.transactions.correlationMode == .opcodeFIFO)
    }

    // MARK: - Source resolution (mirrors the project's #filePath-rooted source-scan guard pattern)

    /// Resolve the TandemKit repo root by walking up from `#filePath` until the audited coordinator
    /// source exists. The guards scan the real Sources file so a future edit that alters the default path trips.
    private static func repoRootURL() -> URL? {
        let fm = FileManager.default
        var probe = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = probe.appendingPathComponent("Sources/TandemBLE/PumpTransactionCoordinator.swift")
            if fm.fileExists(atPath: candidate.path) { return probe }
            probe = probe.deletingLastPathComponent()
        }
        return nil
    }

    private static func readSource(_ relativePath: String) -> String? {
        guard let root = repoRootURL() else { return nil }
        return try? String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - FIFO byte-identity + parser-additivity structural guards

    /// The `.opcodeFIFO` branch of `ingest` must keep the exact FIFO predicate, and `.txIdMatch` must
    /// stay a separate case. Changing the FIFO predicate would mis-correlate every faBolus dose-path read.
    @Test func opcodeFifoBranchIsByteIdenticalStructuralGuard() throws {
        guard let source = Self.readSource("Sources/TandemBLE/PumpTransactionCoordinator.swift") else {
            Issue.record("could not resolve PumpTransactionCoordinator.swift from #filePath=\(#filePath)")
            return
        }
        // The two branches are distinct switch cases (default path is separated from txId correlation).
        #expect(source.contains("case .opcodeFIFO:"),
                "the .opcodeFIFO switch case must exist as the default correlation path")
        #expect(source.contains("case .txIdMatch:"),
                "the .txIdMatch branch must be a SEPARATE case, never merged into the default path")
        // The exact FIFO predicate — characteristic AND opcode, no txId.
        let fifoPredicate = "$0.expectedCharacteristic == characteristic && $0.expectedOpCode == opCode"
        #expect(source.contains(fifoPredicate),
                "the .opcodeFIFO predicate diverged from the pre-D2 FIFO match — REVERT-TRIGGER (D-03)")
        // The predicate must sit inside the .opcodeFIFO case region, ahead of the .txIdMatch case.
        if let fifoCaseStart = source.range(of: "case .opcodeFIFO:"),
           let txCaseStart = source.range(of: "case .txIdMatch:") {
            let fifoRegion = source[fifoCaseStart.upperBound..<txCaseStart.lowerBound]
            #expect(fifoRegion.contains(fifoPredicate),
                    "the FIFO predicate must live in the .opcodeFIFO case region, not the txId branch")
        } else {
            Issue.record("could not bound the .opcodeFIFO case region between the two switch cases")
        }
    }

    /// The op-77 error reply is registered on `.control` as a purely additive `(characteristic, opcode)` key.
    /// The pre-existing `.currentStatus` op-77 registration is untouched — opcodes are not globally unique.
    @Test func op77ControlKeyIsAdditiveNotShadowingStructuralGuard() throws {
        guard let source = Self.readSource("Sources/TandemMessages/Responses/ResponseParser.swift") else {
            Issue.record("could not resolve ResponseParser.swift from #filePath=\(#filePath)")
            return
        }
        // The untouched currentStatus variant (ErrorResponse.props default characteristic is .currentStatus).
        #expect(source.contains("add(ErrorResponse.self)"),
                "the pre-existing .currentStatus op-77 registration must remain untouched (D-08)")
        // The additive control-variant key.
        #expect(source.contains("add(ErrorResponse.self, on: .control)"),
                "the additive op-77-on-.control registration must be present (D-08)")
        // Exactly one .control override for ErrorResponse — no shadowing / no duplicate key.
        let controlKeyCount = source.components(separatedBy: "add(ErrorResponse.self, on: .control)").count - 1
        #expect(controlKeyCount == 1,
                "expected exactly one op-77-on-.control key; a second would shadow it (found \(controlKeyCount))")
    }

    // MARK: - Fail-closed reset + call-site routing guard

    /// Extract a function body by balanced braces, starting at `signature`. Returns the substring between
    /// the opening `{` that follows the signature and its matching `}` — i.e. exactly what the function
    /// executes, no sibling code.
    private static func functionBody(in source: String, signature: String) -> String? {
        guard let sigRange = source.range(of: signature) else { return nil }
        guard let openBrace = source[sigRange.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var i = openBrace
        while i < source.endIndex {
            let ch = source[i]
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let bodyStart = source.index(after: openBrace)
                    return String(source[bodyStart..<i])
                }
            }
            i = source.index(after: i)
        }
        return nil
    }

    /// `failClosed` is private (CoreBluetooth disconnect is the runtime trigger), so this source-scan
    /// pins that the body resets `correlationMode` to `.opcodeFIFO` — a reconnect must never inherit
    /// `.txIdMatch` — and that every disconnect / failed-connect / restore / error / establishment-timeout /
    /// write-error edge routes through that single fail-closed teardown.
    @Test func failClosedResetsModeAndAllSixEdgesRouteThroughIt() throws {
        guard let source = Self.readSource("Sources/TandemBLE/PumpBLEClient.swift") else {
            Issue.record("could not resolve PumpBLEClient.swift from #filePath=\(#filePath)")
            return
        }
        // (a) The reset lives INSIDE the failClosed body (not merely somewhere in the file).
        guard let body = Self.functionBody(in: source, signature: "private func failClosed(resumePending: Bool)") else {
            Issue.record("could not extract the failClosed(resumePending:) function body by balanced braces")
            return
        }
        #expect(body.contains("transactions.correlationMode = .opcodeFIFO"),
                "failClosed must reset correlationMode to the FIFO reference mode on every link change (D-04 #2)")
        // Exactly eight CALL SITES (true/false variants; the definition uses `Bool` and is not counted).
        // The seventh is `establishmentTimedOut()`; the eighth is `handleWriteResult`'s error branch.
        let trueCalls = source.components(separatedBy: "failClosed(resumePending: true)").count - 1
        let falseCalls = source.components(separatedBy: "failClosed(resumePending: false)").count - 1
        let callSites = trueCalls + falseCalls
        #expect(callSites == 8,
                "expected exactly eight disconnect/restore/error/establishment-timeout/write-error edges routing through failClosed (found \(callSites))")
    }
}
