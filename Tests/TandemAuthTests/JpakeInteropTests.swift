import Testing
import Foundation
import TandemMessages
@testable import TandemAuth

/// Interop test: our Swift EC-JPAKE client (mbedTLS) drives the cliparser `jpake-server`
/// (the reference EC-JPAKE, as the pump uses) over a stdin/stdout handshake. Success = both
/// sides derive the **same** shared secret. This proves byte-compatibility with the pump's
/// implementation without any hardware.
@Suite(.enabled(if: JpakeOracle.available)) struct JpakeInteropTests {

    @Test func swiftClientInteropsWithOracleServer() throws {
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

        // Drive the strict request/response handshake until the server prints its result.
        var guardCount = 0
        while let line = reader.line() {
            guardCount += 1
            #expect(guardCount < 50, "handshake did not converge")
            if guardCount >= 50 { break }

            if line.hasPrefix("JPAKE_1A:") {
                serverRound1a = try JpakeOracle.messageParamBytes(line, index: 1)
                let (a, b) = try auth.makeRound1Requests()
                r1a = a
                r1b = b
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
                try send(hex(Jpake3SessionKeyRequest(challengeParam: 0)))  // round 3 (no server data needed)
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

        let serverSecret = try #require(finalDerivedSecret, "server never returned a derived secret")
        #expect(
            Hex.encode(auth.derivedSecret) == serverSecret,
            "client/server derived secrets differ — EC-JPAKE not interoperable")
        #expect(!auth.authKey.isEmpty)
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

    /// `cliparser.jar`'s `Main.class` is class-file major 58 (Java 14); a JDK below 21 cannot
    /// load it. Below this requirement `available` must be false, not merely "jar exists" — a
    /// present-but-wrong JVM must read as UNAVAILABLE, never as an EC-JPAKE interop mismatch.
    static let minimumJavaMajor = 21

    /// Parses the major version out of `java -version` text (written to stderr). Pure, so it can
    /// be unit-tested with literal inputs independent of any real JVM.
    /// Handles the legacy `"1.8.0_x"` shape (-> 8) as well as modern `"21.0.12.1"` (-> 21).
    static func parseJavaMajorVersion(from output: String) -> Int? {
        guard let openQuote = output.firstIndex(of: "\""),
            let closeQuote = output[output.index(after: openQuote)...].firstIndex(of: "\"")
        else { return nil }
        let versionToken = output[output.index(after: openQuote)..<closeQuote]
        let components = versionToken.split(separator: ".")
        guard let first = components.first, let firstNum = Int(first) else { return nil }
        if firstNum == 1, components.count >= 2, let second = Int(components[1]) {
            return second
        }
        return firstNum
    }

    /// The version-requirement boundary, named so it can be asserted non-vacuously: a wrong JVM
    /// must be detectable, not just "some JVM found".
    static func isSupportedJavaMajor(_ major: Int) -> Bool {
        major >= minimumJavaMajor
    }

    /// Memoized (spawned at most once per process, matching `java`'s memoization) resolution of
    /// `java -version`. Any spawn or parse failure resolves to `nil` — fail closed.
    static let resolvedJavaMajorVersion: Int? = {
        guard FileManager.default.isExecutableFile(atPath: java) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: java)
        proc.arguments = ["-version"]
        let errPipe = Pipe()
        proc.standardOutput = Pipe()
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return nil
        }
        // `java -version` writes to stderr, not stdout.
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        return parseJavaMajorVersion(from: String(decoding: errData, as: UTF8.self))
    }()

    /// True when the JAR, an executable `java`, AND a JVM major version >= `minimumJavaMajor` are
    /// all present. A present-but-too-old JVM must read as unavailable (the suite skips) rather
    /// than run and misreport a spurious EC-JPAKE interop failure.
    static var available: Bool {
        guard FileManager.default.fileExists(atPath: jar),
            FileManager.default.isExecutableFile(atPath: java),
            let major = resolvedJavaMajorVersion
        else { return false }
        return isSupportedJavaMajor(major)
    }

    /// Self-describing reason the oracle is unavailable, mirroring `OracleRunner`'s diagnostic
    /// shape, so a wrong/absent JVM names itself instead of silently skipping.
    static var unavailableDiagnostic: String {
        "jar=\(jar) java=\(java) resolvedJavaMajor=\(resolvedJavaMajorVersion.map(String.init) ?? "unknown") (need >= \(minimumJavaMajor))"
    }

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
            let arr = params[index] as? [Any]
        else { return [] }
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
            if chunk.isEmpty {  // EOF
                if buffer.isEmpty { return nil }
                let rest = String(data: buffer, encoding: .utf8)
                buffer.removeAll()
                return rest
            }
            buffer.append(chunk)
        }
    }
}
