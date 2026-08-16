import Foundation

/// Typed history-log events (A4). The pump keeps a rolling on-device log; each entry is a fixed
/// 26-byte record streamed inside `HistoryLogStreamResponse`. Every record starts with a common
/// header (`HistoryLog.parseBase`): typeId = short@0 & 0x0FFF, pumpTimeSec = uint32@2,
/// sequenceNum = uint32@6. `HistoryLogParser` dispatches a record to the matching event struct by
/// typeId (falling back to `UnknownHistoryLog`).
///
/// These are **decode-only** — the pump produces them, the app never sends them — so correctness =
/// our decode matching upstream's decode for the same bytes (verified via the oracle `historylog`
/// command). Most structs are scaffolded by `scripts/port_message.py` from
/// `references/pumpx2/.../response/historyLog/*` and are byte-faithful ports of upstream `parse()`.

/// A decoded history-log event. `typeId` identifies the record type; base fields are shared.
public protocol HistoryLogEvent: Sendable {
    static var typeId: Int { get }
    var cargo: [UInt8] { get }
    var pumpTimeSec: UInt32 { get }
    var sequenceNum: UInt32 { get }
    init(cargo: [UInt8])
}

public extension HistoryLogEvent {
    var typeId: Int { Self.typeId }
    /// The record's pump-clock timestamp as a `Date` (Jan 1 2008 epoch).
    var pumpTime: Date { Date(timeIntervalSince1970: HistoryLog.jan12008UnixEpoch + Double(pumpTimeSec)) }
}

/// Fallback for a record whose typeId we don't (yet) decode. Preserves the header + raw cargo.
public struct UnknownHistoryLog: HistoryLogEvent {
    public static let typeId = -1
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var rawTypeId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 10 else { return }
        rawTypeId = Bytes.readShort(raw, 0) & 0x0FFF
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Dispatches a 26-byte history-log record to a typed `HistoryLogEvent` by typeId. Mirrors
/// upstream `HistoryLogParser` (`LOG_MESSAGE_TYPES`). Register new event types with `add(_:)`.
public enum HistoryLogParser {
    static let factories: [Int: @Sendable ([UInt8]) -> any HistoryLogEvent] = {
        var r: [Int: @Sendable ([UInt8]) -> any HistoryLogEvent] = [:]
        func add<E: HistoryLogEvent>(_ type: E.Type) { r[E.typeId] = { E(cargo: $0) } }
        add(BolusDeliveryHistoryLog.self)
        add(BolusCompletedHistoryLog.self)
        add(BolusActivatedHistoryLog.self)
        add(BolexActivatedHistoryLog.self)
        add(BolexCompletedHistoryLog.self)
        add(BolusRequestedMsg1HistoryLog.self)
        add(BolusRequestedMsg2HistoryLog.self)
        add(BolusRequestedMsg3HistoryLog.self)
        add(BasalRateChangeHistoryLog.self)
        add(DailyBasalHistoryLog.self)
        add(TempRateActivatedHistoryLog.self)
        add(TempRateCompletedHistoryLog.self)
        add(CarbEnteredHistoryLog.self)
        add(BGHistoryLog.self)
        add(DexcomG6CGMHistoryLog.self)
        add(AlarmActivatedHistoryLog.self)
        add(AlertActivatedHistoryLog.self)
        add(AlarmClearedHistoryLog.self)
        add(PumpingResumedHistoryLog.self)
        add(PumpingSuspendedHistoryLog.self)
        add(CartridgeFilledHistoryLog.self)
        add(CannulaFilledHistoryLog.self)
        add(TubingFilledHistoryLog.self)
        add(AlertClearedHistoryLog.self)
        add(ArmInitHistoryLog.self)
        add(BasalDeliveryHistoryLog.self)
        add(CgmAlertAckDexHistoryLog.self)
        add(CgmAlertActivatedDexHistoryLog.self)
        add(CgmAlertActivatedFsl2HistoryLog.self)
        add(CgmAlertActivatedHistoryLog.self)
        add(CgmAlertClearedDexHistoryLog.self)
        add(CgmAlertClearedFsl2HistoryLog.self)
        add(CgmAlertClearedHistoryLog.self)
        add(CgmCalibrationGxHistoryLog.self)
        add(CgmCalibrationHistoryLog.self)
        add(CgmDataFsl2HistoryLog.self)
        add(CgmDataFsl3HistoryLog.self)
        add(CgmDataGxHistoryLog.self)
        add(CgmDataSampleHistoryLog.self)
        add(CgmJoinSessionFsl2HistoryLog.self)
        add(CgmJoinSessionFsl3HistoryLog.self)
        add(CgmJoinSessionG7HistoryLog.self)
        add(CgmJoinSessionHistoryLog.self)
        add(CgmStartSessionFsl2HistoryLog.self)
        add(CgmStartSessionHistoryLog.self)
        add(CgmStopSessionFsl2HistoryLog.self)
        add(CgmStopSessionFsl3HistoryLog.self)
        add(CgmStopSessionG7HistoryLog.self)
        add(CgmStopSessionHistoryLog.self)
        add(ControlIQPcmChangeHistoryLog.self)
        add(ControlIQUserModeChangeHistoryLog.self)
        add(CorrectionDeclinedHistoryLog.self)
        add(DailyStatusHistoryLog.self)
        add(DataLogCorruptionHistoryLog.self)
        add(DateChangeHistoryLog.self)
        add(DexcomG7CGMHistoryLog.self)
        add(FactoryResetHistoryLog.self)
        add(HypoMinimizerResumeHistoryLog.self)
        add(HypoMinimizerSuspendHistoryLog.self)
        add(IdpActionHistoryLog.self)
        add(IdpActionMsg2HistoryLog.self)
        add(IdpBolusHistoryLog.self)
        add(IdpListHistoryLog.self)
        add(IdpTimeDependentSegmentHistoryLog.self)
        add(LogErasedHistoryLog.self)
        add(MalfunctionHistoryLog.self)
        add(NewDayHistoryLog.self)
        add(ParamChangeGlobalSettingsHistoryLog.self)
        add(ParamChangePumpSettingsHistoryLog.self)
        add(ParamChangeRemSettingsHistoryLog.self)
        add(ParamChangeReminderHistoryLog.self)
        add(PlgsPeriodicHistoryLog.self)
        add(ShelfModeHistoryLog.self)
        add(TimeChangedHistoryLog.self)
        add(UpdateStatusHistoryLog.self)
        add(UsbConnectedHistoryLog.self)
        add(UsbDisconnectedHistoryLog.self)
        add(UsbEnumeratedHistoryLog.self)
        add(VersionInfoHistoryLog.self)
        add(VersionsAHistoryLog.self)
        add(AAExerciseChoiceChangeHistoryLog.self)
        add(AAExerciseTimeChangeHistoryLog.self)
        add(AATdiEstChangeHistoryLog.self)
        add(AaAutoBolusRejectedHistoryLog.self)
        add(AaDeliveryStatusChangeHistoryLog.self)
        add(AaEnableSettingChangeHistoryLog.self)
        add(AaSleepScheduleChangeHistoryLog.self)
        add(AaTdiSettingChangeHistoryLog.self)
        add(AaWeightSettingChangeHistoryLog.self)
        add(AlarmAckHistoryLog.self)
        add(AlertAckHistoryLog.self)
        add(BasalIqSettingsChangeHistoryLog.self)
        add(CartridgeInsertedHistoryLog.self)
        add(CartridgeRemovedHistoryLog.self)
        add(CgmAlertAckHistoryLog.self)
        add(CgmAnnuSettingsHistoryLog.self)
        add(CgmBleCalibrationEvtG7HistoryLog.self)
        add(CgmCalibrationG7HistoryLog.self)
        add(CgmFraSettingsHistoryLog.self)
        add(CgmHgaSettingsHistoryLog.self)
        add(CgmInactiveG7HistoryLog.self)
        add(CgmInactiveGxHistoryLog.self)
        add(CgmLgaSettingsHistoryLog.self)
        add(CgmOorSettingsHistoryLog.self)
        add(CgmPairingCodeG7HistoryLog.self)
        add(CgmRejoinSessionHistoryLog.self)
        add(CgmRraSettingsHistoryLog.self)
        add(CgmSensorTypeChangeHistoryLog.self)
        add(CgmSessionTypeChangeHistoryLog.self)
        add(CgmStartSensorReqG7HistoryLog.self)
        add(CgmStartSessionReqGxHistoryLog.self)
        add(CgmStopSessionMsg1HistoryLog.self)
        add(CgmStopSessionMsg2HistoryLog.self)
        add(CgmStopSessionReqG7HistoryLog.self)
        add(CgmStopSessionReqGxHistoryLog.self)
        add(CgmTransmitterIdGxHistoryLog.self)
        add(CgmTransmitterIdHistoryLog.self)
        add(CgmTransmitterVersionGxHistoryLog.self)
        add(CgmUnexpectedGeAlertHistoryLog.self)
        add(ConfirmCartridgeFilledHistoryLog.self)
        add(FillEstimateFinalHistoryLog.self)
        add(MalfunctionAckHistoryLog.self)
        add(PrimeInprocessHistoryLog.self)
        add(ReminderActivatedHistoryLog.self)
        add(ReminderDismissedHistoryLog.self)
        add(ReminderSnoozedHistoryLog.self)
        add(SnoozeActivatedHistoryLog.self)
        add(TipsErrorHistoryLog.self)
        add(TipscReqPrimeCannulaHistoryLog.self)
        add(WumpCartridgeFilledHistoryLog.self)
        add(WumpCartridgeRemovedHistoryLog.self)
        add(WumpOcclusionDebugHistoryLog.self)
        return r
    }()

