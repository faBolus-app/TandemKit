import Foundation

/// The reconnect timeline for the range-edge run: every drop, how long the connection had lasted, and
/// how long it took to be ready again, with the connect attempts in between.
public struct BenchReconnectLog: Sendable, Equatable {
    public struct Drop: Sendable, Equatable {
        public let at: Double
        public let upFor: Double
        public let held: Bool
        public let reason: String
        /// When the link was next ready; nil until then.
        public var readyAgainAt: Double?
        /// Connect attempts between the drop and the next ready.
        public var attempts: Int
        public var gap: Double? { readyAgainAt.map { $0 - at } }
    }

    public private(set) var drops: [Drop] = []
    public private(set) var readies = 0

    public init() {}

    public mutating func dropped(at time: Double, upFor: Double, held: Bool, reason: String) {
        drops.append(Drop(at: time, upFor: upFor, held: held, reason: reason, readyAgainAt: nil, attempts: 0))
    }

    public mutating func connecting(at time: Double) {
        guard let last = drops.last, last.readyAgainAt == nil else { return }
        drops[drops.count - 1].attempts += 1
    }

    /// Returns the line to log when this ready ends a gap.
    public mutating func ready(at time: Double) -> String? {
        readies += 1
        guard let last = drops.last, last.readyAgainAt == nil else { return nil }
        drops[drops.count - 1].readyAgainAt = time
        let d = drops[drops.count - 1]
        return String(
            format: "reconnect: ready %.1f s after the drop, %d connect attempt(s); the dropped connection had "
                + "lasted %.1f s (%@)", d.gap ?? 0, d.attempts, d.upFor, d.held ? "held" : "flap")
    }

    public var summary: [String] {
        guard !drops.isEmpty else { return ["reconnects: no drops"] }
        let gaps = drops.compactMap(\.gap).sorted()
        let flaps = drops.filter { !$0.held }.count
        var out = ["reconnects: \(drops.count) drop(s), \(flaps) flap(s) before the hold, \(drops.count - flaps) after"]
        if !gaps.isEmpty {
            out.append(
                String(
                    format: "drop to ready: min %.1f median %.1f max %.1f s over %d reconnect(s)", gaps.first!,
                    gaps[gaps.count / 2], gaps.last!, gaps.count))
        }
        let open = drops.filter { $0.readyAgainAt == nil }.count
        if open > 0 { out.append("\(open) drop(s) not reconnected by the end of the run") }
        return out
    }
}

/// Pump battery over a run, for the held-link question. The pump reports whole percent, so a rate
/// needs hours of samples; with fewer than two distinct times there is no rate.
public struct BenchBatteryTrend: Sendable, Equatable {
    public private(set) var samples: [(time: Double, percent: Int)] = []

    public init() {}

    public static func == (a: Self, b: Self) -> Bool {
        a.samples.map(\.time) == b.samples.map(\.time) && a.samples.map(\.percent) == b.samples.map(\.percent)
    }

    public mutating func add(_ percent: Int, at time: Double) { samples.append((time, percent)) }

    /// Least-squares slope in percent per hour (negative while draining).
    public var percentPerHour: Double? {
        guard samples.count >= 2 else { return nil }
        let n = Double(samples.count)
        let xs = samples.map { $0.time / 3600 }
        let ys = samples.map { Double($0.percent) }
        let mx = xs.reduce(0, +) / n
        let my = ys.reduce(0, +) / n
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        return sxy / sxx
    }

    public var summary: String {
        guard let first = samples.first, let last = samples.last else { return "battery: no reading" }
        let hours = (last.time - first.time) / 3600
        let rate = percentPerHour.map { String(format: "%+.2f %%/h", $0) } ?? "no rate yet"
        return String(
            format: "battery: %d%% -> %d%% over %.2f h (%d readings), fit %@", first.percent, last.percent, hours,
            samples.count, rate)
    }
}

/// Requests written per hour, the other half of the battery question.
public struct BenchRequestRate: Sendable, Equatable {
    public private(set) var writes = 0
    public let since: Double

    public init(since: Double) { self.since = since }

    public mutating func wrote() { writes += 1 }

    public func perHour(at now: Double) -> Double? {
        let span = now - since
        return span > 0 ? Double(writes) / span * 3600 : nil
    }
}
