import Foundation

/// The 47 history-log types upstream pumpx2 decodes that TandemKit didn't: the classes upstream
/// itself left out of its `HistoryLogParser` until 6dd97b1f, and the ones it has parsed since
/// (counters, bolus permission and remote-bolus request logs, control request and response logs,
/// battery and BLE statistics, Control-IQ diagnostics, and more). Scaffolded from upstream's `parse()` with
/// `scripts/port_message.py`; field names, offsets and widths are upstream's, and
/// `HistoryLogFieldParityTests` checks every field against the oracle. Upstream's own docs mark
/// many of these as provisional (`unknown…` fields are bytes it hasn't named); none of them is used
/// to decide a dose.

/// Alert/Alarm Annunciation — history-log event (typeId 434). Ported from AamAnnunciationHistoryLog.java.
public struct AamAnnunciationHistoryLog: HistoryLogEvent {
    public static let typeId = 434
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var categoryId: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var notificationId: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown19: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        categoryId = Int(raw[10])
        unknown11 = Int(raw[11])
        unknown12 = Bytes.readShort(raw, 12)
        notificationId = Int(Bytes.readUint32(raw, 14))
        unknown18 = Int(raw[18])
        unknown19 = Int(raw[19])
    }
}

/// AIDANET Daily Status 1 — history-log event (typeId 562). Ported from AntDailyStatus1HistoryLog.java.
public struct AntDailyStatus1HistoryLog: HistoryLogEvent {
    public static let typeId = 562
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var closedLoopPreferred: Bool = false
    public private(set) var totalDailyInsulinUnits: Int = 0
    public private(set) var glycemicGoal: Int = 0
    public private(set) var priorTherapy: Int = 0
    public private(set) var sleepEatSegmentStartTime0: Int = 0
    public private(set) var sleepEatSegmentStartTime1: Int = 0
    public private(set) var sleepEatSegmentStartTime2: Int = 0
    public private(set) var sleepEatSegmentStartTime3: Int = 0
    public private(set) var sleepEatSegmentType0: Int = 0
    public private(set) var sleepEatSegmentType1: Int = 0
    public private(set) var sleepEatSegmentType2: Int = 0
    public private(set) var sleepEatSegmentType3: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        closedLoopPreferred = raw[10] != 0
        totalDailyInsulinUnits = Int(raw[11])
        glycemicGoal = Int(raw[12])
        priorTherapy = Int(raw[13])
        sleepEatSegmentStartTime0 = Bytes.readShort(raw, 14)
        sleepEatSegmentStartTime1 = Bytes.readShort(raw, 16)
        sleepEatSegmentStartTime2 = Bytes.readShort(raw, 18)
        sleepEatSegmentStartTime3 = Bytes.readShort(raw, 20)
        sleepEatSegmentType0 = Int(raw[22])
        sleepEatSegmentType1 = Int(raw[23])
        sleepEatSegmentType2 = Int(raw[24])
        sleepEatSegmentType3 = Int(raw[25])
    }
}

/// AIDANET Daily Status 2 — history-log event (typeId 563). Ported from AntDailyStatus2HistoryLog.java.
public struct AntDailyStatus2HistoryLog: HistoryLogEvent {
    public static let typeId = 563
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var pumpControlState: Int = 0
    public private(set) var sensorType: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        pumpControlState = Int(raw[10])
        sensorType = Int(raw[11])
    }
}

/// AIDANET Sleep/Eat Schedule Change — history-log event (typeId 566). Ported from AntSleepEatSchedSettingChangeHistoryLog.java.
public struct AntSleepEatSchedSettingChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 566
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var sleepEatSegmentStartTime0: Int = 0
    public private(set) var sleepEatSegmentStartTime1: Int = 0
    public private(set) var sleepEatSegmentStartTime2: Int = 0
    public private(set) var sleepEatSegmentStartTime3: Int = 0
    public private(set) var sleepEatSegmentType0: Int = 0
    public private(set) var sleepEatSegmentType1: Int = 0
    public private(set) var sleepEatSegmentType2: Int = 0
    public private(set) var sleepEatSegmentType3: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        sleepEatSegmentStartTime0 = Bytes.readShort(raw, 10)
        sleepEatSegmentStartTime1 = Bytes.readShort(raw, 12)
        sleepEatSegmentStartTime2 = Bytes.readShort(raw, 14)
        sleepEatSegmentStartTime3 = Bytes.readShort(raw, 16)
        sleepEatSegmentType0 = Int(raw[18])
        sleepEatSegmentType1 = Int(raw[19])
        sleepEatSegmentType2 = Int(raw[20])
        sleepEatSegmentType3 = Int(raw[21])
    }
}

