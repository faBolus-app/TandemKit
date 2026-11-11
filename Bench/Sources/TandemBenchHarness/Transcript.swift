import Foundation

/// Everything a run prints, also written to a transcript file to hand back after the run.
///
/// Lines go to stdout and the file; packet-level detail goes only to the file unless `PUMP_PACKETS=1`.
/// The pairing code is never written, and the transport redacts authorization frames before they reach
/// here (unless `PUMP_RECORD_PAIRING=1`).
final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle?
    let url: URL?
    let echoDetail: Bool
    private let started = Date()
    private let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(command: String, environment: [String: String]) {
        echoDetail = environment["PUMP_PACKETS"] == "1"
        let dir: URL
        if let path = environment["PUMP_TRANSCRIPT_DIR"], !path.isEmpty {
            dir = URL(fileURLWithPath: path)
        } else {
            dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tandemkit-bench/transcripts")
        }
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        // The process id keeps two runs started in the same second (P1 and P2 side by side) apart.
        let name = "\(command)-\(f.string(from: Date()))-\(ProcessInfo.processInfo.processIdentifier).txt"
        let url = dir.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
            self.url = url
        } catch {
            print("couldn't open a transcript in \(dir.path): \(error); continuing without one")
            handle = nil
            self.url = nil
        }
    }

    /// Called under the lock: one formatter, used by one thread at a time.
    private func stamp() -> String {
        let now = Date()
        return clock.string(from: now) + String(format: " +%.1fs", now.timeIntervalSince(started))
    }

    /// A line for the person at the bench: stdout and the file.
    func line(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let out = "[\(stamp())] \(text)"
        print(out)
        handle?.write(Data((out + "\n").utf8))
    }

    /// Packet-level detail: the file, and stdout only with `PUMP_PACKETS=1`.
    func detail(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        let out = "[\(stamp())]   \(text)"
        if echoDetail { print(out) }
        handle?.write(Data((out + "\n").utf8))
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle?.synchronize()
        try? handle?.close()
    }
}