    /// The number of distinct history-log event types currently decoded.
    public static var decodedTypeCount: Int { factories.count }

    /// Parses one 26-byte record into a typed event, or `UnknownHistoryLog` if the typeId is
    /// unknown / the record is too short.
    public static func parse(record raw: [UInt8]) -> any HistoryLogEvent {
        guard raw.count >= 10 else { return UnknownHistoryLog(cargo: raw) }
        let typeId = Bytes.readShort(raw, 0) & 0x0FFF
        if let make = factories[typeId] { return make(raw) }
        return UnknownHistoryLog(cargo: raw)
    }
}

// MARK: - Boluses

/// Bolus Delivery — history-log event (typeId 280).
public struct BolusDeliveryHistoryLog: HistoryLogEvent {
    public static let typeId = 280
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusID: Int = 0
    public private(set) var bolusDeliveryStatusId: Int = 0
    public private(set) var bolusTypeBitmask: Int = 0
    public private(set) var bolusSource: Int = 0
    public private(set) var reserved: Int = 0
    public private(set) var requestedNow: Int = 0
    public private(set) var requestedLater: Int = 0
    public private(set) var correction: Int = 0
    public private(set) var extendedDurationRequested: Int = 0
    public private(set) var deliveredTotal: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusID = Bytes.readShort(raw, 10)
        bolusDeliveryStatusId = Int(raw[12])
        bolusTypeBitmask = Int(raw[13])
        bolusSource = Int(raw[14])
        reserved = Int(raw[15])
        requestedNow = Bytes.readShort(raw, 16)
        requestedLater = Bytes.readShort(raw, 18)
        correction = Bytes.readShort(raw, 20)
        extendedDurationRequested = Bytes.readShort(raw, 22)
        deliveredTotal = Bytes.readShort(raw, 24)
    }
}

/// Bolus Completed — history-log event (typeId 20). iob/insulin fields are real insulin units.
public struct BolusCompletedHistoryLog: HistoryLogEvent {
    public static let typeId = 20
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var completionStatusId: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var insulinDelivered: Float = 0
    public private(set) var insulinRequested: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        completionStatusId = Bytes.readShort(raw, 10)
        bolusId = Bytes.readShort(raw, 12)
        iob = Bytes.readFloat(raw, 14)
        insulinDelivered = Bytes.readFloat(raw, 18)
        insulinRequested = Bytes.readFloat(raw, 22)
    }
}

/// Bolus Activated — history-log event (typeId 55).
public struct BolusActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 55
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var bolusSize: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        iob = Bytes.readFloat(raw, 14)
        bolusSize = Bytes.readFloat(raw, 18)
    }
}

/// Extended Bolus Activated — history-log event (typeId 59).
public struct BolexActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 59
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var bolexSize: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        iob = Bytes.readFloat(raw, 14)
        bolexSize = Bytes.readFloat(raw, 18)
    }
}

/// Extended Bolus Portion Complete — history-log event (typeId 21).
public struct BolexCompletedHistoryLog: HistoryLogEvent {
    public static let typeId = 21
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var completionStatusId: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var insulinDelivered: Float = 0
    public private(set) var insulinRequested: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        completionStatusId = Bytes.readShort(raw, 10)
        bolusId = Bytes.readShort(raw, 12)
        iob = Bytes.readFloat(raw, 14)
        insulinDelivered = Bytes.readFloat(raw, 18)
        insulinRequested = Bytes.readFloat(raw, 22)
    }
}

/// Bolus Requested 1/3 — history-log event (typeId 64).
public struct BolusRequestedMsg1HistoryLog: HistoryLogEvent {
    public static let typeId = 64
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var bolusTypeId: Int = 0
    public private(set) var correctionBolusIncluded: Bool = false
    public private(set) var carbAmount: Int = 0
    public private(set) var bg: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var carbRatio: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        bolusTypeId = Int(raw[12])
        correctionBolusIncluded = raw[13] != 0
        carbAmount = Bytes.readShort(raw, 14)
        bg = Bytes.readShort(raw, 16)
        iob = Bytes.readFloat(raw, 18)
        carbRatio = Int(Bytes.readUint32(raw, 22))
    }
}

/// Bolus Requested 2/3 — history-log event (typeId 65).
public struct BolusRequestedMsg2HistoryLog: HistoryLogEvent {
    public static let typeId = 65
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var options: Int = 0
    public private(set) var standardPercent: Int = 0
    public private(set) var duration: Int = 0
    public private(set) var spare1: Int = 0
    public private(set) var isf: Int = 0
    public private(set) var targetBG: Int = 0
    public private(set) var userOverride: Bool = false
    public private(set) var declinedCorrection: Bool = false
    public private(set) var selectedIOB: Int = 0
    public private(set) var spare2: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        options = Int(raw[12])
        standardPercent = Int(raw[13])
        duration = Bytes.readShort(raw, 14)
        spare1 = Bytes.readShort(raw, 16)
        isf = Bytes.readShort(raw, 18)
        targetBG = Bytes.readShort(raw, 20)
        userOverride = raw[22] != 0
        declinedCorrection = raw[23] != 0
        selectedIOB = Int(raw[24])
        spare2 = Int(raw[25])
    }
}

/// Bolus Requested 3/3 — history-log event (typeId 66). Bolus sizes are real insulin units.
public struct BolusRequestedMsg3HistoryLog: HistoryLogEvent {
    public static let typeId = 66
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bolusId: Int = 0
    public private(set) var spare: Int = 0
    public private(set) var foodBolusSize: Float = 0
    public private(set) var correctionBolusSize: Float = 0
    public private(set) var totalBolusSize: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bolusId = Bytes.readShort(raw, 10)
        spare = Bytes.readShort(raw, 12)
        foodBolusSize = Bytes.readFloat(raw, 14)
        correctionBolusSize = Bytes.readFloat(raw, 18)
        totalBolusSize = Bytes.readFloat(raw, 22)
    }
}

// MARK: - Basal / temp rate

/// Basal Rate Change — history-log event (typeId 3). Rates are real units/hr (IEEE floats).
public struct BasalRateChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 3
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var commandBasalRate: Float = 0
    public private(set) var baseBasalRate: Float = 0
    public private(set) var maxBasalRate: Float = 0
    public private(set) var insulinDeliveryProfile: Int = 0
    public private(set) var changeTypeId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        commandBasalRate = Bytes.readFloat(raw, 10)
        baseBasalRate = Bytes.readFloat(raw, 14)
        maxBasalRate = Bytes.readFloat(raw, 18)
        insulinDeliveryProfile = Bytes.readShort(raw, 22)
        changeTypeId = Int(raw[24])
    }
}

