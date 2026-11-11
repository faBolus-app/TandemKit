import Foundation

/// Qualifying-event (notice) bits by position, with TandemKit's names (`QualifyingEvent`, a port of
/// pumpX2's), for the `notices` and `monitor` logs.
public enum BenchNoticeBits {
    public static let names: [Int: String] = [
        0: "alert", 1: "alarm", 2: "reminder", 3: "malfunction", 4: "cgmAlert", 5: "homeScreenChange",
        6: "pumpSuspend", 7: "pumpResume", 8: "timeChange", 9: "basalChange", 10: "bolusChange", 11: "iobChange",
        12: "extendedBolusChange", 13: "profileChange", 14: "bg", 15: "cgmChange", 16: "battery", 17: "basalIQ",
        18: "remainingInsulin", 19: "pumpCommunicationsSuspended", 20: "activeProfileSegmentChange",
        21: "basalIQStatus", 22: "controlIQInfo", 23: "controlIQSleep", 24: "globalPumpSettings", 25: "snoozeStatus",
        26: "pumpingStatus", 27: "pumpReset", 28: "heartbeat", 31: "bolusPermissionRevoked"
    ]

    public static let commsSuspendedBit = 19

    public static func positions(_ raw: UInt32) -> [Int] {
        (0..<32).filter { raw & (UInt32(1) << UInt32($0)) != 0 }
    }

    /// `0x00080400 [10 bolusChange, 19 pumpCommunicationsSuspended]`.
    public static func describe(_ raw: UInt32) -> String {
        let named = positions(raw).map { "\($0) \(names[$0] ?? "unnamed")" }.joined(separator: ", ")
        return String(format: "0x%08x", raw) + " [\(named)]"
    }
}

/// Episodes of notice bit 19 (comms suspended). An episode opens on the first notice with the bit and
/// closes on the next notice without it; how long the pump means it to last isn't known, so both the
/// span between its own notices and the time to the clearing notice are kept.
public struct BenchCommsSuspendedLog: Sendable, Equatable {
    public struct Episode: Sendable, Equatable {
        public var start: Double
        public var lastSeen: Double
        public var notices: Int
        /// The other bits that came with bit 19, over the episode.
        public var otherBits: Set<Int>
        /// When a notice without bit 19 arrived; nil while open.
        public var clearedAt: Double?
    }

    public private(set) var episodes: [Episode] = []
    public private(set) var notices = 0

    public init() {}

    public var open: Episode? { episodes.last.flatMap { $0.clearedAt == nil ? $0 : nil } }

    /// Records one notice; returns a line to log when bit 19 starts, repeats or clears.
    public mutating func record(_ raw: UInt32, at time: Double) -> String? {
        notices += 1
        let bit = BenchNoticeBits.commsSuspendedBit
        let has = raw & (UInt32(1) << UInt32(bit)) != 0
        let others = Set(BenchNoticeBits.positions(raw)).subtracting([bit])
        if has {
            if var current = open {
                current.lastSeen = time
                current.notices += 1
                current.otherBits.formUnion(others)
                episodes[episodes.count - 1] = current
                return String(
                    format: "bit 19 again (%d in this episode, %.1f s since it started)", current.notices,
                    time - current.start)
            }
            episodes.append(Episode(start: time, lastSeen: time, notices: 1, otherBits: others, clearedAt: nil))
            return "bit 19 SET (episode \(episodes.count))"
        }
        if var current = open {
            current.clearedAt = time
            episodes[episodes.count - 1] = current
            return String(
                format: "bit 19 cleared by a notice without it: %.1f s after it started, %d notice(s) with it",
                time - current.start, current.notices)
        }
        return nil
    }

    public var summary: [String] {
        if episodes.isEmpty { return ["bit 19: never seen in \(notices) notice(s)"] }
        return episodes.enumerated().map { i, e in
            let span = String(format: "%.1f", e.lastSeen - e.start)
            let cleared = e.clearedAt.map { String(format: "%.1f s after start", $0 - e.start) } ?? "not cleared"
            let with = e.otherBits.sorted().map { BenchNoticeBits.names[$0] ?? "bit \($0)" }.joined(separator: ", ")
            return "bit 19 episode \(i + 1): \(e.notices) notice(s) over \(span) s, cleared \(cleared); "
                + "with: \(with.isEmpty ? "nothing else" : with)"
        }
    }
}
