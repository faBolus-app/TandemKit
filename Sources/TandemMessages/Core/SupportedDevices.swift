import Foundation

/// The pump product family a message is legal to send to (workstream B / D-08). Mirrors upstream
/// `com.jwoglom.pumpx2.pump.messages.models.KnownDeviceModel` — the enum the upstream `@MessageProps`
/// `supportedDevices=` tags resolve to. Kept minimal to the models the port actually classifies;
/// add cases here as upstream adds device models.
public enum PumpModel: Sendable, Equatable, CaseIterable {
    /// t:slim X2.
    case tslim
    /// Tandem Mobi.
    case mobi
}

/// A negotiated pump API version (major.minor), the Swift mirror of upstream
/// `com.jwoglom.pumpx2.pump.messages.models.ApiVersion`. `Comparable` so a message's `minApi`
/// floor can be compared against the connected pump's negotiated version. The named constants
/// mirror upstream `KnownApiVersion` — the exact values the `@MessageProps` `minApi=` tags carry.
public struct ApiVersion: Sendable, Comparable, Equatable, Hashable {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static func < (a: ApiVersion, b: ApiVersion) -> Bool {
        (a.major, a.minor) < (b.major, b.minor)
    }
}

public extension ApiVersion {
    /// v2.1 — earliest known API (software v7.1/v7.4). Upstream `API_V2_1`; also the upstream default.
    static let v2_1 = ApiVersion(major: 2, minor: 1)
    /// v2.5 — software v7.6, adds remote bolus. Upstream `API_V2_5`.
    static let v2_5 = ApiVersion(major: 2, minor: 5)
    /// v3.0 stub. Upstream `API_V3`.
    static let v3 = ApiVersion(major: 3, minor: 0)
    /// v3.2 — software v7.7, 6-char numeric pairing PIN. Upstream `API_V3_2`.
    static let v3_2 = ApiVersion(major: 3, minor: 2)
    /// v3.4 — software v7.8 for the t:slim X2. Upstream `API_V3_4`.
    static let v3_4 = ApiVersion(major: 3, minor: 4)
    /// Mobi initial release (software v7.6.0.3). Upstream `MOBI_API_V3_5`.
    static let mobi_v3_5 = ApiVersion(major: 3, minor: 5)
    /// Mobi software v7.7.0.1. Upstream `MOBI_API_V3_6`.
    static let mobi_v3_6 = ApiVersion(major: 3, minor: 6)
    /// Mobi software v7.9.0.1 (Control-IQ Plus). Upstream `MOBI_API_V3_8`.
    static let mobi_v3_8 = ApiVersion(major: 3, minor: 8)
    /// Sentinel for messages known to the app but unparseable by any known firmware. Upstream
    /// `API_FUTURE` (99,99) — a `minApi: .future` floor is above every known pump, so such a
    /// message is gated for any KNOWN target (and, per fail-open, still sent to an unknown target).
    static let future = ApiVersion(major: 99, minor: 99)
}
