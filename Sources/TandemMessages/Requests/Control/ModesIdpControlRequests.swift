import Foundation

/// Pump-mode + active-profile control (A2). **Both modify insulin delivery** (they change
/// Control-IQ behavior / the active basal profile), so `modifiesInsulinDelivery=true` — the app
/// must raise WritePolicy to `.allowDelivery` and these require bench (saline) validation before
/// being relied upon, behind the advanced-control + Mobi gate. Ports of
/// `request/control/{SetModes,SetActiveIDP}Request`.

/// Sets the pump user mode bitmap — sleep / exercise (opcode 0xCC → 0xCD). 1-byte bitmap cargo.
/// Precondition (per firmware): Control-IQ must be enabled. Port of `request/control/SetModesRequest`.
public struct SetModesRequest: Message {
    public static let props = MessageProps(
        opCode: 0xCC, size: 1, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xCD)

    /// The mode toggle carried in the 1-byte bitmap. Values match the pump firmware / Tandem Source
    /// event schema — **do not renumber**. 5–7 are defined but unsupported in current firmware.
    public enum ModeCommand: Int, CaseIterable {
        case sleepModeOn = 1
        case sleepModeOff = 2
        case exerciseModeOn = 3
        case exerciseModeOff = 4
        case unsupportedStopAll = 5
        case unsupportedStartEatingSoon = 6
        case unsupportedStopEatingSoon = 7

        public var bitmap: Int { rawValue }
        public static func fromBitmap(_ bitmap: Int) -> ModeCommand? { ModeCommand(rawValue: bitmap) }
    }

    public var cargo: [UInt8]
    public private(set) var bitmap = 0
    public init() { cargo = [] }
    public init(bitmap: Int) {
        self.bitmap = bitmap
        self.cargo = [UInt8(bitmap & 0xFF)]
    }
    /// Convenience: build from a symbolic `ModeCommand` instead of a raw bitmap.
    public init(mode: ModeCommand) { self.init(bitmap: mode.bitmap) }
    /// The decoded mode, or nil if the bitmap isn't a known command.
    public var command: ModeCommand? { ModeCommand.fromBitmap(bitmap) }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if !body.isEmpty { bitmap = Int(body[0]) }
    }
}

/// Switches the active insulin-delivery profile (opcode 0xEC → 0xED). 2-byte cargo:
/// idpId + profileIndex. Changes basal delivery.
public struct SetActiveIDPRequest: Message {
    public static let props = MessageProps(
        opCode: 0xEC, size: 2, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xED)
    public var cargo: [UInt8]
    public private(set) var idpId = 0
    public private(set) var profileIndex = 0
    public init() { cargo = [] }
    public init(idpId: Int, profileIndex: Int = 0) {
        self.idpId = idpId
        self.profileIndex = profileIndex
        self.cargo = [UInt8(idpId & 0xFF), UInt8(profileIndex & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 2 { idpId = Int(body[0]); profileIndex = Int(body[1]) }
    }
}