/// Daily Basal — history-log event (typeId 81). End-of-day totals + battery snapshot.
public struct DailyBasalHistoryLog: HistoryLogEvent {
    public static let typeId = 81
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var dailyTotalBasal: Float = 0
    public private(set) var lastBasalRate: Float = 0
    public private(set) var iob: Float = 0
    public private(set) var finalEventForDay: Bool = false
    public private(set) var batteryChargeRaw: Int = 0
    public private(set) var lipoMv: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        dailyTotalBasal = Bytes.readFloat(raw, 10)
        lastBasalRate = Bytes.readFloat(raw, 14)
        iob = Bytes.readFloat(raw, 18)
        finalEventForDay = raw[22] == 1
        batteryChargeRaw = Int(raw[23])
        lipoMv = Bytes.readShort(raw, 24)
    }
}

/// Temporary Basal Rate Activated — history-log event (typeId 2).
public struct TempRateActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 2
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var percent: Float = 0
    public private(set) var duration: Float = 0
    public private(set) var tempRateId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        percent = Bytes.readFloat(raw, 10)
        duration = Bytes.readFloat(raw, 14)
        tempRateId = Bytes.readShort(raw, 20)
    }
}

/// Temporary Basal Rate Completed — history-log event (typeId 15).
public struct TempRateCompletedHistoryLog: HistoryLogEvent {
    public static let typeId = 15
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var tempRateId: Int = 0
    public private(set) var timeLeft: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        tempRateId = Bytes.readShort(raw, 12)
        timeLeft = Int(Bytes.readUint32(raw, 14))
    }
}

// MARK: - Carbs / BG / CGM

/// Carbs Entered — history-log event (typeId 48).
public struct CarbEnteredHistoryLog: HistoryLogEvent {
    public static let typeId = 48
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var carbs: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        carbs = Bytes.readFloat(raw, 10)
    }
}

/// BG Taken — history-log event (typeId 16).
public struct BGHistoryLog: HistoryLogEvent {
    public static let typeId = 16
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bg: Int = 0
    public private(set) var cgmCalibration: Int = 0
    public private(set) var bgSourceId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var targetBG: Int = 0
    public private(set) var isf: Int = 0
    public private(set) var selectedIOB: Int = 0
    public private(set) var bgSourceType: Int = 0
    public private(set) var spare: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bg = Bytes.readShort(raw, 10)
        cgmCalibration = Int(raw[12])
        bgSourceId = Int(raw[13])
        iob = Bytes.readFloat(raw, 14)
        targetBG = Bytes.readShort(raw, 18)
        isf = Bytes.readShort(raw, 20)
        selectedIOB = Int(raw[22])
        bgSourceType = Int(raw[23])
        spare = Bytes.readShort(raw, 24)
    }
}

/// Dexcom G6 CGM Data — history-log event (typeId 256). `currentGlucoseDisplayValue` is the mg/dL.
public struct DexcomG6CGMHistoryLog: HistoryLogEvent {
    public static let typeId = 256
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var glucoseValueStatusRaw: Int = 0
    public private(set) var cgmDataTypeRaw: Int = 0
    public private(set) var rate: Int = 0
    public private(set) var algorithmState: Int = 0
    public private(set) var rssi: Int = 0
    public private(set) var currentGlucoseDisplayValue: Int = 0
    public private(set) var timeStampSeconds: Int = 0
    public private(set) var egvInfoBitmaskRaw: Int = 0
    public private(set) var interval: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        glucoseValueStatusRaw = Bytes.readShort(raw, 10)
        cgmDataTypeRaw = Int(raw[12])
        rate = Int(raw[13])
        algorithmState = Int(raw[14])
        rssi = Int(raw[15])
        currentGlucoseDisplayValue = Bytes.readShort(raw, 16)
        timeStampSeconds = Int(Bytes.readUint32(raw, 18))
        egvInfoBitmaskRaw = Bytes.readShort(raw, 22)
        interval = Int(raw[24])
    }
}

// MARK: - Alarms / alerts

/// Alarm Activated — history-log event (typeId 5).
public struct AlarmActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 5
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alarmId: Int = 0
    public private(set) var faultLocatorData: Int = 0
    public private(set) var param1: Int = 0
    public private(set) var param2: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alarmId = Int(Bytes.readUint32(raw, 10))
        faultLocatorData = Int(Bytes.readUint32(raw, 14))
        param1 = Int(Bytes.readUint32(raw, 18))
        param2 = Bytes.readFloat(raw, 22)
    }
}

/// Alert Activated — history-log event (typeId 4).
public struct AlertActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 4
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public private(set) var faultLocatorData: Int = 0
    public private(set) var param1: Int = 0
    public private(set) var param2: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
        faultLocatorData = Int(Bytes.readUint32(raw, 14))
        param1 = Int(Bytes.readUint32(raw, 18))
        param2 = Bytes.readFloat(raw, 22)
    }
}

/// Alarm Cleared — history-log event (typeId 28).
public struct AlarmClearedHistoryLog: HistoryLogEvent {
    public static let typeId = 28
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alarmId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alarmId = Int(Bytes.readUint32(raw, 10))
    }
}

// MARK: - Pumping / cartridge / cannula

/// Pumping Resumed — history-log event (typeId 12).
public struct PumpingResumedHistoryLog: HistoryLogEvent {
    public static let typeId = 12
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var insulinAmount: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        insulinAmount = Bytes.readShort(raw, 14)
    }
}

/// Pumping Suspended — history-log event (typeId 11).
public struct PumpingSuspendedHistoryLog: HistoryLogEvent {
    public static let typeId = 11
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var insulinAmount: Int = 0
    public private(set) var reasonId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        insulinAmount = Bytes.readShort(raw, 14)
        reasonId = Int(raw[16])
    }
}

/// Cartridge Filled — history-log event (typeId 33).
public struct CartridgeFilledHistoryLog: HistoryLogEvent {
    public static let typeId = 33
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var insulinDisplay: Int = 0
    public private(set) var insulinActual: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        insulinDisplay = Int(Bytes.readUint32(raw, 10))
        insulinActual = Bytes.readFloat(raw, 14)
    }
}

/// Cannula Filled — history-log event (typeId 61).
public struct CannulaFilledHistoryLog: HistoryLogEvent {
    public static let typeId = 61
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var primeSize: Float = 0
    public private(set) var completionStatus: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        primeSize = Bytes.readFloat(raw, 10)
        completionStatus = Int(Bytes.readUint32(raw, 14))
    }
}

/// Tubing Filled — history-log event (typeId 63).
public struct TubingFilledHistoryLog: HistoryLogEvent {
    public static let typeId = 63
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var primeSize: Float = 0
    public private(set) var completionStatus: Int = 0
    public private(set) var position: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        primeSize = Bytes.readFloat(raw, 10)
        completionStatus = Int(Bytes.readUint32(raw, 14))
        position = Int(Bytes.readUint32(raw, 18))
    }
}

// MARK: - Additional oracle-verified events (generated)

/// Alert Cleared — history-log event (typeId 26). Ported from AlertClearedHistoryLog.java.
public struct AlertClearedHistoryLog: HistoryLogEvent {
    public static let typeId = 26
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public private(set) var faultLocatorData: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
        faultLocatorData = Int(Bytes.readUint32(raw, 14))
    }
}

/// Arm Init — history-log event (typeId 99). Ported from ArmInitHistoryLog.java.
public struct ArmInitHistoryLog: HistoryLogEvent {
    public static let typeId = 99
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var version: Int = 0
    public private(set) var configABits: Int = 0
    public private(set) var configBBits: Int = 0
    public private(set) var numLogEntries: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        version = Int(Bytes.readUint32(raw, 10))
        configABits = Int(Bytes.readUint32(raw, 14))
        configBBits = Int(Bytes.readUint32(raw, 18))
        numLogEntries = Int(Bytes.readUint32(raw, 22))
    }
}

/// Basal Delivery — history-log event (typeId 279). Ported from BasalDeliveryHistoryLog.java.
public struct BasalDeliveryHistoryLog: HistoryLogEvent {
    public static let typeId = 279
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var commandedRateSource: Int = 0
    public private(set) var commandedRate: Int = 0
    public private(set) var profileBasalRate: Int = 0
    public private(set) var algorithmRate: Int = 0
    public private(set) var tempRate: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        commandedRateSource = Bytes.readShort(raw, 10)
        commandedRate = Bytes.readShort(raw, 14)
        profileBasalRate = Bytes.readShort(raw, 16)
        algorithmRate = Bytes.readShort(raw, 18)
        tempRate = Bytes.readShort(raw, 20)
    }
}