/// Authorization Counters — history-log event (typeId 494). Ported from AuthorizationCountersHistoryLog.java.
public struct AuthorizationCountersHistoryLog: HistoryLogEvent {
    public static let typeId = 494
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var authorizationRequestCount: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        authorizationRequestCount = Int(Bytes.readUint32(raw, 10))
        unknown14 = Int(Bytes.readUint32(raw, 14))
        unknown18 = Int(Bytes.readUint32(raw, 18))
        unknown22 = Int(Bytes.readUint32(raw, 22))
    }
}

/// Battery Estimate Update — history-log event (typeId 330). Ported from BatteryEstimateUpdateHistoryLog.java.
public struct BatteryEstimateUpdateHistoryLog: HistoryLogEvent {
    public static let typeId = 330
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown10: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var currentBatteryAbc: Int = 0
    public private(set) var unknown13: Int = 0
    public private(set) var lipoMv: Int = 0
    public private(set) var currentBatteryIbc: Int = 0
    public private(set) var elapsedMs: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        unknown10 = Int(raw[10])
        unknown11 = Int(raw[11])
        currentBatteryAbc = Int(raw[12])
        unknown13 = Int(raw[13])
        lipoMv = Bytes.readShort(raw, 16)
        currentBatteryIbc = Int(raw[18])
        elapsedMs = Int(Bytes.readUint32(raw, 22))
        unknown14 = Int(Int16(truncatingIfNeeded: Bytes.readShort(raw, 14)))
    }
}

/// Battery Hourly — history-log event (typeId 271). Ported from BatteryHourlyHistoryLog.java.
public struct BatteryHourlyHistoryLog: HistoryLogEvent {
    public static let typeId = 271
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknown16: Int = 0
    public private(set) var currentBatteryIbc: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var lipoMv: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown20: Int = 0
    public private(set) var unknown22: Int = 0
    public private(set) var unknown24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentBatteryIbc = Bytes.readShort(raw, 10)
        unknown12 = Bytes.readShort(raw, 12)
        lipoMv = Bytes.readShort(raw, 14)
        unknown18 = Bytes.readShort(raw, 18)
        unknown20 = Bytes.readShort(raw, 20)
        unknown22 = Bytes.readShort(raw, 22)
        unknown24 = Bytes.readShort(raw, 24)
        unknown16 = Int(Int16(truncatingIfNeeded: Bytes.readShort(raw, 16)))
    }
}

/// BLE Daily Connections — history-log event (typeId 474). Ported from BleDailyConnectionsHistoryLog.java.
public struct BleDailyConnectionsHistoryLog: HistoryLogEvent {
    public static let typeId = 474
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownTail: [UInt8] = []
    public private(set) var connectedPercent: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var connections: Int = 0
    public private(set) var unauthenticatedConnections: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        connectedPercent = Int(raw[10])
        unknown11 = Int(raw[11])
        connections = Bytes.readShort(raw, 12)
        unauthenticatedConnections = Bytes.readShort(raw, 14)
        unknownTail = Array(raw[16..<26])
    }
}

/// BLE Link Stats — history-log event (typeId 473). Ported from BleLinkStatsHistoryLog.java.
public struct BleLinkStatsHistoryLog: HistoryLogEvent {
    public static let typeId = 473
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var minimum: Int = 0
    public private(set) var maximum: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var unknown13: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown15: Int = 0
    public private(set) var unknown16: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var intervalSeconds: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        minimum = Int(raw[10])
        maximum = Int(raw[11])
        unknown12 = Int(raw[12])
        unknown13 = Int(raw[13])
        unknown14 = Int(raw[14])
        unknown15 = Int(raw[15])
        unknown16 = Bytes.readShort(raw, 16)
        unknown18 = Bytes.readShort(raw, 18)
        intervalSeconds = Bytes.readShort(raw, 20)
    }
}

