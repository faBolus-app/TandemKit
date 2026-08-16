import Foundation

/// Pump GATT service UUIDs. Port of `ServiceUUID` from the upstream Android transport.
public enum ServiceUUID {
    /// Tandem TIP service (the primary "pump" service used for messaging).
    public static let pumpService = UUID(uuidString: "0000FDFB-0000-1000-8000-00805F9B34FB")!
    /// Tandem TDU service (used by the Mobi app alongside TIP).
    public static let tduService = UUID(uuidString: "0000FDFA-0000-1000-8000-00805F9B34FB")!
    public static let disService = UUID(uuidString: "0000180A-0000-1000-8000-00805F9B34FB")!
    public static let genericAccessService = UUID(uuidString: "00001800-0000-1000-8000-00805F9B34FB")!
    public static let genericAttributeService = UUID(uuidString: "00001801-0000-1000-8000-00805F9B34FB")!

    /// MTU iOS/the Tandem app negotiates (upstream requests 185).
    public static let preferredMTU = 185

    /// Characteristics we subscribe to notifications on (subset the pump exposes).
    public static let notificationCharacteristics: [Characteristic] = [
        .currentStatus, .qualifyingEvents, .historyLog, .authorization, .control, .controlStream,
    ]
}
