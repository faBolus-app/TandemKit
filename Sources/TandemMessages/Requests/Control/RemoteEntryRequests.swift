import Foundation

/// Remote BG / carb entry (A2). Signed CONTROL writes that record a manual BG or carb value for the
/// bolus calculator — they do NOT dispense insulin (`modifiesInsulinDelivery` false), so they're
/// safe to expose to the watch/Garmin remote. Ports of `request/control/RemoteBgEntryRequest` and
/// `RemoteCarbEntryRequest`. Byte-parity covered in OracleParityTests.

/// Records a remote carb entry (opcode 0xF2 → 0xF3). 9-byte cargo: LE uint16 carbs + unknown byte +
/// uint32 pumpTime + LE uint16 bolusId.
public struct RemoteCarbEntryRequest: Message {
    public static let props = MessageProps(
        opCode: 0xF2, size: 9, signed: true, type: .request,
        characteristic: .control, risk: .benign, responseOpCode: 0xF3)   // records carb metadata; does not dose (P-01)
    public var cargo: [UInt8]
    public private(set) var carbs = 0
    public private(set) var unknown = 0
    public private(set) var pumpTimeSecondsSinceBoot: UInt32 = 0
    public private(set) var bolusId = 0
    public init() { cargo = [] }
    public init(carbs: Int, unknown: Int = 0, pumpTimeSecondsSinceBoot: UInt32, bolusId: Int) {
        self.carbs = carbs
        self.unknown = unknown
        self.pumpTimeSecondsSinceBoot = pumpTimeSecondsSinceBoot
        self.bolusId = bolusId
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(carbs),
            [UInt8(unknown & 0xFF)],
            Bytes.toUint32(pumpTimeSecondsSinceBoot),
            Bytes.firstTwoBytesLittleEndian(bolusId))
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        guard body.count >= 9 else { return }
        carbs = Bytes.readShort(body, 0)
        unknown = Int(body[2])
        pumpTimeSecondsSinceBoot = Bytes.readUint32(body, 3)
        bolusId = Bytes.readShort(body, 7)
    }
}

/// Records a remote BG entry (opcode 0xB6 → 0xB7). 11-byte cargo: LE uint16 bg +
/// useForCgmCalibration byte + entryType byte + source byte + uint32 pumpTime + LE uint16 bolusId.
/// entryType per BloodGlucoseReadingType (MANUAL=0), source per BloodGlucoseReadingSource
/// (PUMP=0, REMOTE=1).
public struct RemoteBgEntryRequest: Message {
    public static let props = MessageProps(
        opCode: 0xB6, size: 11, signed: true, type: .request,
        characteristic: .control, risk: .benign, responseOpCode: 0xB7)   // records BG metadata; does not dose (P-01)
    public var cargo: [UInt8]
    public private(set) var bg = 0
    public private(set) var useForCgmCalibration = false
    public private(set) var entryTypeId = 0
    public private(set) var sourceId = 0
    public private(set) var pumpTimeSecondsSinceBoot: UInt32 = 0
    public private(set) var bolusId = 0
    public init() { cargo = [] }

    /// PX-01: a plain remote BG entry is benign metadata, but a BG marked
    /// `useForCgmCalibration` **recalibrates the CGM** — that shifts every subsequent glucose reading
    /// and therefore every Control-IQ / bolus-calc decision, so it is therapy-significant (`.settings`),
    /// not `.benign`. Risk is computed from cargo so `.allowBenignControl` cannot smuggle a calibration.
    public var operationRisk: OperationRisk { useForCgmCalibration ? .settings : .benign }

    /// Low-level init with explicit entryType/source ids.
    public init(bg: Int, useForCgmCalibration: Bool, entryTypeId: Int, sourceId: Int,
                pumpTimeSecondsSinceBoot: UInt32, bolusId: Int) {
        self.bg = bg
        self.useForCgmCalibration = useForCgmCalibration
        self.entryTypeId = entryTypeId
        self.sourceId = sourceId
        self.pumpTimeSecondsSinceBoot = pumpTimeSecondsSinceBoot
        self.bolusId = bolusId
        self.cargo = Bytes.combine(
            Bytes.firstTwoBytesLittleEndian(bg),
            [useForCgmCalibration ? 1 : 0],
            [UInt8(entryTypeId & 0xFF)],
            [UInt8(sourceId & 0xFF)],
            Bytes.toUint32(pumpTimeSecondsSinceBoot),
            Bytes.firstTwoBytesLittleEndian(bolusId))
    }

    /// Convenience matching upstream: entryType = MANUAL(0); source = REMOTE(1) if autopop else PUMP(0).
    public init(bg: Int, useForCgmCalibration: Bool, isAutopopBg: Bool,
                pumpTimeSecondsSinceBoot: UInt32, bolusId: Int) {
        self.init(bg: bg, useForCgmCalibration: useForCgmCalibration, entryTypeId: 0,
                  sourceId: isAutopopBg ? 1 : 0, pumpTimeSecondsSinceBoot: pumpTimeSecondsSinceBoot,
                  bolusId: bolusId)
    }

    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        guard body.count >= 11 else { return }
        bg = Bytes.readShort(body, 0)
        useForCgmCalibration = body[2] != 0
        entryTypeId = Int(body[3])
        sourceId = Int(body[4])
        pumpTimeSecondsSinceBoot = Bytes.readUint32(body, 5)
        bolusId = Bytes.readShort(body, 9)
    }
}