/// CGM Alert Ack B — history-log event (typeId 371). Ported from CgmAlertAckDexHistoryLog.java.
public struct CgmAlertAckDexHistoryLog: HistoryLogEvent {
    public static let typeId = 371
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM Alert Activated B — history-log event (typeId 369). Ported from CgmAlertActivatedDexHistoryLog.java.
public struct CgmAlertActivatedDexHistoryLog: HistoryLogEvent {
    public static let typeId = 369
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CgmAlertActivatedFsl2HistoryLog — history-log event (typeId 460). Ported from CgmAlertActivatedFsl2HistoryLog.java.
public struct CgmAlertActivatedFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 460
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM Alert Activated — history-log event (typeId 171). Ported from CgmAlertActivatedHistoryLog.java.
public struct CgmAlertActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 171
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public private(set) var faultLocatorData: Int = 0
    public private(set) var param1: Int = 0
    public private(set) var param2: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
        faultLocatorData = Int(Bytes.readUint32(raw, 14))
        param1 = Int(Bytes.readUint32(raw, 18))
        param2 = Bytes.readFloat(raw, 22)
    }
}

/// CGM Alert Cleared B — history-log event (typeId 370). Ported from CgmAlertClearedDexHistoryLog.java.
public struct CgmAlertClearedDexHistoryLog: HistoryLogEvent {
    public static let typeId = 370
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CgmAlertClearedFsl2HistoryLog — history-log event (typeId 461). Ported from CgmAlertClearedFsl2HistoryLog.java.
public struct CgmAlertClearedFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 461
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM Alert Cleared — history-log event (typeId 172). Ported from CgmAlertClearedHistoryLog.java.
public struct CgmAlertClearedHistoryLog: HistoryLogEvent {
    public static let typeId = 172
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM Calibration GX — history-log event (typeId 210). Ported from CgmCalibrationGxHistoryLog.java.
public struct CgmCalibrationGxHistoryLog: HistoryLogEvent {
    public static let typeId = 210
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var value: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        value = Bytes.readShort(raw, 10)
    }
}

/// CGM Calibration — history-log event (typeId 160). Ported from CgmCalibrationHistoryLog.java.
public struct CgmCalibrationHistoryLog: HistoryLogEvent {
    public static let typeId = 160
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentTime: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var calTimestamp: Int = 0
    public private(set) var value: Int = 0
    public private(set) var currentDisplayValue: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentTime = Int(Bytes.readUint32(raw, 10))
        timestamp = Int(Bytes.readUint32(raw, 14))
        calTimestamp = Int(Bytes.readUint32(raw, 18))
        value = Bytes.readShort(raw, 22)
        currentDisplayValue = Bytes.readShort(raw, 24)
    }
}

/// CgmDataFsl2HistoryLog — history-log event (typeId 372). Ported from CgmDataFsl2HistoryLog.java.
public struct CgmDataFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 372
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var status: Int = 0
    public private(set) var type: Int = 0
    public private(set) var rate: Int = 0
    public private(set) var rssi: Int = 0
    public private(set) var value: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var transmitterTimestamp: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        status = Bytes.readShort(raw, 10)
        type = Int(raw[12])
        rate = Int(raw[13])
        rssi = Int(raw[15])
        value = Bytes.readShort(raw, 16)
        timestamp = Int(Bytes.readUint32(raw, 18))
        transmitterTimestamp = Int(Bytes.readUint32(raw, 22))
    }
}

/// CgmDataFsl3HistoryLog — history-log event (typeId 480). Ported from CgmDataFsl3HistoryLog.java.
public struct CgmDataFsl3HistoryLog: HistoryLogEvent {
    public static let typeId = 480
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var status: Int = 0
    public private(set) var type: Int = 0
    public private(set) var rate: Int = 0
    public private(set) var rssi: Int = 0
    public private(set) var value: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var transmitterTimestamp: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        status = Bytes.readShort(raw, 10)
        type = Int(raw[12])
        rate = Int(raw[13])
        rssi = Int(raw[15])
        value = Bytes.readShort(raw, 16)
        timestamp = Int(Bytes.readUint32(raw, 18))
        transmitterTimestamp = Int(Bytes.readUint32(raw, 22))
    }
}

/// CGM GX Data Sample — history-log event (typeId 211). Ported from CgmDataGxHistoryLog.java.
public struct CgmDataGxHistoryLog: HistoryLogEvent {
    public static let typeId = 211
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var status: Int = 0
    public private(set) var type: Int = 0
    public private(set) var rate: Int = 0
    public private(set) var rssi: Int = 0
    public private(set) var value: Int = 0
    public private(set) var timestamp: Int = 0
    public private(set) var transmitterTimestamp: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        status = Bytes.readShort(raw, 10)
        type = Int(raw[12])
        rate = Int(raw[13])
        rssi = Int(raw[15])
        value = Bytes.readShort(raw, 16)
        timestamp = Int(Bytes.readUint32(raw, 18))
        transmitterTimestamp = Int(Bytes.readUint32(raw, 22))
    }
}

/// CGM Data Sample — history-log event (typeId 151). Ported from CgmDataSampleHistoryLog.java.
public struct CgmDataSampleHistoryLog: HistoryLogEvent {
    public static let typeId = 151
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var status: Int = 0
    public private(set) var value: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        status = Bytes.readShort(raw, 10)
        value = Bytes.readShort(raw, 19)
    }
}

/// CGM Join Session FSL2 — history-log event (typeId 406). Ported from CgmJoinSessionFsl2HistoryLog.java.
public struct CgmJoinSessionFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 406
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CgmJoinSessionFsl3HistoryLog — history-log event (typeId 477). Ported from CgmJoinSessionFsl3HistoryLog.java.
public struct CgmJoinSessionFsl3HistoryLog: HistoryLogEvent {
    public static let typeId = 477
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Join Session G7 — history-log event (typeId 394). Ported from CgmJoinSessionG7HistoryLog.java.
public struct CgmJoinSessionG7HistoryLog: HistoryLogEvent {
    public static let typeId = 394
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var cgmTimestamp: Int = 0
    public private(set) var sessionSignature: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        cgmTimestamp = Int(Bytes.readUint32(raw, 10))
        sessionSignature = Int(Bytes.readUint32(raw, 14))
    }
}

/// CGM Join Session GX — history-log event (typeId 213). Ported from CgmJoinSessionHistoryLog.java.
public struct CgmJoinSessionHistoryLog: HistoryLogEvent {
    public static let typeId = 213
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentTransmitterTime: Int = 0
    public private(set) var sessionStartTime: Int = 0
    public private(set) var sessionJoinReasonRaw: Int = 0
    public private(set) var sessionDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentTransmitterTime = Int(Bytes.readUint32(raw, 10))
        sessionStartTime = Int(Bytes.readUint32(raw, 14))
        sessionJoinReasonRaw = Int(raw[24])
        sessionDuration = Int(raw[25])
    }
}

/// CGM Start Session FSL2 — history-log event (typeId 404). Ported from CgmStartSessionFsl2HistoryLog.java.
public struct CgmStartSessionFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 404
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Start Session GX — history-log event (typeId 212). Ported from CgmStartSessionHistoryLog.java.
public struct CgmStartSessionHistoryLog: HistoryLogEvent {
    public static let typeId = 212
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentTransmitterTime: Int = 0
    public private(set) var sessionStartTime: Int = 0
    public private(set) var sessionDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentTransmitterTime = Int(Bytes.readUint32(raw, 10))
        sessionStartTime = Int(Bytes.readUint32(raw, 14))
        sessionDuration = Int(raw[25])
    }
}

