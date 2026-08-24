import Testing
import Foundation
import TandemMessages
@testable import TandemAuth

/// Interop test: our Swift EC-JPAKE client (mbedTLS) drives the cliparser `jpake-server`
/// (the reference EC-JPAKE, as the pump uses) over a stdin/stdout handshake. Success = both
/// sides derive the **same** shared secret. This proves byte-compatibility with the pump's
/// implementation without any hardware.
@Suite(.enabled(if: JpakeOracle.available)) struct JpakeInteropTests {

    /// Outcome of one full handshake attempt against a freshly-spawned oracle process.
    private struct InteropOutcome {
        /// The server's derived secret, or `nil` if the oracle produced no result this attempt
        /// (an environment failure — the JVM never started or died before emitting output).
        let serverSecret: String?
        let clientSecret: String
        let authKeyEmpty: Bool
        let diagnostic: String
    }

    @Test func swiftClientInteropsWithOracleServer() throws {
        // The oracle is a spawned JVM. On a loaded/parallel CI runner it can occasionally fail to
        // start, or be killed under memory pressure, before printing any handshake output — which
        // surfaces as an empty run with no derivedSecret. That is an *environment* flake, not an
        // interop failure, so retry the whole handshake a few times. A genuine interop regression
        // (the secrets DIFFER) is deterministic — it fails on every attempt and is NOT retried
        // (see the mismatch #expect below). Retrying only the no-secret case therefore cannot mask
        // a real byte-compatibility break.
        var diagnostics: [String] = []
        for attempt in 1...4 {
            let outcome = try attemptInterop()
            guard let serverSecret = outcome.serverSecret else {
                diagnostics.append("attempt \(attempt): \(outcome.diagnostic)")
                continue
            }
            #expect(outcome.clientSecret == serverSecret,
                    "client/server derived secrets differ — EC-JPAKE not interoperable")
            #expect(!outcome.authKeyEmpty)
            return
        }
        Issue.record("EC-JPAKE oracle never returned a derived secret in 4 attempts — environment failure, not an interop mismatch: \(diagnostics.joined(separator: "; "))")
    }

    /// Drives one strict request/response handshake against a fresh `jpake-server` oracle process.
    private func attemptInterop() throws -> InteropOutcome {
        let pairingCode = "123456"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: JpakeOracle.java)
        proc.arguments = ["-jar", JpakeOracle.jar, "jpake-server", pairingCode]
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()

        let reader = LineReader(stdoutPipe.fileHandleForReading)
        func send(_ hexPackets: [String]) {
            let line = hexPackets.joined(separator: " ") + "\n"
            stdinPipe.fileHandleForWriting.write(Data(line.utf8))
        }
        func hex(_ msg: Message) throws -> [String] {
            try Packetize.packetize(msg, txId: 0).map { Hex.encode($0.build()) }
        }

        let auth = try JpakeAuth(pairingCode: pairingCode)
        var r1a: Jpake1aRequest?, r1b: Jpake1bRequest?
        var serverRound1a: [UInt8] = [], serverRound1b: [UInt8] = []
        var finalDerivedSecret: String?

        // Drive the strict request/response handshake until the server prints its result. The 200
        // cap is a pure infinite-loop safety net — strictly more lines than a real handshake emits.
        var guardCount = 0
        while let line = reader.line() {
            guardCount += 1
            if guardCount >= 200 { break }

            if line.hasPrefix("JPAKE_1A:") {
                serverRound1a = try JpakeOracle.messageParamBytes(line, index: 1)
                let (a, b) = try auth.makeRound1Requests(); r1a = a; r1b = b
                try send(hex(a))
            } else if line.hasPrefix("JPAKE_1B:") {
                serverRound1b = try JpakeOracle.messageParamBytes(line, index: 1)
                try send(hex(r1b!))
                try auth.readServerRound1(challenge1a: serverRound1a, challenge1b: serverRound1b)
            } else if line.hasPrefix("JPAKE_2:") {
                let serverRound2 = try JpakeOracle.messageParamBytes(line, index: 1)
                try auth.readServerRound2(challenge: serverRound2)
                try send(hex(auth.makeRound2Request()))
                _ = try auth.derive()
                try send(hex(Jpake3SessionKeyRequest(challengeParam: 0)))   // round 3 (no server data needed)
            } else if line.hasPrefix("JPAKE_3:") {
                let serverNonce3 = try JpakeOracle.messageParamBytes(line, index: 1)
                try send(hex(auth.makeRound4Request(serverNonce3: serverNonce3)))
            } else if line.contains("\"derivedSecret\"") {
                finalDerivedSecret = try JpakeOracle.jsonString(line, key: "derivedSecret")
                break
            }
            _ = r1a
        }
        proc.waitUntilExit()

        return InteropOutcome(
            serverSecret: finalDerivedSecret,
            clientSecret: Hex.encode(auth.derivedSecret),
            authKeyEmpty: auth.authKey.isEmpty,
            diagnostic: "oracle exit status \(proc.terminationStatus), \(guardCount) line(s) read, no derivedSecret emitted"
        )
    }
}

/// Locates the cliparser oracle + JDK and parses jpake-server output lines.
enum JpakeOracle {
    static let jar: String = {
        let cwd = FileManager.default.currentDirectoryPath
        return "\(cwd)/vendor/pumpx2-oracle/cliparser/build/libs/cliparser.jar"
    }()
    static let java: String = {
        if let e = ProcessInfo.processInfo.environment["PUMPX2_JAVA"] { return e }
        let brew = "/opt/homebrew/opt/openjdk@21/bin/java"
        return FileManager.default.isExecutableFile(atPath: brew) ? brew : "/usr/bin/java"
    }()
    static var available: Bool { FileManager.default.fileExists(atPath: jar) }

    /// The JSON object after the "PREFIX: " on a server line.
    private static func json(_ line: String) throws -> [String: Any] {
        guard let braceIdx = line.firstIndex(of: "{") else { return [:] }
        let data = Data(line[braceIdx...].utf8)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// `messageParams[index]` as bytes (the oracle emits signed Java bytes as JSON ints).
    static func messageParamBytes(_ line: String, index: Int) throws -> [UInt8] {
        let obj = try json(line)
        guard let params = obj["messageParams"] as? [Any], index < params.count,
              let arr = params[index] as? [Any] else { return [] }
        return arr.compactMap { ($0 as? NSNumber).map { UInt8(truncatingIfNeeded: $0.intValue) } }
    }

    static func jsonString(_ line: String, key: String) throws -> String? {
        (try json(line))[key] as? String
    }
}

/// Blocking line reader over a FileHandle (reads chunks, yields newline-terminated lines).
final class LineReader {
    private let handle: FileHandle
    private var buffer = Data()
    init(_ handle: FileHandle) { self.handle = handle }
    func line() -> String? {
        while true {
            if let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            let chunk = handle.availableData
            if chunk.isEmpty {   // EOF
                if buffer.isEmpty { return nil }
                let rest = String(data: buffer, encoding: .utf8); buffer.removeAll(); return rest
            }
            buffer.append(chunk)
        }
    }
}