/// BLE SoftDevice Version — history-log event (typeId 450). Ported from BleSoftDeviceVersionHistoryLog.java.
public struct BleSoftDeviceVersionHistoryLog: HistoryLogEvent {
    public static let typeId = 450
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var softDeviceId: Int = 0
    public private(set) var softDeviceMajorVersion: Int = 0
    public private(set) var softDeviceMinorVersion: Int = 0
    public private(set) var softDeviceBugfixVersion: Int = 0
    public private(set) var softDeviceId2: Int = 0
    public private(set) var softDeviceMajorVersion2: Int = 0
    public private(set) var softDeviceMinorVersion2: Int = 0
    public private(set) var softDeviceBugfixVersion2: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        softDeviceId = Bytes.readShort(raw, 10)
        softDeviceMajorVersion = Bytes.readShort(raw, 12)
        softDeviceMinorVersion = Bytes.readShort(raw, 14)
        softDeviceBugfixVersion = Bytes.readShort(raw, 16)
        softDeviceId2 = Bytes.readShort(raw, 18)
        softDeviceMajorVersion2 = Bytes.readShort(raw, 20)
        softDeviceMinorVersion2 = Bytes.readShort(raw, 22)
        softDeviceBugfixVersion2 = Bytes.readShort(raw, 24)
    }
}

/// Bolus Delivery Summary — history-log event (typeId 194). Ported from BolusDeliverySummaryHistoryLog.java.
public struct BolusDeliverySummaryHistoryLog: HistoryLogEvent {
    public static let typeId = 194
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownU8At10: Int = 0
    public private(set) var unknownU8At11: Int = 0
    public private(set) var unknownFloatAt14: Float = 0
    public private(set) var unknownFloatAt18: Float = 0
    public private(set) var unknownFloatAt22: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        unknownU8At10 = Int(raw[10])
        unknownU8At11 = Int(raw[11])
        unknownFloatAt14 = Bytes.readFloat(raw, 14)
        unknownFloatAt18 = Bytes.readFloat(raw, 18)
        unknownFloatAt22 = Bytes.readFloat(raw, 22)
    }
}

/// Bolus IOB Entry — history-log event (typeId 195). Ported from BolusIobEntryHistoryLog.java.
public struct BolusIobEntryHistoryLog: HistoryLogEvent {
    public static let typeId = 195
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownU8At10: Int = 0
    public private(set) var unknownU8At11: Int = 0
    public private(set) var insulinDurationMillis: Int = 0
    public private(set) var insulinDelivered: Float = 0
    public private(set) var mudaliarIob: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        unknownU8At10 = Int(raw[10])
        unknownU8At11 = Int(raw[11])
        insulinDurationMillis = Int(Bytes.readUint32(raw, 14))
        insulinDelivered = Bytes.readFloat(raw, 18)
        mudaliarIob = Bytes.readFloat(raw, 22)
    }
}

/// Bolus Permission Change — history-log event (typeId 295). Ported from BolusPermissionChangeHistoryLog.java.
public struct BolusPermissionChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 295
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var unknownU8At12: Int = 0
    public private(set) var unknownU8At13: Int = 0
    public private(set) var changeReasonId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        unknownU8At12 = Int(raw[12])
        unknownU8At13 = Int(raw[13])
        changeReasonId = Int(raw[14])
    }
}

/// Bolus Permission Request — history-log event (typeId 338). Ported from BolusPermissionRequestHistoryLog.java.
public struct BolusPermissionRequestHistoryLog: HistoryLogEvent {
    public static let typeId = 338
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var requestTimestamp: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        requestTimestamp = Int(Bytes.readUint32(raw, 10))
    }
}

/// Bolus Permission Response — history-log event (typeId 297). Ported from BolusPermissionResponseHistoryLog.java.
public struct BolusPermissionResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 297
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var unknownU8At14: Int = 0
    public private(set) var unknownU8At15: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        unknownU8At14 = Int(raw[14])
        unknownU8At15 = Int(raw[15])
    }
}

/// Cartridge/Fill Response — history-log event (typeId 359). Ported from CartridgeFillResponseHistoryLog.java.
public struct CartridgeFillResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 359
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownTail: [UInt8] = []
    public private(set) var responseOpCode: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else {
            status = 1
            return
        }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        responseOpCode = Int(raw[10])
        unknown11 = Int(raw[11])
        status = Int(raw[12])
        unknownTail = Array(raw[13..<26])
    }
}