/// CGM Stop Session FSL2 — history-log event (typeId 405). Ported from CgmStopSessionFsl2HistoryLog.java.
public struct CgmStopSessionFsl2HistoryLog: HistoryLogEvent {
    public static let typeId = 405
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CgmStopSessionFsl3HistoryLog — history-log event (typeId 486). Ported from CgmStopSessionFsl3HistoryLog.java.
public struct CgmStopSessionFsl3HistoryLog: HistoryLogEvent {
    public static let typeId = 486
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CgmStopSessionG7HistoryLog — history-log event (typeId 447). Ported from CgmStopSessionG7HistoryLog.java.
public struct CgmStopSessionG7HistoryLog: HistoryLogEvent {
    public static let typeId = 447
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentTransmitterTime: Int = 0
    public private(set) var sessionStartTime: Int = 0
    public private(set) var sessionStopTime: Int = 0
    public private(set) var stopSessionCode: Int = 0
    public private(set) var sessionStopReason: Int = 0
    public private(set) var sessionDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentTransmitterTime = Int(Bytes.readUint32(raw, 10))
        sessionStartTime = Int(Bytes.readUint32(raw, 14))
        sessionStopTime = Int(Bytes.readUint32(raw, 18))
        stopSessionCode = Int(raw[23])
        sessionStopReason = Int(raw[24])
        sessionDuration = Int(raw[25])
    }
}

/// CGM Stop Session GX — history-log event (typeId 214). Ported from CgmStopSessionHistoryLog.java.
public struct CgmStopSessionHistoryLog: HistoryLogEvent {
    public static let typeId = 214
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentTransmitterTime: Int = 0
    public private(set) var sessionStartTime: Int = 0
    public private(set) var sessionStopTime: Int = 0
    public private(set) var sessionStopReasonRaw: Int = 0
    public private(set) var sessionDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentTransmitterTime = Int(Bytes.readUint32(raw, 10))
        sessionStartTime = Int(Bytes.readUint32(raw, 14))
        sessionStopTime = Int(Bytes.readUint32(raw, 18))
        sessionStopReasonRaw = Int(raw[24])
        sessionDuration = Int(raw[25])
    }
}

/// ControlIQPcmChangeHistoryLog — history-log event (typeId 230). Ported from ControlIQPcmChangeHistoryLog.java.
public struct ControlIQPcmChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 230
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentPcmId: Int = 0
    public private(set) var previousPcmId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentPcmId = Int(raw[10])
        previousPcmId = Int(raw[11])
    }
}

/// ControlIQ User Mode Change — history-log event (typeId 229). Ported from ControlIQUserModeChangeHistoryLog.java.
public struct ControlIQUserModeChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 229
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var currentUserMode: Int = 0
    public private(set) var previousUserMode: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        currentUserMode = Int(raw[10])
        previousUserMode = Int(raw[11])
    }
}

/// Correction Declined — history-log event (typeId 93). Ported from CorrectionDeclinedHistoryLog.java.
public struct CorrectionDeclinedHistoryLog: HistoryLogEvent {
    public static let typeId = 93
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bg: Int = 0
    public private(set) var bolusId: Int = 0
    public private(set) var iob: Float = 0
    public private(set) var targetBg: Int = 0
    public private(set) var isf: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bg = Bytes.readShort(raw, 10)
        bolusId = Bytes.readShort(raw, 12)
        iob = Bytes.readFloat(raw, 14)
        targetBg = Bytes.readShort(raw, 18)
        isf = Bytes.readShort(raw, 20)
    }
}

/// Daily Status — history-log event (typeId 313). Ported from DailyStatusHistoryLog.java.
public struct DailyStatusHistoryLog: HistoryLogEvent {
    public static let typeId = 313
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var sensorType: Int = 0
    public private(set) var userMode: Int = 0
    public private(set) var pumpControlState: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        sensorType = Int(raw[11])
        userMode = Int(raw[12])
        pumpControlState = Int(raw[13])
    }
}

/// Data Log Corruption — history-log event (typeId 60). Ported from DataLogCorruptionHistoryLog.java.
public struct DataLogCorruptionHistoryLog: HistoryLogEvent {
    public static let typeId = 60
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var block: Int = 0
    public private(set) var reason: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        block = Int(Bytes.readUint32(raw, 10))
        reason = Int(raw[17])
    }
}

/// Date Change — history-log event (typeId 14). Ported from DateChangeHistoryLog.java.
public struct DateChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 14
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var datePrior: Int = 0
    public private(set) var dateAfter: Int = 0
    public private(set) var rawRTCTime: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        datePrior = Int(Bytes.readUint32(raw, 10))
        dateAfter = Int(Bytes.readUint32(raw, 14))
        rawRTCTime = Int(Bytes.readUint32(raw, 18))
    }
}

/// CGM Data G7 — history-log event (typeId 399). Ported from DexcomG7CGMHistoryLog.java.
public struct DexcomG7CGMHistoryLog: HistoryLogEvent {
    public static let typeId = 399
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var glucoseValueStatusRaw: Int = 0
    public private(set) var cgmDataTypeRaw: Int = 0
    public private(set) var rate: Int = 0
    public private(set) var algorithmStateRaw: Int = 0
    public private(set) var rssi: Int = 0
    public private(set) var currentGlucoseDisplayValue: Int = 0
    public private(set) var egvTimestamp: Int = 0
    public private(set) var egvInfoBitmaskRaw: Int = 0
    public private(set) var interval: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        glucoseValueStatusRaw = Bytes.readShort(raw, 10)
        cgmDataTypeRaw = Int(raw[12])
        rate = Int(raw[13])
        algorithmStateRaw = Int(raw[14])
        rssi = Int(raw[15])
        currentGlucoseDisplayValue = Bytes.readShort(raw, 16)
        egvTimestamp = Int(Bytes.readUint32(raw, 18))
        egvInfoBitmaskRaw = Bytes.readShort(raw, 22)
        interval = Int(raw[24])
    }
}

/// Factory Reset — history-log event (typeId 82). Ported from FactoryResetHistoryLog.java.
public struct FactoryResetHistoryLog: HistoryLogEvent {
    public static let typeId = 82
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Hypo Minimizer Resume — history-log event (typeId 199). Ported from HypoMinimizerResumeHistoryLog.java.
public struct HypoMinimizerResumeHistoryLog: HistoryLogEvent {
    public static let typeId = 199
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var reason: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        reason = Int(Bytes.readUint32(raw, 10))
    }
}

/// Hypo Minimizer Suspend — history-log event (typeId 198). Ported from HypoMinimizerSuspendHistoryLog.java.
public struct HypoMinimizerSuspendHistoryLog: HistoryLogEvent {
    public static let typeId = 198
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// IdpActionHistoryLog — history-log event (typeId 69). Ported from IdpActionHistoryLog.java.
public struct IdpActionHistoryLog: HistoryLogEvent {
    public static let typeId = 69
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var idp: Int = 0
    public private(set) var status: Int = 0
    public private(set) var sourceIdp: Int = 0
    public private(set) var name: String = ""
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        idp = Int(raw[10])
        status = Int(raw[11])
        sourceIdp = Int(raw[12])
        name = Bytes.readString(raw, 18, 8)
    }
}

/// IdpActionMsg2HistoryLog — history-log event (typeId 57). Ported from IdpActionMsg2HistoryLog.java.
public struct IdpActionMsg2HistoryLog: HistoryLogEvent {
    public static let typeId = 57
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var idp: Int = 0
    public private(set) var name: String = ""
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        idp = Int(raw[10])
        name = Bytes.readString(raw, 18, 8)
    }
}

/// IDP Bolus — history-log event (typeId 70). Ported from IdpBolusHistoryLog.java.
public struct IdpBolusHistoryLog: HistoryLogEvent {
    public static let typeId = 70
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var idp: Int = 0
    public private(set) var modification: Int = 0
    public private(set) var bolusStatus: Int = 0
    public private(set) var insulinDuration: Int = 0
    public private(set) var maxBolusSize: Int = 0
    public private(set) var bolusEntryType: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        idp = Int(raw[10])
        modification = Int(raw[11])
        bolusStatus = Int(raw[12])
        insulinDuration = Bytes.readShort(raw, 14)
        maxBolusSize = Bytes.readShort(raw, 16)
        bolusEntryType = Int(raw[18])
    }
}

/// IDP List — history-log event (typeId 71). Ported from IdpListHistoryLog.java.
public struct IdpListHistoryLog: HistoryLogEvent {
    public static let typeId = 71
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var numProfiles: Int = 0
    public private(set) var slot1: Int = 0
    public private(set) var slot2: Int = 0
    public private(set) var slot3: Int = 0
    public private(set) var slot4: Int = 0
    public private(set) var slot5: Int = 0
    public private(set) var slot6: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        numProfiles = Int(raw[10])
        slot1 = Int(raw[14])
        slot2 = Int(raw[15])
        slot3 = Int(raw[16])
        slot4 = Int(raw[17])
        slot5 = Int(raw[18])
        slot6 = Int(raw[19])
    }
}

