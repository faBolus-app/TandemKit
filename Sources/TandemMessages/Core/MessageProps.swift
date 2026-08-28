import Foundation

/// Operation-risk class for a message. Lets a caller authorize on the *consequence* of a message,
/// not just on "does it dispense insulin": `PumpBLEClient.WritePolicy.maxRisk` maps each link policy
/// to the highest class it authorizes, and a message is permitted only at or below that ceiling.
/// Ordered least→most dangerous.
public enum OperationRisk: Int, Sendable, Comparable, CaseIterable {
    /// Reads, pairing, unsigned non-control traffic. No pump state change.
    case read = 0
    /// Signed control with no therapy effect: dismiss a notification, play the find-my-pump sound,
    /// record carb/BG metadata (does not itself dose).
    case benign = 1
    /// Therapy-significant configuration that does not itself dispense: max bolus/basal limits,
    /// Control-IQ settings, time/date, CGM session/alerts, reminders, profile (IDP) edits.
    case settings = 2
    /// High-consequence, non-dispensing commands: factory reset, disconnect, shelf mode.
    case destructive = 3
    /// Commits/changes active insulin delivery: initiate bolus, suspend/resume, temp rate, modes,
    /// cartridge/cannula fill. Mirrors `modifiesInsulinDelivery`.
    case delivery = 4

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Per-message metadata. In upstream this is the `@MessageProps` annotation read via
/// reflection; in Swift each message type supplies it as a static value.
///
/// `responseOpCode` / `requestOpCode` wire a request↔response pair together. They're
/// optional here and get populated as the message catalog is ported (the opcode registry
/// is built incrementally, unlike upstream's single `Messages` enum).
public struct MessageProps: Sendable {
    public let opCode: UInt8
    public let size: Int
    public let variableSize: Bool
    public let stream: Bool
    public let signed: Bool
    public let type: MessageType
    public let characteristic: Characteristic
    public let modifiesInsulinDelivery: Bool
    public let responseOpCode: UInt8?
    public let requestOpCode: UInt8?
    /// Explicit risk override; `nil` derives a fail-safe default (see `operationRisk`).
    private let riskOverride: OperationRisk?

    /// Device/API send-gating metadata (workstream B / D-08), the Swift mirror of upstream's
    /// `@MessageProps` `supportedDevices=` / `minApi=` tags. Both are **additive-optional** and default
    /// to `nil` = *unrestricted*, so every existing `MessageProps(...)` call site stays source-compatible
    /// and every currently-sent message stays sendable byte-for-byte — the change is behavior-preserving
    /// for supported combos. The values are consumed only by `isSupported(onModel:apiVersion:)`.

    /// The pump families this message is legal to send to; `nil` = every device (unrestricted).
    public let supportedDevices: [PumpModel]?
    /// The minimum negotiated API version this message requires; `nil` = no floor (unrestricted).
    public let minApi: ApiVersion?

    public init(
        opCode: UInt8,
        size: Int = 0,
        variableSize: Bool = false,
        stream: Bool = false,
        signed: Bool = false,
        type: MessageType,
        characteristic: Characteristic = .currentStatus,
        modifiesInsulinDelivery: Bool = false,
        risk: OperationRisk? = nil,
        responseOpCode: UInt8? = nil,
        requestOpCode: UInt8? = nil,
        supportedDevices: [PumpModel]? = nil,
        minApi: ApiVersion? = nil
    ) {
        self.opCode = opCode
        self.size = size
        self.variableSize = variableSize
        self.stream = stream
        self.signed = signed
        self.type = type
        self.characteristic = characteristic
        self.modifiesInsulinDelivery = modifiesInsulinDelivery
        self.riskOverride = risk
        self.responseOpCode = responseOpCode
        self.requestOpCode = requestOpCode
        self.supportedDevices = supportedDevices
        self.minApi = minApi
    }

    /// Pure device/API compatibility predicate (workstream B / D-08). Decides whether this message is
    /// legal to send to a target pump identified by `model` + `apiVersion`. **Fail-open by design:**
    ///
    /// - Returns `true` when the message declares no restriction (`supportedDevices == nil` and
    ///   `minApi == nil`) — an un-annotated message stays universally sendable.
    /// VA-06: each declared dimension (device family, API floor) is evaluated **independently**.
    /// - Returns `false` when the message DECLARES a restriction AND a KNOWN target violates THAT
    ///   dimension: a known `model` not in `supportedDevices`, OR a known `apiVersion` below `minApi` —
    ///   even if the OTHER dimension's context is still unknown.
    /// - An UNKNOWN dimension fails OPEN for that dimension only (preserves send-then-firmware-NACK; and
    ///   gating on an unknown API would deadlock bootstrap — the API is negotiated via op33 only AFTER
    ///   JPAKE auth and several pre-identity reads that themselves carry a `minApi`).
    /// - A fully-unrestricted message, or a fully-unknown target for a restricted message, stays supported.
    ///
    /// This is deliberately transport-free so the send gate's decision is deterministically testable and
    /// cannot be masked by connection state (mirrors `PumpBLEClient.authorizationError`).
    ///
    /// NOTE (pre-VA-06 defect): the old `guard let model, let apiVersion else { return true }` required
    /// BOTH dimensions known before gating EITHER, so a known t:slim could send a `[.mobi]`-only message
    /// (or a known too-old API a `minApi` message) whenever the other dimension was not yet known.
    public func isSupported(onModel model: PumpModel?, apiVersion: ApiVersion?) -> Bool {
        // Unrestricted message ⇒ always supported (behavior-preserving for every un-annotated message).
        if supportedDevices == nil && minApi == nil { return true }
        // Device restriction violated: a KNOWN model is not in the declared device set (independent of API).
        if let supportedDevices, let model, !supportedDevices.contains(model) { return false }
        // API floor violated: a KNOWN negotiated version is below the declared minimum (independent of model).
        if let minApi, let apiVersion, apiVersion < minApi { return false }
        return true
    }

    /// The operation-risk class. Uses the explicit `risk:` when a message declares one;
    /// otherwise derives a **fail-safe** default: anything that modifies delivery is `.delivery`; any
    /// other control-characteristic or signed message is treated as `.settings` (therapy-significant)
    /// until it proves itself benign by declaring `risk: .benign`; everything else is `.read`. Using
    /// `signed || control` (not `&&`) keeps `.readOnly` (max `.read`) blocking exactly what it did
    /// before — every control/signed/delivery message — while a newly-ported control message defaults
    /// to the more-restrictive tier, never to benign.
    public var operationRisk: OperationRisk {
        if let riskOverride { return riskOverride }
        if modifiesInsulinDelivery { return .delivery }
        if signed || characteristic == .control { return .settings }
        return .read
    }
}
