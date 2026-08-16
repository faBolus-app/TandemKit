import Foundation

/// Delivery-limit settings (A2). Signed CONTROL writes. Upstream does not flag these
/// `modifiesInsulinDelivery` (they set bounds, they don't dispense), but they gate future delivery,
/// so the app still exposes them behind the advanced-control + Mobi gate. Pair with the
/// `GlobalMaxBolusSettings` / `BasalLimitSettings` reads. Ports of
/// `request/control/{SetMaxBolusLimit,SetMaxBasalLimit}Request`.

/// Sets the max-bolus limit in milliunits (opcode 0x86 → 0x87). 2-byte LE cargo.
public struct SetMaxBolusLimitRequest: Message {
    public static let props = MessageProps(
        opCode: 0x86, size: 2, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0x87)
    public var cargo: [UInt8]
    public private(set) var maxBolusMilliunits = 0
    public init() { cargo = [] }
    public init(maxBolusMilliunits: Int) {
        self.maxBolusMilliunits = maxBolusMilliunits
        self.cargo = Bytes.firstTwoBytesLittleEndian(maxBolusMilliunits)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 2 { maxBolusMilliunits = Bytes.readShort(body, 0) }
    }
}

/// Sets the max hourly-basal limit in milliunits/hr (opcode 0x88 → 0x89). 4-byte uint32 cargo.
public struct SetMaxBasalLimitRequest: Message {
    public static let props = MessageProps(
        opCode: 0x88, size: 4, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0x89)
    public var cargo: [UInt8]
    public private(set) var maxHourlyBasalMilliunits: UInt32 = 0
    public init() { cargo = [] }
    public init(maxHourlyBasalMilliunits: UInt32) {
        self.maxHourlyBasalMilliunits = maxHourlyBasalMilliunits
        self.cargo = Bytes.toUint32(maxHourlyBasalMilliunits)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 4 { maxHourlyBasalMilliunits = Bytes.readUint32(body, 0) }
    }
}