/// CGM State Change — history-log event (typeId 219). Ported from CgmStateChangeGxHistoryLog.java.
public struct CgmStateChangeGxHistoryLog: HistoryLogEvent {
    public static let typeId = 219
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknown23: Int = 0
    public private(set) var eventId: Int = 0
    public private(set) var unknown15: Int = 0
    public private(set) var stateId: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var previousStateId: Int = 0
    public private(set) var unknown18: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        unknown18 = Int(Bytes.readUint32(raw, 18))
        let word10 = Bytes.readUint32(raw, 10)
        let word14 = Bytes.readUint32(raw, 14)
        let word22 = Bytes.readUint32(raw, 22)
        previousStateId = Int(word10 & 0xFF)
        unknown11 = Int(word10 >> 8)
        stateId = Int(word14 & 0xFF)
        unknown15 = Int(word14 >> 8)
        eventId = Int(word22 & 0xFF)
        unknown23 = Int(word22 >> 8)
    }
}

/// Charging Started — history-log event (typeId 34). Ported from ChargingStartedHistoryLog.java.
public struct ChargingStartedHistoryLog: HistoryLogEvent {
    public static let typeId = 34
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentBatteryAbc: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var currentBatteryIbc: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var lipoMv: Int = 0
    public private(set) var unknown22: Int = 0
    public private(set) var unknown24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentBatteryAbc = Bytes.readShort(raw, 10)
        unknown12 = Bytes.readShort(raw, 12)
        unknown14 = Bytes.readShort(raw, 14)
        currentBatteryIbc = Bytes.readShort(raw, 16)
        unknown18 = Bytes.readShort(raw, 18)
        lipoMv = Bytes.readShort(raw, 20)
        unknown22 = Bytes.readShort(raw, 22)
        unknown24 = Bytes.readShort(raw, 24)
    }
}

/// Charging Stopped — history-log event (typeId 35). Ported from ChargingStoppedHistoryLog.java.
public struct ChargingStoppedHistoryLog: HistoryLogEvent {
    public static let typeId = 35
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentBatteryAbc: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var currentBatteryIbc: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var lipoMv: Int = 0
    public private(set) var unknown22: Int = 0
    public private(set) var unknown24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentBatteryAbc = Bytes.readShort(raw, 10)
        unknown12 = Bytes.readShort(raw, 12)
        unknown14 = Bytes.readShort(raw, 14)
        currentBatteryIbc = Bytes.readShort(raw, 16)
        unknown18 = Bytes.readShort(raw, 18)
        lipoMv = Bytes.readShort(raw, 20)
        unknown22 = Bytes.readShort(raw, 22)
        unknown24 = Bytes.readShort(raw, 24)
    }
}

/// Control-IQ Automated Insulin — history-log event (typeId 237). Ported from ControlIQAutomatedInsulinHistoryLog.java.
public struct ControlIQAutomatedInsulinHistoryLog: HistoryLogEvent {
    public static let typeId = 237
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var totalInsulin: Float = 0
    public private(set) var basalAboveProfileInsulin: Float = 0
    public private(set) var autoBolusInsulin: Float = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        totalInsulin = Bytes.readFloat(raw, 10)
        basalAboveProfileInsulin = Bytes.readFloat(raw, 14)
        autoBolusInsulin = Bytes.readFloat(raw, 18)
        unknown22 = Int(Bytes.readUint32(raw, 22))
    }
}

/// Control-IQ Cycle — history-log event (typeId 227). Ported from ControlIQCycleHistoryLog.java.
public struct ControlIQCycleHistoryLog: HistoryLogEvent {
    public static let typeId = 227
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var basalIncreaseMilliunits: Int = 0
    public private(set) var cycleInsulinMilliunits: Int = 0
    public private(set) var predictedGlucoseX100: Int = 0
    public private(set) var programmedBasalRate: Int = 0
    public private(set) var netIobMilliunits: Int = 0
    public private(set) var glucoseEstimate: Int = 0
    public private(set) var correctionFactor: Int = 0
    public private(set) var tdiEstimate: Int = 0
    public private(set) var hypoBrake: Int = 0
    public private(set) var sleepRamp: Int = 0
    public private(set) var upperTarget: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        basalIncreaseMilliunits = Bytes.readShort(raw, 10)
        cycleInsulinMilliunits = Bytes.readShort(raw, 12)
        predictedGlucoseX100 = Bytes.readShort(raw, 14)
        programmedBasalRate = Bytes.readShort(raw, 16)
        netIobMilliunits = Bytes.readShort(raw, 18)
        glucoseEstimate = Int(raw[20])
        correctionFactor = Int(raw[21])
        tdiEstimate = Int(raw[22])
        hypoBrake = Int(raw[23])
        sleepRamp = Int(raw[24])
        upperTarget = Int(raw[25])
    }
}

