import Foundation

/// Runs the upstream `cliparser` JAR — the byte-level oracle — and returns the packet hex it
/// produces for a given message. Swift-produced bytes are asserted equal to this ("byte-exact
/// or fail").
///
/// Requests go to one long-lived `cliparser serve` JVM (see `OracleServer`) rather than a JVM per
/// call: start-up costs about 0.4 s, which is most of the time a one-shot call takes.
///
/// Resolution order (all overridable by env so CI can point at its own build):
///   - JDK:  $PUMPX2_JAVA, else Homebrew openjdk@21, else `java` on PATH.
///   - JAR:  $PUMPX2_ORACLE_JAR, else vendor/pumpx2-oracle/cliparser/build/libs/cliparser.jar.
enum OracleRunner {
    struct EncodeResult: Decodable {
        let messageName: String
        let txId: String
        let packets: [String]
        let characteristicName: String
        let characteristic: String
    }

    enum OracleError: Error, CustomStringConvertible {
        case unavailable(String)
        case failed(String)
        var description: String {
            switch self {
            case .unavailable(let s): return "oracle unavailable: \(s)"
            case .failed(let s): return "oracle failed: \(s)"
            }
        }
    }

    /// Package root, derived from this file's path (…/Tests/TandemMessagesTests/OracleRunner.swift).
    static let packageRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // TandemMessagesTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // package root

    static let jarPath: String = {
        if let env = ProcessInfo.processInfo.environment["PUMPX2_ORACLE_JAR"] { return env }
        return
            packageRoot
            .appendingPathComponent("vendor/pumpx2-oracle/cliparser/build/libs/cliparser.jar")
            .path
    }()

    static let javaPath: String = {
        if let env = ProcessInfo.processInfo.environment["PUMPX2_JAVA"] { return env }
        let brew = "/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home/bin/java"
        if FileManager.default.isExecutableFile(atPath: brew) { return brew }
        return "/usr/bin/java"
    }()

    /// `cliparser.jar`'s `Main.class` is class-file major 58 (Java 14); a JDK below 21 cannot
    /// load it. Below this requirement `isAvailable` must be false, not merely "jar exists and
    /// java is executable" — a present-but-wrong JVM must read as UNAVAILABLE, never as a
    /// byte-parity mismatch.
    static let minimumJavaMajor = 21

    /// Parses the major version out of `java -version` text (written to stderr). Pure, so it can
    /// be unit-tested with literal inputs independent of any real JVM (anti-vacuity).
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

    /// The version-requirement boundary, named so it can be asserted non-vacuously: a
    /// wrong JVM must be detectable, not just "some JVM found".
    static func isSupportedJavaMajor(_ major: Int) -> Bool {
        major >= minimumJavaMajor
    }

    /// Memoized (spawned at most once per process, matching `javaPath`'s memoization) resolution
    /// of `javaPath -version`. Any spawn or parse failure resolves to `nil` — fail closed.
    static let resolvedJavaMajorVersion: Int? = {
        guard FileManager.default.isExecutableFile(atPath: javaPath) else { return nil }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: javaPath)
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

    /// True when the JDK, the built oracle JAR, AND a JVM major version >= `minimumJavaMajor` are
    /// all present. Used to gate oracle tests so a checkout without a built oracle (or with only
    /// a too-old JVM) still runs the rest of the suite instead of misreporting byte-parity
    /// failures.
    static var isAvailable: Bool {
        guard FileManager.default.fileExists(atPath: jarPath),
            FileManager.default.isExecutableFile(atPath: javaPath),
            let major = resolvedJavaMajorVersion
        else { return false }
        return isSupportedJavaMajor(major)
    }

    /// A fixed legacy pairing code + pump-time used for signed-message parity tests. The HMAC
    /// key for a legacy pairing is the code's ASCII bytes (see PumpStateSupplier), so the same
    /// values fed to Swift Packetize and to the oracle env produce identical signed packets.
    static let testPairingCode = "6VeDeRAL5DCigGw2"  // 16 chars, from an upstream example
    static let testPumpTimeSinceReset: UInt32 = 461_589_180

    /// Runs `cliparser encode <txId> <messageName> <jsonParams>` and returns the parsed result.
    /// For signed messages, pass `pairingCode`/`pumpTimeSinceReset` so the oracle computes the
    /// HMAC with the same key/time as Swift.
    static func encode(
        txId: UInt8,
        messageName: String,
        json: String = "{}",
        pairingCode: String? = nil,
        pumpTimeSinceReset: UInt32? = nil
    ) throws -> EncodeResult {
        guard isAvailable else {
            throw OracleError.unavailable(
                "jar=\(jarPath) java=\(javaPath) resolvedJavaMajor=\(resolvedJavaMajorVersion.map(String.init) ?? "unknown") (need >= \(minimumJavaMajor))"
            )
        }
        var env: [String: String] = [:]
        if let pairingCode { env["PUMP_PAIRING_CODE"] = pairingCode }
        if let pumpTimeSinceReset { env["PUMP_TIME_SINCE_RESET"] = String(pumpTimeSinceReset) }
        let (out, err) = try OracleServer.shared.call(["encode", String(txId), messageName, json], env: env)
        // The oracle prints the JSON result on stdout; diagnostics go to stderr.
        guard let line = out.split(separator: "\n").last(where: { $0.contains("\"packets\"") }),
            let data = line.data(using: .utf8)
        else {
            throw OracleError.failed("no JSON in output: \(out)\n\(err)")
        }
        return try JSONDecoder().decode(EncodeResult.self, from: data)
    }

