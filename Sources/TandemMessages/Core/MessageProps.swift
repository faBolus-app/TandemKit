import Foundation

/// Operation-risk class for a message (audit P-01). The 3-state `WritePolicy` byte gate is too coarse:
/// its `.allowNonDelivery` band lumps genuinely-benign signed ops (dismiss an alert, find-my-pump) with
/// therapy-significant configuration (set max bolus, Control-IQ, time sync) and destructive commands
/// (factory reset). This class lets a caller authorize on the *consequence* of a message, not just on
/// "does it dispense insulin". Ordered least→most dangerous.
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
        requestOpCode: UInt8? = nil
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
    }

    /// The operation-risk class (audit P-01). Uses the explicit `risk:` when a message declares one;
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