/// IdpTimeDependentSegmentHistoryLog — history-log event (typeId 68). Ported from IdpTimeDependentSegmentHistoryLog.java.
public struct IdpTimeDependentSegmentHistoryLog: HistoryLogEvent {
    public static let typeId = 68
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var idp: Int = 0
    public private(set) var status: Int = 0
    public private(set) var segmentIndex: Int = 0
    public private(set) var modificationType: Int = 0
    public private(set) var startTime: Int = 0
    public private(set) var basalRate: Int = 0
    public private(set) var isf: Int = 0
    public private(set) var targetBg: Int = 0
    public private(set) var carbRatio: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        idp = Int(raw[10])
        status = Int(raw[11])
        segmentIndex = Int(raw[12])
        modificationType = Int(raw[13])
        startTime = Bytes.readShort(raw, 14)
        basalRate = Bytes.readShort(raw, 16)
        isf = Bytes.readShort(raw, 18)
        targetBg = Int(Bytes.readUint32(raw, 20))
        carbRatio = Int(raw[24])
    }
}

/// Log Erased — history-log event (typeId 0). Ported from LogErasedHistoryLog.java.
public struct LogErasedHistoryLog: HistoryLogEvent {
    public static let typeId = 0
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var numErased: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        numErased = Int(Bytes.readUint32(raw, 10))
    }
}

/// Malfunction Activated — history-log event (typeId 6). Ported from MalfunctionHistoryLog.java.
public struct MalfunctionHistoryLog: HistoryLogEvent {
    public static let typeId = 6
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var malfId: Int = 0
    public private(set) var faultLocatorData: Int = 0
    public private(set) var param1: Int = 0
    public private(set) var param2: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        malfId = Int(Bytes.readUint32(raw, 10))
        faultLocatorData = Int(Bytes.readUint32(raw, 14))
        param1 = Int(Bytes.readUint32(raw, 18))
        param2 = Bytes.readFloat(raw, 22)
    }
}

/// New Day — history-log event (typeId 90). Ported from NewDayHistoryLog.java.
public struct NewDayHistoryLog: HistoryLogEvent {
    public static let typeId = 90
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var commandedBasalRate: Float = 0
    public private(set) var featuresBitmask: Int = 0
    public private(set) var featureBitmaskIndex: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        commandedBasalRate = Bytes.readFloat(raw, 10)
        featuresBitmask = Int(Bytes.readUint32(raw, 14))
        featureBitmaskIndex = Int(Bytes.readUint32(raw, 18))
    }
}

/// Param Global Settings — history-log event (typeId 74). Ported from ParamChangeGlobalSettingsHistoryLog.java.
public struct ParamChangeGlobalSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 74
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var modifiedData: Int = 0
    public private(set) var qbDataStatus: Int = 0
    public private(set) var qbActive: Int = 0
    public private(set) var qbDataEntryType: Int = 0
    public private(set) var qbIncrementUnits: Int = 0
    public private(set) var qbIncrementCarbs: Int = 0
    public private(set) var buttonVolume: Int = 0
    public private(set) var qbVolume: Int = 0
    public private(set) var bolusVolume: Int = 0
    public private(set) var reminderVolume: Int = 0
    public private(set) var alertVolume: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        modifiedData = Int(raw[10])
        qbDataStatus = Int(raw[11])
        qbActive = Int(raw[12])
        qbDataEntryType = Int(raw[13])
        qbIncrementUnits = Bytes.readShort(raw, 14)
        qbIncrementCarbs = Bytes.readShort(raw, 16)
        buttonVolume = Int(raw[18])
        qbVolume = Int(raw[19])
        bolusVolume = Int(raw[20])
        reminderVolume = Int(raw[21])
        alertVolume = Int(raw[22])
    }
}

/// Param Pump Settings — history-log event (typeId 73). Ported from ParamChangePumpSettingsHistoryLog.java.
public struct ParamChangePumpSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 73
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var modification: Int = 0
    public private(set) var status: Int = 0
    public private(set) var lowInsulinThreshold: Int = 0
    public private(set) var cannulaPrimeSize: Int = 0
    public private(set) var isFeatureLocked: Int = 0
    public private(set) var autoShutdownEnabled: Int = 0
    public private(set) var oledTimeout: Int = 0
    public private(set) var autoShutdownDuration: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        modification = Int(raw[10])
        status = Bytes.readShort(raw, 12)
        lowInsulinThreshold = Int(raw[14])
        cannulaPrimeSize = Int(raw[15])
        isFeatureLocked = Int(raw[16])
        autoShutdownEnabled = Int(raw[17])
        oledTimeout = Int(raw[19])
        autoShutdownDuration = Bytes.readShort(raw, 20)
    }
}

/// Reminder Parameter Change — history-log event (typeId 97). Ported from ParamChangeRemSettingsHistoryLog.java.
public struct ParamChangeRemSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 97
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var modification: Int = 0
    public private(set) var status: Int = 0
    public private(set) var lowBgThreshold: Int = 0
    public private(set) var highBgThreshold: Int = 0
    public private(set) var siteChangeDays: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        modification = Int(raw[10])
        status = Int(raw[11])
        lowBgThreshold = Bytes.readShort(raw, 14)
        highBgThreshold = Bytes.readShort(raw, 16)
        siteChangeDays = Int(raw[18])
    }
}

/// Param Reminder — history-log event (typeId 96). Ported from ParamChangeReminderHistoryLog.java.
public struct ParamChangeReminderHistoryLog: HistoryLogEvent {
    public static let typeId = 96
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var modification: Int = 0
    public private(set) var reminderId: Int = 0
    public private(set) var status: Int = 0
    public private(set) var enable: Int = 0
    public private(set) var frequencyMinutes: Int = 0
    public private(set) var startTime: Int = 0
    public private(set) var endTime: Int = 0
    public private(set) var activeDays: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        modification = Int(raw[10])
        reminderId = Int(raw[11])
        status = Int(raw[12])
        enable = Int(raw[13])
        frequencyMinutes = Int(Bytes.readUint32(raw, 14))
        startTime = Bytes.readShort(raw, 18)
        endTime = Bytes.readShort(raw, 20)
        activeDays = Int(raw[22])
    }
}

/// PLGS Periodic — history-log event (typeId 140). Ported from PlgsPeriodicHistoryLog.java.
public struct PlgsPeriodicHistoryLog: HistoryLogEvent {
    public static let typeId = 140
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Shelf Mode — history-log event (typeId 53). Ported from ShelfModeHistoryLog.java.
public struct ShelfModeHistoryLog: HistoryLogEvent {
    public static let typeId = 53
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var msecSinceReset: Int = 0
    public private(set) var lipoIbc: Int = 0
    public private(set) var lipoAbc: Int = 0
    public private(set) var lipoCurrent: Int = 0
    public private(set) var lipoRemCap: Int = 0
    public private(set) var lipoMv: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        msecSinceReset = Int(Bytes.readUint32(raw, 10))
        lipoIbc = Int(raw[14])
        lipoAbc = Int(raw[15])
        lipoCurrent = Bytes.readShort(raw, 16)
        lipoRemCap = Int(Bytes.readUint32(raw, 18))
        lipoMv = Int(Bytes.readUint32(raw, 22))
    }
}

/// Time Change — history-log event (typeId 13). Ported from TimeChangedHistoryLog.java.
public struct TimeChangedHistoryLog: HistoryLogEvent {
    public static let typeId = 13
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var timePrior: Int = 0
    public private(set) var timeAfter: Int = 0
    public private(set) var rawRTC: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        timePrior = Int(Bytes.readUint32(raw, 10))
        timeAfter = Int(Bytes.readUint32(raw, 14))
        rawRTC = Int(Bytes.readUint32(raw, 18))
    }
}

