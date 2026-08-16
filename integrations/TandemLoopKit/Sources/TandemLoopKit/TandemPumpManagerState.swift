import Foundation
import LoopKit

/// Persisted driver state. `RawRepresentable` over LoopKit's `[String: Any]` state dictionary, the
/// same shape OmniBLE uses. Versioned so a future field change can migrate.
public struct TandemPumpManagerState: RawRepresentable, Equatable {
    public typealias RawValue = [String: Any]
    public static let version = 1

    public var timeZone: TimeZone
    /// Per-command HMAC signing key from pairing. Its presence == onboarded.
    /// NOTE: a production host should Keychain-back this; it is persisted in rawState here for the
    /// first cut, matching how OmniBLE persists its pod secrets in state.
    public var authKey: [UInt8]?
    public var pumpPeripheralID: UUID?
    public var pumpSerial: String?
    /// The in-flight / not-yet-authoritatively-final dose, if any.
    public var pendingDose: TandemUnfinalizedDose?
    public var lastReconciliation: Date?
    /// True when a delivery write was issued but its outcome was never authoritatively read (lost
    /// reply / disconnect). Durable across relaunch (together with `pendingDose`, which carries the
    /// bolus id) so the indeterminate delivery is reconciled against pump history and never silently
    /// dropped. A NORMAL in-flight bolus is NOT uncertain — this stays false while it proceeds.
    public var deliveryUncertain: Bool
    public var suspended: Bool
    public var batteryPercent: Int?
    public var reservoirUnits: Double?

    public var isOnboarded: Bool { authKey != nil }

    public init(timeZone: TimeZone = .current,
                authKey: [UInt8]? = nil,
                pumpPeripheralID: UUID? = nil,
                pumpSerial: String? = nil,
                pendingDose: TandemUnfinalizedDose? = nil,
                lastReconciliation: Date? = nil,
                deliveryUncertain: Bool = false,
                suspended: Bool = false,
                batteryPercent: Int? = nil,
                reservoirUnits: Double? = nil) {
        self.timeZone = timeZone
        self.authKey = authKey
        self.pumpPeripheralID = pumpPeripheralID
        self.pumpSerial = pumpSerial
        self.pendingDose = pendingDose
        self.lastReconciliation = lastReconciliation
        self.deliveryUncertain = deliveryUncertain
        self.suspended = suspended
        self.batteryPercent = batteryPercent
        self.reservoirUnits = reservoirUnits
    }

    public init?(rawValue: RawValue) {
        // Version guard: an unknown/newer version is rejected (nil) rather than mis-decoded.
        guard let version = rawValue["version"] as? Int, version <= Self.version else { return nil }

        let seconds = (rawValue["timeZone"] as? Int) ?? TimeZone.current.secondsFromGMT()
        self.timeZone = TimeZone(secondsFromGMT: seconds) ?? .current
        if let bytes = rawValue["authKey"] as? [Int] { self.authKey = bytes.map { UInt8(truncatingIfNeeded: $0) } }
        if let s = rawValue["pumpPeripheralID"] as? String { self.pumpPeripheralID = UUID(uuidString: s) }
        self.pumpSerial = rawValue["pumpSerial"] as? String
        if let b64 = rawValue["pendingDose"] as? String, let data = Data(base64Encoded: b64) {
            self.pendingDose = try? JSONDecoder().decode(TandemUnfinalizedDose.self, from: data)
        }
        if let ts = rawValue["lastReconciliation"] as? Double { self.lastReconciliation = Date(timeIntervalSince1970: ts) }
        self.deliveryUncertain = (rawValue["deliveryUncertain"] as? Bool) ?? false
        self.suspended = (rawValue["suspended"] as? Bool) ?? false
        self.batteryPercent = rawValue["batteryPercent"] as? Int
        self.reservoirUnits = rawValue["reservoirUnits"] as? Double
    }

    public var rawValue: RawValue {
        var raw: RawValue = ["version": Self.version, "suspended": suspended, "deliveryUncertain": deliveryUncertain]
        raw["timeZone"] = timeZone.secondsFromGMT()
        if let authKey { raw["authKey"] = authKey.map { Int($0) } }
        if let pumpPeripheralID { raw["pumpPeripheralID"] = pumpPeripheralID.uuidString }
        if let pumpSerial { raw["pumpSerial"] = pumpSerial }
        if let pendingDose, let data = try? JSONEncoder().encode(pendingDose) {
            raw["pendingDose"] = data.base64EncodedString()
        }
        if let lastReconciliation { raw["lastReconciliation"] = lastReconciliation.timeIntervalSince1970 }
        if let batteryPercent { raw["batteryPercent"] = batteryPercent }
        if let reservoirUnits { raw["reservoirUnits"] = reservoirUnits }
        return raw
    }

    // RawValue is [String: Any] (not Equatable); compare the decoded fields instead.
    public static func == (lhs: TandemPumpManagerState, rhs: TandemPumpManagerState) -> Bool {
        lhs.timeZone == rhs.timeZone
            && lhs.authKey == rhs.authKey
            && lhs.pumpPeripheralID == rhs.pumpPeripheralID
            && lhs.pumpSerial == rhs.pumpSerial
            && lhs.pendingDose == rhs.pendingDose
            && lhs.lastReconciliation == rhs.lastReconciliation
            && lhs.deliveryUncertain == rhs.deliveryUncertain
            && lhs.suspended == rhs.suspended
            && lhs.batteryPercent == rhs.batteryPercent
            && lhs.reservoirUnits == rhs.reservoirUnits
    }
}