/// Control-IQ Features — history-log event (typeId 328). Ported from ControlIQFeaturesHistoryLog.java.
public struct ControlIQFeaturesHistoryLog: HistoryLogEvent {
    public static let typeId = 328
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownTail: [UInt8] = []
    public private(set) var controlIqFeaturesBitmask: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        controlIqFeaturesBitmask = Int(Bytes.readUint32(raw, 10))
        unknownTail = Array(raw[14..<26])
    }
}

/// Control-IQ Glucose Model — history-log event (typeId 327). Ported from ControlIQGlucoseModelHistoryLog.java.
public struct ControlIQGlucoseModelHistoryLog: HistoryLogEvent {
    public static let typeId = 327
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var tdiEstimate: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var unknown12: Int = 0
    public private(set) var shortTermPredictedGlucoseRaw: Int = 0
    public private(set) var filteredGlucose: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var correctionFactor: Int = 0
    public private(set) var unknown21: Int = 0
    public private(set) var unknown22: Int = 0
    public private(set) var unknown24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        tdiEstimate = Int(raw[10])
        unknown11 = Int(raw[11])
        unknown12 = Bytes.readShort(raw, 12)
        shortTermPredictedGlucoseRaw = Bytes.readShort(raw, 14)
        filteredGlucose = Bytes.readShort(raw, 16)
        unknown18 = Bytes.readShort(raw, 18)
        correctionFactor = Int(raw[20])
        unknown21 = Int(raw[21])
        unknown22 = Bytes.readShort(raw, 22)
        unknown24 = Bytes.readShort(raw, 24)
    }
}

/// Control Request Counters — history-log event (typeId 492). Ported from ControlRequestCountersHistoryLog.java.
public struct ControlRequestCountersHistoryLog: HistoryLogEvent {
    public static let typeId = 492
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var controlRequestCount: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        controlRequestCount = Int(Bytes.readUint32(raw, 10))
        unknown14 = Int(Bytes.readUint32(raw, 14))
        unknown18 = Int(Bytes.readUint32(raw, 18))
        unknown22 = Int(Bytes.readUint32(raw, 22))
    }
}

/// Control Request — history-log event (typeId 290). Ported from ControlRequestHistoryLog.java.
public struct ControlRequestHistoryLog: HistoryLogEvent {
    public static let typeId = 290
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var requestTimestamp: Int = 0
    public private(set) var requestOpCode: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        requestTimestamp = Int(Bytes.readUint32(raw, 10))
        requestOpCode = Int(raw[14])
    }
}

/// Control Response — history-log event (typeId 300). Ported from ControlResponseHistoryLog.java.
public struct ControlResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 300
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownTail: [UInt8] = []
    public private(set) var responseOpCode: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else {
            status = 1
            return
        }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        responseOpCode = Int(raw[10])
        unknown11 = Int(raw[11])
        status = Int(raw[12])
        unknownTail = Array(raw[13..<26])
    }
}

/// Control Stream Counters — history-log event (typeId 493). Ported from ControlStreamCountersHistoryLog.java.
public struct ControlStreamCountersHistoryLog: HistoryLogEvent {
    public static let typeId = 493
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var controlStreamMessageCount: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        controlStreamMessageCount = Int(Bytes.readUint32(raw, 10))
        unknown14 = Int(Bytes.readUint32(raw, 14))
        unknown18 = Int(Bytes.readUint32(raw, 18))
        unknown22 = Int(Bytes.readUint32(raw, 22))
    }
}

/// Dismiss Notification Response — history-log event (typeId 334). Ported from DismissNotificationResponseHistoryLog.java.
public struct DismissNotificationResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 334
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownTail: [UInt8] = []
    public private(set) var responseOpCode: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else {
            status = 1
            return
        }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        responseOpCode = Int(raw[10])
        unknown11 = Int(raw[11])
        status = Int(raw[12])
        unknownTail = Array(raw[13..<26])
    }
}

