import Foundation

/// Assorted A2 settings-write control commands (CGM alert thresholds, Control-IQ settings, extended
/// bolus, G6 transmitter id). All signed CONTROL. Only `AdditionalBolus` dispenses insulin. Ports
/// of the corresponding `request/control/*Request` classes.

// MARK: - CGM alert settings (non-insulin)

/// CGM high/low glucose alert (opcode 0xC2 → 0xC3). 7-byte cargo: LE uint16 threshold +
/// LE uint16 repeatDurationMinutes + alertType + enable + bitmask.
public struct CgmHighLowAlertRequest: Message {
    public static let props = MessageProps(opCode: 0xC2, size: 7, signed: true, type: .request, characteristic: .control, responseOpCode: 0xC3)
    public var cargo: [UInt8]
    public private(set) var alertType = 0, threshold = 0, repeatDurationMinutes = 0, bitmask = 0
    public private(set) var enableAlert = false
    public init() { cargo = [] }
    public init(alertType: Int, threshold: Int, repeatDurationMinutes: Int, enableAlert: Bool, bitmask: Int) {
        self.alertType = alertType; self.threshold = threshold
        self.repeatDurationMinutes = repeatDurationMinutes; self.enableAlert = enableAlert; self.bitmask = bitmask
        self.cargo = Bytes.combine(Bytes.firstTwoBytesLittleEndian(threshold),
                                   Bytes.firstTwoBytesLittleEndian(repeatDurationMinutes),
                                   [UInt8(alertType & 0xFF), enableAlert ? 1 : 0, UInt8(bitmask & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// CGM out-of-range alert (opcode 0xC6 → 0xC7). 3-byte cargo: enable + alertDelay + bitmask.
public struct CgmOutOfRangeAlertRequest: Message {
    public static let props = MessageProps(opCode: 0xC6, size: 3, signed: true, type: .request, characteristic: .control, responseOpCode: 0xC7)
    public var cargo: [UInt8]
    public private(set) var enable = false
    public private(set) var alertDelay = 0, bitmask = 0
    public init() { cargo = [] }
    public init(enable: Bool, alertDelay: Int, bitmask: Int) {
        self.enable = enable; self.alertDelay = alertDelay; self.bitmask = bitmask
        self.cargo = [enable ? 1 : 0, UInt8(alertDelay & 0xFF), UInt8(bitmask & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// CGM rise/fall rate alert (opcode 0xC4 → 0xC5). 4-byte cargo: alertType + enable + mgPerDl + bitmask.
public struct CgmRiseFallAlertRequest: Message {
    public static let props = MessageProps(opCode: 0xC4, size: 4, signed: true, type: .request, characteristic: .control, responseOpCode: 0xC5)
    public var cargo: [UInt8]
    public private(set) var alertType = 0, mgPerDl = 0, bitmask = 0
    public private(set) var enable = false
    public init() { cargo = [] }
    public init(alertType: Int, enable: Bool, mgPerDl: Int, bitmask: Int) {
        self.alertType = alertType; self.enable = enable; self.mgPerDl = mgPerDl; self.bitmask = bitmask
        self.cargo = [UInt8(alertType & 0xFF), enable ? 1 : 0, UInt8(mgPerDl & 0xFF), UInt8(bitmask & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

// MARK: - Control-IQ settings (non-insulin)

/// Changes Control-IQ settings — enable, weight, total daily insulin (opcode 0xCA → 0xCB). 6-byte
/// cargo: enabled + LE uint16 weightLbs + [1, tdi, 1] (upstream magic framing).
public struct ChangeControlIQSettingsRequest: Message {
    public static let props = MessageProps(opCode: 0xCA, size: 6, signed: true, type: .request, characteristic: .control, responseOpCode: 0xCB)
    public var cargo: [UInt8]
    public private(set) var enabled = false
    public private(set) var weightLbs = 0, totalDailyInsulinUnits = 0
    public init() { cargo = [] }
    public init(enabled: Bool, weightLbs: Int, totalDailyInsulinUnits: Int) {
        self.enabled = enabled; self.weightLbs = weightLbs; self.totalDailyInsulinUnits = totalDailyInsulinUnits
        self.cargo = Bytes.combine([enabled ? 1 : 0], Bytes.firstTwoBytesLittleEndian(weightLbs),
                                   [1, UInt8(totalDailyInsulinUnits & 0xFF), 1])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

// MARK: - Extended bolus (INSULIN-AFFECTING)

/// Adds/continues an extended (additional) bolus referencing an existing bolusID (opcode
/// 0xFA → 0xFB). **modifiesInsulinDelivery** — bench-validate + gate. 4-byte cargo:
/// LE uint16 bolusID + LE uint16 reserve.
public struct AdditionalBolusRequest: Message {
    public static let props = MessageProps(opCode: 0xFA, size: 4, signed: true, type: .request, characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xFB)
    public var cargo: [UInt8]
    public private(set) var bolusID = 0, reserve = 0
    public init() { cargo = [] }
    public init(bolusID: Int, reserve: Int = 0) {
        self.bolusID = bolusID; self.reserve = reserve
        self.cargo = Bytes.combine(Bytes.firstTwoBytesLittleEndian(bolusID), Bytes.firstTwoBytesLittleEndian(reserve))
    }
    public mutating func parse(_ raw: [UInt8]) {
        let b = removeSignedRequestHmacBytes(raw); cargo = b
        if b.count >= 4 { bolusID = Bytes.readShort(b, 0); reserve = Bytes.readShort(b, 2) }
    }
}

// MARK: - CGM transmitter id (non-insulin)

/// Sets the Dexcom G6 transmitter id (opcode 0xB0 → 0xB1). 16-byte cargo: 6-char string + 10 zero pad.
public struct SetG6TransmitterIdRequest: Message {
    public static let props = MessageProps(opCode: 0xB0, size: 16, signed: true, type: .request, characteristic: .control, responseOpCode: 0xB1)
    public var cargo: [UInt8]
    public private(set) var txId = ""
    public init() { cargo = [] }
    public init(txId: String) {
        self.txId = txId
        self.cargo = Bytes.combine(Bytes.writeString(txId, 6), [UInt8](repeating: 0, count: 10))
    }
    public mutating func parse(_ raw: [UInt8]) {
        let b = removeSignedRequestHmacBytes(raw); cargo = b
        if b.count >= 6 { txId = Bytes.readString(b, 0, 6) }
    }
}
