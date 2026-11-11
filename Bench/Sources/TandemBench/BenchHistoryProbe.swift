import Foundation

/// What a HistoryLogRequest(startLog, count) brought back, and which reading of `startLog` it fits.
///
/// pumpX2's sample app reads `startLog` as the low end of the page (records start...start+count-1).
/// pumpX2's own 2023 capture of a t:slim at API 2.5 shows the other reading: every request carried the
/// newest sequence number, and the pump streamed start down to start-count+1, newest first. Both
/// windows hold `start`, so a page of one record can't tell them apart.
public struct BenchHistoryProbe: Sendable, Equatable {
    public enum Anchoring: String, Sendable, Equatable {
        /// start down to start-count+1.
        case top
        /// start up to start+count-1.
        case low
        /// count is 1: both readings give the same record.
        case ambiguous
        /// Nothing came back.
        case empty
        /// Neither window exactly.
        case neither
    }

    public let start: UInt32
    public let count: Int
    /// Sequence numbers in the order the frames brought them.
    public let received: [UInt32]

    public init(start: UInt32, count: Int, received: [UInt32]) {
        self.start = start
        self.count = count
        self.received = received
    }

    public var topWindow: ClosedRange<UInt32> {
        let low = start >= UInt32(max(count - 1, 0)) ? start - UInt32(max(count - 1, 0)) : 0
        return low...start
    }

    public var lowWindow: ClosedRange<UInt32> {
        start...(start &+ UInt32(max(count - 1, 0)))
    }

    public var anchoring: Anchoring {
        if received.isEmpty { return .empty }
        let got = Set(received)
        if count == 1, got == [start] { return .ambiguous }
        if got == Set(topWindow) { return .top }
        if got == Set(lowWindow) { return .low }
        return .neither
    }

    /// True when the records came newest first.
    public var newestFirst: Bool {
        received.count > 1 && zip(received, received.dropFirst()).allSatisfy { $0 > $1 }
    }

    public var duplicates: Int { received.count - Set(received).count }

    public var summary: String {
        let range = received.isEmpty ? "none" : "\(received.min()!)...\(received.max()!)"
        var s =
            "asked start=\(start) count=\(count): got \(received.count) record(s), SNs \(range), "
            + "order \(newestFirst ? "newest first" : (received.count > 1 ? "not newest first" : "-")), "
            + "fits: \(anchoring.rawValue)"
        if duplicates > 0 { s += ", \(duplicates) duplicate(s)" }
        return s
    }

    /// The page-size question: a full page, or one cut short (and, for 251-255, cut at 250).
    public static func capVerdict(asked: Int, got: Int) -> String {
        if got == asked { return "full page: asked \(asked), got \(got)" }
        if asked > 250, got == 250 { return "capped at 250: asked \(asked), got 250" }
        return "short page: asked \(asked), got \(got)"
    }
}

/// Times between the stream frames of one page, for the page-timer question.
public struct BenchFrameTiming: Sendable, Equatable {
    public let arrivals: [Double]

    public init(arrivals: [Double]) { self.arrivals = arrivals }

    public var gaps: [Double] { zip(arrivals.dropFirst(), arrivals).map { $0 - $1 } }

    public var summary: String {
        guard let first = arrivals.first, let last = arrivals.last else { return "no frames" }
        let g = gaps.sorted()
        guard !g.isEmpty else { return "1 frame" }
        let median = g[g.count / 2]
        return String(
            format: "%d frames over %.2f s; gap min %.3f median %.3f max %.3f s", arrivals.count, last - first,
            g.first!, median, g.last!)
    }
}