/// History Request Counters — history-log event (typeId 490). Ported from HistoryRequestCountersHistoryLog.java.
public struct HistoryRequestCountersHistoryLog: HistoryLogEvent {
    public static let typeId = 490
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var historyLogRequestCount: Int = 0
    public private(set) var unknown14: Int = 0
    public private(set) var unknown18: Int = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        historyLogRequestCount = Int(Bytes.readUint32(raw, 10))
        unknown14 = Int(Bytes.readUint32(raw, 14))
        unknown18 = Int(Bytes.readUint32(raw, 18))
        unknown22 = Int(Bytes.readUint32(raw, 22))
    }
}

/// History Request Range — history-log event (typeId 491). Ported from HistoryRequestRangeHistoryLog.java.
public struct HistoryRequestRangeHistoryLog: HistoryLogEvent {
    public static let typeId = 491
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknown10: Int = 0
    public private(set) var minStartLog: Int = 0
    public private(set) var maxStartLog: Int = 0
    public private(set) var unknown22: Int = 0
    public private(set) var unknown24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        unknown10 = Int(Bytes.readUint32(raw, 10))
        minStartLog = Int(Bytes.readUint32(raw, 14))
        maxStartLog = Int(Bytes.readUint32(raw, 18))
        unknown22 = Bytes.readShort(raw, 22)
        unknown24 = Bytes.readShort(raw, 24)
    }
}

/// Initiate Bolus Request 1/3 — history-log event (typeId 292). Ported from InitiateBolusRequestMsg1HistoryLog.java.
public struct InitiateBolusRequestMsg1HistoryLog: HistoryLogEvent {
    public static let typeId = 292
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var requestTimestamp: Int = 0
    public private(set) var transactionId: Int = 0
    public private(set) var bolusTypeBitmask: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var totalVolume: Int = 0
    public private(set) var foodVolume: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        requestTimestamp = Int(Bytes.readUint32(raw, 10))
        transactionId = Int(raw[14])
        bolusTypeBitmask = Int(raw[15])
        bolusId = Bytes.readShort(raw, 16)
        totalVolume = Int(Bytes.readUint32(raw, 18))
        foodVolume = Int(Bytes.readUint32(raw, 22))
    }
}

/// Initiate Bolus Request 2/3 — history-log event (typeId 293). Ported from InitiateBolusRequestMsg2HistoryLog.java.
public struct InitiateBolusRequestMsg2HistoryLog: HistoryLogEvent {
    public static let typeId = 293
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var transactionId: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var correctionVolume: Int = 0
    public private(set) var extendedVolume: Int = 0
    public private(set) var bolusCarbs: Int = 0
    public private(set) var bolusBG: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        transactionId = Int(raw[10])
        bolusId = Bytes.readShort(raw, 12)
        correctionVolume = Int(Bytes.readUint32(raw, 14))
        extendedVolume = Int(Bytes.readUint32(raw, 18))
        bolusCarbs = Bytes.readShort(raw, 22)
        bolusBG = Bytes.readShort(raw, 24)
    }
}

/// Initiate Bolus Request 3/3 — history-log event (typeId 343). Ported from InitiateBolusRequestMsg3HistoryLog.java.
public struct InitiateBolusRequestMsg3HistoryLog: HistoryLogEvent {
    public static let typeId = 343
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var transactionId: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var bolusIOB: Int = 0
    public private(set) var extendedSeconds: Int = 0
    public private(set) var extended3: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        transactionId = Int(raw[10])
        bolusId = Bytes.readShort(raw, 12)
        bolusIOB = Int(Bytes.readUint32(raw, 14))
        extendedSeconds = Int(Bytes.readUint32(raw, 18))
        extended3 = Int(Bytes.readUint32(raw, 22))
    }
}

/// Initiate Bolus Response — history-log event (typeId 298). Ported from InitiateBolusResponseHistoryLog.java.
public struct InitiateBolusResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 298
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var unknownU8At14: Int = 0
    public private(set) var unknownU8At15: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        unknownU8At14 = Int(raw[14])
        unknownU8At15 = Int(raw[15])
    }
}

/// IOB Snapshot After Bolus — history-log event (typeId 207). Ported from IobSnapshotPostBolusHistoryLog.java.
public struct IobSnapshotPostBolusHistoryLog: HistoryLogEvent {
    public static let typeId = 207
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var unknownU8At12: Int = 0
    public private(set) var selectedIob: Int = 0
    public private(set) var mudaliarIob: Float = 0
    public private(set) var swan6hrIob: Float = 0
    public private(set) var unknownFloatAt22: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        unknownU8At12 = Int(raw[12])
        selectedIob = Int(raw[13])
        mudaliarIob = Bytes.readFloat(raw, 14)
        swan6hrIob = Bytes.readFloat(raw, 18)
        unknownFloatAt22 = Bytes.readFloat(raw, 22)
    }
}