/// Update Status — history-log event (typeId 203). Ported from UpdateStatusHistoryLog.java.
public struct UpdateStatusHistoryLog: HistoryLogEvent {
    public static let typeId = 203
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var metadataAndVersionStatus: Int = 0
    public private(set) var swUpdateStatus: Int = 0
    public private(set) var fileDlAndSideloadStatus: Int = 0
    public private(set) var fullDlAndCrcStatus: Int = 0
    public private(set) var updateSuccessful: Int = 0
    public private(set) var externalFlashStatus: Int = 0
    public private(set) var swPartNum: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        metadataAndVersionStatus = Bytes.readShort(raw, 10)
        swUpdateStatus = Bytes.readShort(raw, 12)
        fileDlAndSideloadStatus = Bytes.readShort(raw, 14)
        fullDlAndCrcStatus = Bytes.readShort(raw, 16)
        updateSuccessful = Int(raw[19])
        externalFlashStatus = Bytes.readShort(raw, 20)
        swPartNum = Int(Bytes.readUint32(raw, 22))
    }
}

/// USB Connected — history-log event (typeId 36). Ported from UsbConnectedHistoryLog.java.
public struct UsbConnectedHistoryLog: HistoryLogEvent {
    public static let typeId = 36
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var negotiatedCurrentmA: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        negotiatedCurrentmA = Bytes.readFloat(raw, 10)
    }
}

/// USB Disconnected — history-log event (typeId 37). Ported from UsbDisconnectedHistoryLog.java.
public struct UsbDisconnectedHistoryLog: HistoryLogEvent {
    public static let typeId = 37
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var negotiatedCurrentMilliAmps: Float = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        negotiatedCurrentMilliAmps = Bytes.readFloat(raw, 10)
    }
}

/// USB Enumerated — history-log event (typeId 67). Ported from UsbEnumeratedHistoryLog.java.
public struct UsbEnumeratedHistoryLog: HistoryLogEvent {
    public static let typeId = 67
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var negotiatedCurrentMilliAmps: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        negotiatedCurrentMilliAmps = Int(raw[10])
    }
}

/// Version Info — history-log event (typeId 191). Ported from VersionInfoHistoryLog.java.
public struct VersionInfoHistoryLog: HistoryLogEvent {
    public static let typeId = 191
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var version: Int = 0
    public private(set) var configABits: Int = 0
    public private(set) var configBBits: Int = 0
    public private(set) var armCrc: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        version = Int(Bytes.readUint32(raw, 10))
        configABits = Int(Bytes.readUint32(raw, 14))
        configBBits = Int(Bytes.readUint32(raw, 18))
        armCrc = Bytes.readShort(raw, 24)
    }
}

/// Versions A — history-log event (typeId 307). Ported from VersionsAHistoryLog.java.
public struct VersionsAHistoryLog: HistoryLogEvent {
    public static let typeId = 307
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var armPartNumber: Int = 0
    public private(set) var armSwVersion: Int = 0
    public private(set) var blePartNumber: Int = 0
    public private(set) var bleSwVersion: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        armPartNumber = Int(Bytes.readUint32(raw, 10))
        armSwVersion = Int(Bytes.readUint32(raw, 14))
        blePartNumber = Int(Bytes.readUint32(raw, 18))
        bleSwVersion = Int(Bytes.readUint32(raw, 22))
    }
}

// MARK: - Remaining events (swift-dispatch only; not in oracle LOG_MESSAGE_TYPES)

/// AA Exercise Choice Change — history-log event (typeId 319). Ported from AAExerciseChoiceChangeHistoryLog.java.
public struct AAExerciseChoiceChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 319
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA Exercise Time Change — history-log event (typeId 318). Ported from AAExerciseTimeChangeHistoryLog.java.
public struct AAExerciseTimeChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 318
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA TDI Estimate Change — history-log event (typeId 332). Ported from AATdiEstChangeHistoryLog.java.
public struct AATdiEstChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 332
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA Auto Bolus Rejected — history-log event (typeId 288). Ported from AaAutoBolusRejectedHistoryLog.java.
public struct AaAutoBolusRejectedHistoryLog: HistoryLogEvent {
    public static let typeId = 288
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA Delivery Status Change — history-log event (typeId 238). Ported from AaDeliveryStatusChangeHistoryLog.java.
public struct AaDeliveryStatusChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 238
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA Enable Setting Change — history-log event (typeId 244). Ported from AaEnableSettingChangeHistoryLog.java.
public struct AaEnableSettingChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 244
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var enabled: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        enabled = Int(raw[10])
    }
}

/// AA Sleep Schedule Change — history-log event (typeId 235). Ported from AaSleepScheduleChangeHistoryLog.java.
public struct AaSleepScheduleChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 235
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA TDI Setting Change — history-log event (typeId 245). Ported from AaTdiSettingChangeHistoryLog.java.
public struct AaTdiSettingChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 245
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// AA Weight Setting Change — history-log event (typeId 246). Ported from AaWeightSettingChangeHistoryLog.java.
public struct AaWeightSettingChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 246
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Alarm Ack — history-log event (typeId 8). Ported from AlarmAckHistoryLog.java.
public struct AlarmAckHistoryLog: HistoryLogEvent {
    public static let typeId = 8
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alarmId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alarmId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Alert Ack — history-log event (typeId 27). Ported from AlertAckHistoryLog.java.
public struct AlertAckHistoryLog: HistoryLogEvent {
    public static let typeId = 27
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Basal IQ Settings Change — history-log event (typeId 142). Ported from BasalIqSettingsChangeHistoryLog.java.
public struct BasalIqSettingsChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 142
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Cartridge Inserted — history-log event (typeId 32). Ported from CartridgeInsertedHistoryLog.java.
public struct CartridgeInsertedHistoryLog: HistoryLogEvent {
    public static let typeId = 32
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Cartridge Removed — history-log event (typeId 31). Ported from CartridgeRemovedHistoryLog.java.
public struct CartridgeRemovedHistoryLog: HistoryLogEvent {
    public static let typeId = 31
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Alert Ack — history-log event (typeId 173). Ported from CgmAlertAckHistoryLog.java.
public struct CgmAlertAckHistoryLog: HistoryLogEvent {
    public static let typeId = 173
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertId = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM ANNU Settings — history-log event (typeId 157). Ported from CgmAnnuSettingsHistoryLog.java.
public struct CgmAnnuSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 157
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CgmBleCalibrationEvtG7HistoryLog — history-log event (typeId 439). Ported from CgmBleCalibrationEvtG7HistoryLog.java.
public struct CgmBleCalibrationEvtG7HistoryLog: HistoryLogEvent {
    public static let typeId = 439
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var isCalibrationAccepted: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        isCalibrationAccepted = raw[10] != 0
    }
}

/// CgmCalibrationG7HistoryLog — history-log event (typeId 438). Ported from CgmCalibrationG7HistoryLog.java.
public struct CgmCalibrationG7HistoryLog: HistoryLogEvent {
    public static let typeId = 438
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var bg: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        bg = Int(Bytes.readUint32(raw, 10))
    }
}

/// CGM FRA Settings — history-log event (typeId 168). Ported from CgmFraSettingsHistoryLog.java.
public struct CgmFraSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 168
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertLevel: Int = 0
    public private(set) var repeatDuration: Int = 0
    public private(set) var isEnabled: Bool = false
    public private(set) var modifiedField: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertLevel = Bytes.readShort(raw, 10)
        repeatDuration = Bytes.readShort(raw, 12)
        isEnabled = raw[14] != 0
        modifiedField = Bytes.readShort(raw, 16)
    }
}

/// CGM HGA Settings — history-log event (typeId 165). Ported from CgmHgaSettingsHistoryLog.java.
public struct CgmHgaSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 165
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertLevel: Int = 0
    public private(set) var repeatDuration: Int = 0
    public private(set) var isEnabled: Bool = false
    public private(set) var modifiedField: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertLevel = Bytes.readShort(raw, 10)
        repeatDuration = Bytes.readShort(raw, 12)
        isEnabled = raw[14] != 0
        modifiedField = Bytes.readShort(raw, 16)
    }
}

/// CgmInactiveG7HistoryLog — history-log event (typeId 441). Ported from CgmInactiveG7HistoryLog.java.
public struct CgmInactiveG7HistoryLog: HistoryLogEvent {
    public static let typeId = 441
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Inactive GX — history-log event (typeId 215). Ported from CgmInactiveGxHistoryLog.java.
public struct CgmInactiveGxHistoryLog: HistoryLogEvent {
    public static let typeId = 215
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM LGA Settings — history-log event (typeId 166). Ported from CgmLgaSettingsHistoryLog.java.
public struct CgmLgaSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 166
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertLevel: Int = 0
    public private(set) var repeatDuration: Int = 0
    public private(set) var isEnabled: Bool = false
    public private(set) var modifiedField: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertLevel = Bytes.readShort(raw, 10)
        repeatDuration = Bytes.readShort(raw, 12)
        isEnabled = raw[14] != 0
        modifiedField = Bytes.readShort(raw, 16)
    }
}

