import Foundation

/// The BLE GATT characteristics the pump exposes for messaging.
/// Port of `com.jwoglom.pumpx2.pump.messages.bluetooth.Characteristic` +
/// the UUID constants from `CharacteristicUUID`.
public enum Characteristic: String, CaseIterable, Sendable {
    case currentStatus   = "7B83FFF6-9F77-4E5C-8064-AAE2C24838B9"
    case qualifyingEvents = "7B83FFF7-9F77-4E5C-8064-AAE2C24838B9"
    case historyLog      = "7B83FFF8-9F77-4E5C-8064-AAE2C24838B9"
    case authorization   = "7B83FFF9-9F77-4E5C-8064-AAE2C24838B9"
    case control         = "7B83FFFC-9F77-4E5C-8064-AAE2C24838B9"
    case controlStream   = "7B83FFFD-9F77-4E5C-8064-AAE2C24838B9"

    /// Uppercased canonical UUID string, matching upstream `getUuid().toString()`.
    public var uuidString: String { rawValue }

    public var uuid: UUID { UUID(uuidString: rawValue)! }

    /// Human-readable name used in oracle/debug output (subset of `CharacteristicUUID.which`).
    public var name: String {
        switch self {
        case .currentStatus:    return "CURRENT_STATUS"
        case .qualifyingEvents: return "QUALIFYING_EVENTS"
        case .historyLog:       return "HISTORY_LOG"
        case .authorization:    return "AUTHORIZATION"
        case .control:          return "CONTROL"
        case .controlStream:    return "CONTROL_STREAM"
        }
    }

    public static func of(uuid: UUID) -> Characteristic? {
        allCases.first { $0.uuid == uuid }
    }
}