    /// Convenience: just the packet hex strings.
    static func encodePackets(txId: UInt8, messageName: String, json: String = "{}") throws -> [String] {
        try encode(txId: txId, messageName: messageName, json: json).packets
    }

    struct HistoryLogParse {
        let typeId: Int
        let className: String
        let description: String
    }

    /// Runs `cliparser historylog <hex>` — decodes a 26-byte history-log record and returns the
    /// upstream typeId + class short-name (+ toString). History logs are decode-only, so this gives
    /// byte-exact **decode** parity: feed the same bytes to Swift `HistoryLogParser` and compare.
    static func parseHistoryLog(hex: String) throws -> HistoryLogParse {
        guard isAvailable else {
            throw OracleError.unavailable(
                "jar=\(jarPath) java=\(javaPath) resolvedJavaMajor=\(resolvedJavaMajorVersion.map(String.init) ?? "unknown") (need >= \(minimumJavaMajor))"
            )
        }
        let (out, err) = try OracleServer.shared.call(["historylog", hex])
        guard let line = out.split(separator: "\n").last(where: { $0.contains("\t") }) else {
            throw OracleError.failed("no tab-delimited output: \(out)\n\(err)")
        }
        let parts = line.components(separatedBy: "\t")
        guard parts.count >= 2, let tid = Int(parts[0]) else {
            throw OracleError.failed("unparseable historylog line: \(line)")
        }
        let shortName = parts[1].components(separatedBy: ".").last ?? parts[1]
        return HistoryLogParse(
            typeId: tid, className: shortName,
            description: parts.count >= 4 ? parts[3] : "")
    }
}

/// One `cliparser serve` process shared by every oracle test. `serve` reads one JSON request per
/// line, `{"id", "args", "env"}`, runs `args` as the one-shot command would, and answers with one
/// JSON line, `{"id", "ok", "stdout", "stderr", "error"}`. Each request's environment comes only from
/// its `env`, so tests can't leak a pairing code into each other.
///
/// `@unchecked Sendable`: Swift Testing runs suites in parallel, and every use of the pipes and the
/// process goes through `lock`, one request at a time (the server itself answers in order).
final class OracleServer: @unchecked Sendable {
    static let shared = OracleServer()

    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffered = Data()
    private var nextId = 0

    /// Runs one command and returns its stdout and stderr. Throws `OracleError.failed` when the
    /// command fails (the one-shot command's non-zero exit) or the server dies.
    func call(_ args: [String], env: [String: String] = [:]) throws -> (out: String, err: String) {
        lock.lock()
        defer { lock.unlock() }
        if process?.isRunning != true { try start() }
        nextId += 1
        let request: [String: Any] = ["id": nextId, "args": args, "env": env]
        var line = try JSONSerialization.data(withJSONObject: request)
        line.append(0x0A)
        do {
            try input?.write(contentsOf: line)
            let reply = try readLine()
            guard let json = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
                (json["id"] as? Int) == nextId
            else {
                // Out of step with the server: every later reply would answer an earlier request.
                stop()
                throw OracleRunner.OracleError.failed(
                    "unexpected serve reply: \(String(decoding: reply, as: UTF8.self))")
            }
            let out = json["stdout"] as? String ?? ""
            let err = json["stderr"] as? String ?? ""
            guard json["ok"] as? Bool == true else {
                throw OracleRunner.OracleError.failed(
                    "\(args.first ?? ""): \(json["error"] ?? "unknown error")\n\(err)")
            }
            return (out, err)
        } catch let error as OracleRunner.OracleError {
            throw error
        } catch {
            stop()
            throw OracleRunner.OracleError.failed("serve I/O: \(error)")
        }
    }

    private func start() throws {
        // A write to a server that has just died must throw, not kill the test process.
        signal(SIGPIPE, SIG_IGN)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: OracleRunner.javaPath)
        proc.arguments = ["-jar", OracleRunner.jarPath, "serve"]
        let inPipe = Pipe(), outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        // The library's own logging goes to the server's real stderr; nothing reads it.
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        process = proc
        input = inPipe.fileHandleForWriting
        output = outPipe.fileHandleForReading
        buffered = Data()
    }

    private func stop() {
        process?.terminate()
        process = nil
        input = nil
        output = nil
        buffered = Data()
    }

    private func readLine() throws -> Data {
        while true {
            if let newline = buffered.firstIndex(of: 0x0A) {
                let line = buffered[buffered.startIndex..<newline]
                buffered = Data(buffered[buffered.index(after: newline)...])
                return Data(line)
            }
            guard let chunk = output?.availableData, !chunk.isEmpty else {
                stop()
                throw OracleRunner.OracleError.failed("cliparser serve exited")
            }
            buffered.append(chunk)
        }
    }
}