/// CGM OOR Settings — history-log event (typeId 169). Ported from CgmOorSettingsHistoryLog.java.
public struct CgmOorSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 169
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertLevel: Int = 0
    public private(set) var repeatDuration: Int = 0
    public private(set) var isEnabled: Bool = false
    public private(set) var modifiedField: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertLevel = Bytes.readShort(raw, 10)
        repeatDuration = Bytes.readShort(raw, 12)
        isEnabled = raw[14] != 0
        modifiedField = Bytes.readShort(raw, 16)
    }
}

/// CGM Pairing Code G7 — history-log event (typeId 395). Ported from CgmPairingCodeG7HistoryLog.java.
public struct CgmPairingCodeG7HistoryLog: HistoryLogEvent {
    public static let typeId = 395
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var pairingCode: String = ""
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        pairingCode = Bytes.readString(raw, 10, 16)
    }
}

/// CGM Rejoin Session — history-log event (typeId 367). Ported from CgmRejoinSessionHistoryLog.java.
public struct CgmRejoinSessionHistoryLog: HistoryLogEvent {
    public static let typeId = 367
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM RRA Settings — history-log event (typeId 167). Ported from CgmRraSettingsHistoryLog.java.
public struct CgmRraSettingsHistoryLog: HistoryLogEvent {
    public static let typeId = 167
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var alertLevel: Int = 0
    public private(set) var repeatDuration: Int = 0
    public private(set) var isEnabled: Bool = false
    public private(set) var modifiedField: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        alertLevel = Bytes.readShort(raw, 10)
        repeatDuration = Bytes.readShort(raw, 12)
        isEnabled = raw[14] != 0
        modifiedField = Bytes.readShort(raw, 16)
    }
}

/// CGM Sensor Type Change — history-log event (typeId 368). Ported from CgmSensorTypeChangeHistoryLog.java.
public struct CgmSensorTypeChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 368
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Session Type Change — history-log event (typeId 267). Ported from CgmSessionTypeChangeHistoryLog.java.
public struct CgmSessionTypeChangeHistoryLog: HistoryLogEvent {
    public static let typeId = 267
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Start Sensor Request G7 — history-log event (typeId 390). Ported from CgmStartSensorReqG7HistoryLog.java.
public struct CgmStartSensorReqG7HistoryLog: HistoryLogEvent {
    public static let typeId = 390
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Start Session Request GX — history-log event (typeId 217). Ported from CgmStartSessionReqGxHistoryLog.java.
public struct CgmStartSessionReqGxHistoryLog: HistoryLogEvent {
    public static let typeId = 217
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Stop Session Msg 1 — history-log event (typeId 162). Ported from CgmStopSessionMsg1HistoryLog.java.
public struct CgmStopSessionMsg1HistoryLog: HistoryLogEvent {
    public static let typeId = 162
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Stop Session Msg 2 — history-log event (typeId 163). Ported from CgmStopSessionMsg2HistoryLog.java.
public struct CgmStopSessionMsg2HistoryLog: HistoryLogEvent {
    public static let typeId = 163
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CgmStopSessionReqG7HistoryLog — history-log event (typeId 443). Ported from CgmStopSessionReqG7HistoryLog.java.
public struct CgmStopSessionReqG7HistoryLog: HistoryLogEvent {
    public static let typeId = 443
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Stop Session Request GX — history-log event (typeId 218). Ported from CgmStopSessionReqGxHistoryLog.java.
public struct CgmStopSessionReqGxHistoryLog: HistoryLogEvent {
    public static let typeId = 218
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Transmitter ID GX — history-log event (typeId 216). Ported from CgmTransmitterIdGxHistoryLog.java.
public struct CgmTransmitterIdGxHistoryLog: HistoryLogEvent {
    public static let typeId = 216
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Transmitter ID — history-log event (typeId 156). Ported from CgmTransmitterIdHistoryLog.java.
public struct CgmTransmitterIdHistoryLog: HistoryLogEvent {
    public static let typeId = 156
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Transmitter Version GX — history-log event (typeId 220). Ported from CgmTransmitterVersionGxHistoryLog.java.
public struct CgmTransmitterVersionGxHistoryLog: HistoryLogEvent {
    public static let typeId = 220
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// CGM Unexpected GE Alert — history-log event (typeId 187). Ported from CgmUnexpectedGeAlertHistoryLog.java.
public struct CgmUnexpectedGeAlertHistoryLog: HistoryLogEvent {
    public static let typeId = 187
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Confirm Cartridge Filled — history-log event (typeId 41). Ported from ConfirmCartridgeFilledHistoryLog.java.
public struct ConfirmCartridgeFilledHistoryLog: HistoryLogEvent {
    public static let typeId = 41
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Fill Estimate Final — history-log event (typeId 98). Ported from FillEstimateFinalHistoryLog.java.
public struct FillEstimateFinalHistoryLog: HistoryLogEvent {
    public static let typeId = 98
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Malfunction Ack — history-log event (typeId 7). Ported from MalfunctionAckHistoryLog.java.
public struct MalfunctionAckHistoryLog: HistoryLogEvent {
    public static let typeId = 7
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var malfId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        malfId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Prime In Process — history-log event (typeId 348). Ported from PrimeInprocessHistoryLog.java.
public struct PrimeInprocessHistoryLog: HistoryLogEvent {
    public static let typeId = 348
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// Reminder Activated — history-log event (typeId 25). Ported from ReminderActivatedHistoryLog.java.
public struct ReminderActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 25
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var reminderId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        reminderId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Reminder Dismissed — history-log event (typeId 29). Ported from ReminderDismissedHistoryLog.java.
public struct ReminderDismissedHistoryLog: HistoryLogEvent {
    public static let typeId = 29
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var reminderId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        reminderId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Reminder Snoozed — history-log event (typeId 30). Ported from ReminderSnoozedHistoryLog.java.
public struct ReminderSnoozedHistoryLog: HistoryLogEvent {
    public static let typeId = 30
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var reminderId: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        reminderId = Int(Bytes.readUint32(raw, 10))
    }
}

/// Snooze Activated — history-log event (typeId 286). Ported from SnoozeActivatedHistoryLog.java.
public struct SnoozeActivatedHistoryLog: HistoryLogEvent {
    public static let typeId = 286
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// TIPS Error — history-log event (typeId 419). Ported from TipsErrorHistoryLog.java.
public struct TipsErrorHistoryLog: HistoryLogEvent {
    public static let typeId = 419
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public private(set) var messageType: Int = 0
    public private(set) var requestCode: Int = 0
    public private(set) var errorCode: Int = 0
    public private(set) var isDataMasked: Bool = false
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
        messageType = Int(raw[10])
        requestCode = Int(raw[11])
        errorCode = Int(raw[12])
        isDataMasked = raw[13] != 0
    }
}

/// TIPSC Req Prime Cannula — history-log event (typeId 291). Ported from TipscReqPrimeCannulaHistoryLog.java.
public struct TipscReqPrimeCannulaHistoryLog: HistoryLogEvent {
    public static let typeId = 291
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// WUMP Cartridge Filled — history-log event (typeId 301). Ported from WumpCartridgeFilledHistoryLog.java.
public struct WumpCartridgeFilledHistoryLog: HistoryLogEvent {
    public static let typeId = 301
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// WUMP Cartridge Removed — history-log event (typeId 302). Ported from WumpCartridgeRemovedHistoryLog.java.
public struct WumpCartridgeRemovedHistoryLog: HistoryLogEvent {
    public static let typeId = 302
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}

/// WUMP Occlusion Debug — history-log event (typeId 283). Ported from WumpOcclusionDebugHistoryLog.java.
public struct WumpOcclusionDebugHistoryLog: HistoryLogEvent {
    public static let typeId = 283
    public var cargo: [UInt8]
    public private(set) var pumpTimeSec: UInt32 = 0
    public private(set) var sequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 26 else { return }
        pumpTimeSec = Bytes.readUint32(raw, 2)
        sequenceNum = Bytes.readUint32(raw, 6)
    }
}