/// IOB Snapshot Before Bolus — history-log event (typeId 206). Ported from IobSnapshotPreBolusHistoryLog.java.
public struct IobSnapshotPreBolusHistoryLog: HistoryLogEvent {
    public static let typeId = 206
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var unknownU8At12: Int = 0
    public private(set) var selectedIob: Int = 0
    public private(set) var mudaliarIob: Float = 0
    public private(set) var swan6hrIob: Float = 0
    public private(set) var unknownFloatAt22: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        unknownU8At12 = Int(raw[12])
        selectedIob = Int(raw[13])
        mudaliarIob = Bytes.readFloat(raw, 14)
        swan6hrIob = Bytes.readFloat(raw, 18)
        unknownFloatAt22 = Bytes.readFloat(raw, 22)
    }
}

/// Max Basal Limit Set — history-log event (typeId 274). Ported from MaxBasalLimitSetHistoryLog.java.
public struct MaxBasalLimitSetHistoryLog: HistoryLogEvent {
    public static let typeId = 274
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var maxHourlyBasalMilliunits: Int = 0
    public private(set) var previousMaxHourlyBasalMilliunits: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        maxHourlyBasalMilliunits = Int(Bytes.readUint32(raw, 10))
        previousMaxHourlyBasalMilliunits = Int(Bytes.readUint32(raw, 14))
    }
}

/// Max Bolus Limit Set — history-log event (typeId 326). Ported from MaxBolusLimitSetHistoryLog.java.
public struct MaxBolusLimitSetHistoryLog: HistoryLogEvent {
    public static let typeId = 326
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var maxBolusMilliunits: Int = 0
    public private(set) var previousMaxBolusMilliunits: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        maxBolusMilliunits = Bytes.readShort(raw, 10)
        previousMaxBolusMilliunits = Bytes.readShort(raw, 12)
    }
}

/// Pump Button — history-log event (typeId 17). Ported from PumpButtonHistoryLog.java.
public struct PumpButtonHistoryLog: HistoryLogEvent {
    public static let typeId = 17
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var timeOfDayMs: Int = 0
    public private(set) var state: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        timeOfDayMs = Int(Bytes.readUint32(raw, 10))
        state = Int(raw[14])
    }
}

/// Pump Drive Event — history-log event (typeId 277). Ported from PumpDriveEventHistoryLog.java.
public struct PumpDriveEventHistoryLog: HistoryLogEvent {
    public static let typeId = 277
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknownI16At16: Int = 0
    public private(set) var unknownI16At14: Int = 0
    public private(set) var driveCounter: Int = 0
    public private(set) var unknownU8At18: Int = 0
    public private(set) var unknownU8At19: Int = 0
    public private(set) var unknownU8At20: Int = 0
    public private(set) var unknownU8At21: Int = 0
    public private(set) var unknownU16At22: Int = 0
    public private(set) var unknownU16At24: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        driveCounter = Int(Bytes.readUint32(raw, 10))
        unknownU8At18 = Int(raw[18])
        unknownU8At19 = Int(raw[19])
        unknownU8At20 = Int(raw[20])
        unknownU8At21 = Int(raw[21])
        unknownU16At22 = Bytes.readShort(raw, 22)
        unknownU16At24 = Bytes.readShort(raw, 24)
        unknownI16At14 = Int(Int16(truncatingIfNeeded: Bytes.readShort(raw, 14)))
        unknownI16At16 = Int(Int16(truncatingIfNeeded: Bytes.readShort(raw, 16)))
    }
}

/// Reservoir Estimate — history-log event (typeId 231). Ported from ReservoirEstimateHistoryLog.java.
public struct ReservoirEstimateHistoryLog: HistoryLogEvent {
    public static let typeId = 231
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var insulinDelivered: Float = 0
    public private(set) var insulinRemaining: Float = 0
    public private(set) var displayedInsulinRemaining: Int = 0
    public private(set) var driveCounter: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        insulinDelivered = Bytes.readFloat(raw, 10)
        insulinRemaining = Bytes.readFloat(raw, 14)
        displayedInsulinRemaining = Int(raw[18])
        driveCounter = Int(Bytes.readUint32(raw, 22))
    }
}

/// Set Temp Rate Response — history-log event (typeId 309). Ported from SetTempRateResponseHistoryLog.java.
public struct SetTempRateResponseHistoryLog: HistoryLogEvent {
    public static let typeId = 309
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var status: Int = 0
    public private(set) var unknown11: Int = 0
    public private(set) var tempRateId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else {
            status = 1
            return
        }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        status = Int(raw[10])
        unknown11 = Int(raw[11])
        tempRateId = Bytes.readShort(raw, 12)
    }
}

/// Software ID — history-log event (typeId 449). Ported from SoftwareIdHistoryLog.java.
public struct SoftwareIdHistoryLog: HistoryLogEvent {
    public static let typeId = 449
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var unknown11: Int = 0
    public private(set) var slot: Int = 0
    public private(set) var armSwVersion: Int = 0
    public private(set) var softwareIdLow: Int = 0
    public private(set) var unknown22: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        slot = Int(raw[10])
        armSwVersion = Int(Bytes.readUint32(raw, 14))
        softwareIdLow = Int(Bytes.readUint32(raw, 18))
        unknown22 = Int(Bytes.readUint32(raw, 22))
        unknown11 = Int(raw[11]) | Int(raw[12]) << 8 | Int(raw[13]) << 16
    }
}

/// Sync Dose Complete — history-log event (typeId 559). Ported from SyncDoseCompleteHistoryLog.java.
public struct SyncDoseCompleteHistoryLog: HistoryLogEvent {
    public static let typeId = 559
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var doseId: Int = 0
    public private(set) var doseSource: Int = 0
    public private(set) var tempAdjustmentPercent: Int = 0
    public private(set) var syncDoseSizeDelivered: Float = 0
    public private(set) var currentBasalRate: Int = 0
    public private(set) var activeInsulin: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        doseId = Bytes.readShort(raw, 10)
        doseSource = Int(raw[12])
        tempAdjustmentPercent = Int(raw[13])
        syncDoseSizeDelivered = Bytes.readFloat(raw, 14)
        currentBasalRate = Bytes.readShort(raw, 18)
        activeInsulin = Bytes.readFloat(raw, 22)
    }
}

/// Sync Dose Start — history-log event (typeId 558). Ported from SyncDoseStartHistoryLog.java.
public struct SyncDoseStartHistoryLog: HistoryLogEvent {
    public static let typeId = 558
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var doseId: Int = 0
    public private(set) var doseSource: Int = 0
    public private(set) var tempAdjustmentPercent: Int = 0
    public private(set) var syncDoseSizeRequested: Float = 0
    public private(set) var currentBasalRate: Int = 0
    public private(set) var profileBasalRate: Int = 0
    public private(set) var activeInsulin: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        doseId = Bytes.readShort(raw, 10)
        doseSource = Int(raw[12])
        tempAdjustmentPercent = Int(raw[13])
        syncDoseSizeRequested = Bytes.readFloat(raw, 14)
        currentBasalRate = Bytes.readShort(raw, 18)
        profileBasalRate = Bytes.readShort(raw, 20)
        activeInsulin = Bytes.readFloat(raw, 22)
    }
}

/// Temp Adjustment Activated — history-log event (typeId 565). Ported from TempAdjustmentActivatedHistoryLog.java.
public struct TempAdjustmentActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 565
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var requestedPercent: Int = 0
    public private(set) var tempBasalPercent: Int = 0
    public private(set) var duration: Int = 0
    public private(set) var requestedAdjustmentType: Int = 0
    public private(set) var tempRateId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        requestedPercent = Bytes.readShort(raw, 10)
        tempBasalPercent = Bytes.readShort(raw, 12)
        duration = Int(Bytes.readUint32(raw, 18))
        requestedAdjustmentType = Bytes.readShort(raw, 22)
        tempRateId = Bytes.readShort(raw, 24)
    }
}

/// Temp Adjustment Completed — history-log event (typeId 564). Ported from TempAdjustmentCompletedHistoryLog.java.
public struct TempAdjustmentCompletedHistoryLog: HistoryLogEvent {
    public static let typeId = 564
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var stopReason: Int = 0
    public private(set) var tempRateId: Int = 0
    public private(set) var timeLeft: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        stopReason = Bytes.readShort(raw, 10)
        tempRateId = Bytes.readShort(raw, 12)
        timeLeft = Int(Bytes.readUint32(raw, 14))
    }
}
