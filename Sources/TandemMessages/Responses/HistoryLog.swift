import Foundation

/// History-log responses. `HistoryLogStatusResponse` reports the available sequence-number
/// range; `HistoryLogStreamResponse` carries the actual log entries (each a 26-byte record)
/// streamed after a `HistoryLogRequest`. We parse the CGM (EGV) records out of the stream to
/// backfill the glucose chart; other record types are ignored here.
///
/// Ports of `response/currentStatus/HistoryLogStatusResponse`, `HistoryLogResponse`, and
/// `response/historyLog/HistoryLogStreamResponse` (+ the CGM history-log records).

/// Available history-log range (opcode 59, 12 bytes): count + first/last sequence numbers.
public struct HistoryLogStatusResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 59, size: 12, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var numEntries: UInt32 = 0
    public private(set) var firstSequenceNum: UInt32 = 0
    public private(set) var lastSequenceNum: UInt32 = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        numEntries = Bytes.readUint32(raw, 0)
        firstSequenceNum = Bytes.readUint32(raw, 4)
        lastSequenceNum = Bytes.readUint32(raw, 8)
    }
    public mutating func parse(_ raw: [UInt8]) { self = HistoryLogStatusResponse(cargo: raw) }
}

/// Ack for a `HistoryLogRequest` (opcode 61, 2 bytes). The actual entries arrive as
/// `HistoryLogStreamResponse` frames.
public struct HistoryLogResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 61, size: 2, type: .response, characteristic: .currentStatus)
    public var cargo: [UInt8]
    public private(set) var status: Int = 0
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        if raw.count >= 1 { status = Int(raw[0]) }
    }
    public mutating func parse(_ raw: [UInt8]) { self = HistoryLogResponse(cargo: raw) }
}

/// A single CGM (EGV) reading recovered from a history-log record.
public struct CgmHistoryReading: Sendable, Equatable {
    /// Pump-clock seconds since the Jan 1 2008 epoch (convert with `HistoryLog.jan12008UnixEpoch`).
    public let pumpTimeSec: UInt32
    public let sequenceNum: UInt32
    public let glucoseMgdl: Int
}

/// A completed bolus recovered from a history-log record (`LID_BOLUS_COMPLETED`, typeId 20). Both
/// `deliveredUnits` and `iobUnits` are real insulin units (IEEE floats in the record).
public struct BolusHistoryRecord: Sendable, Equatable {
    public let pumpTimeSec: UInt32
    public let sequenceNum: UInt32
    public let deliveredUnits: Double
    /// Insulin on board at the time of this bolus completion — lets us seed the IOB chart from
    /// history (the pump keeps no separate IOB-over-time log).
    public let iobUnits: Double
    public let completionStatusId: Int
}

/// Shared history-log helpers/constants.
public enum HistoryLog {
    /// Unix epoch seconds for Jan 1 2008 — the base for pump-clock timestamps. Mirrors
    /// `helpers/Dates.JANUARY_1_2008_UNIX_EPOCH`.
    public static let jan12008UnixEpoch: TimeInterval = 1_199_145_600

    /// CGM record type ids that carry a displayable glucose value at the same offsets:
    /// Dexcom G6 (`LID_CGM_DATA_GXB` = 256) and G7 (399).
    static let cgmTypeIds: Set<Int> = [256, 399]

    /// `LID_BOLUS_COMPLETED` — a finished bolus (delivered units + IOB at the time).
    static let bolusCompletedTypeId = 20

    /// Each history-log record is a fixed 26 bytes.
    static let recordSize = 26

    /// Parses one 26-byte record, returning a CGM reading if it's an EGV record. Header layout
    /// (`HistoryLog.parseBase`): typeId = short@0 & 0x0FFF, pumpTimeSec = uint32@2,
    /// sequenceNum = uint32@6. CGM records store the displayed glucose as short@16.
    static func parseCgmRecord(_ raw: [UInt8]) -> CgmHistoryReading? {
        guard raw.count >= recordSize else { return nil }
        let typeId = Bytes.readShort(raw, 0) & 0x0FFF
        guard cgmTypeIds.contains(typeId) else { return nil }
        let mgdl = Bytes.readShort(raw, 16)
        // Guard against sentinel/invalid values (special-high/low or "do not show").
        guard mgdl > 0 && mgdl < 1000 else { return nil }
        return CgmHistoryReading(pumpTimeSec: Bytes.readUint32(raw, 2),
                                 sequenceNum: Bytes.readUint32(raw, 6),
                                 glucoseMgdl: mgdl)
    }

    /// Parses one 26-byte record, returning a completed bolus if it's a `LID_BOLUS_COMPLETED`
    /// record. Layout (`BolusCompletedHistoryLog`): completionStatus = short@10, bolusId = short@12,
    /// iob = float@14, insulinDelivered = float@18, insulinRequested = float@22.
    static func parseBolusRecord(_ raw: [UInt8]) -> BolusHistoryRecord? {
        guard raw.count >= recordSize else { return nil }
        let typeId = Bytes.readShort(raw, 0) & 0x0FFF
        guard typeId == bolusCompletedTypeId else { return nil }
        let delivered = Double(Bytes.readFloat(raw, 18))
        guard delivered > 0, delivered < 100 else { return nil }   // guard sentinel/garbage
        return BolusHistoryRecord(pumpTimeSec: Bytes.readUint32(raw, 2),
                                  sequenceNum: Bytes.readUint32(raw, 6),
                                  deliveredUnits: delivered,
                                  iobUnits: Double(Bytes.readFloat(raw, 14)),
                                  completionStatusId: Bytes.readShort(raw, 10))
    }
}

/// A stream frame of history-log records (opcode 129 / -127, variable size) on the HISTORY_LOG
/// characteristic. Cargo: `[numberOfHistoryLogs, streamId, record0(26)…recordN(26)]`.
public struct HistoryLogStreamResponse: ResponseMessage {
    public static let props = MessageProps(opCode: 129, size: 28, variableSize: true, stream: true,
                                           type: .response, characteristic: .historyLog)
    public var cargo: [UInt8]
    public private(set) var numberOfHistoryLogs: Int = 0
    public private(set) var streamId: Int = 0
    /// The raw 26-byte records in this frame.
    public private(set) var records: [[UInt8]] = []
    public init() { cargo = [] }
    public init(cargo raw: [UInt8]) {
        cargo = raw
        guard raw.count >= 2 else { return }
        numberOfHistoryLogs = Int(raw[0])
        streamId = Int(raw[1])
        var i = 2
        while i + HistoryLog.recordSize <= raw.count {
            records.append(Array(raw[i..<(i + HistoryLog.recordSize)]))
            i += HistoryLog.recordSize
        }
    }
    public mutating func parse(_ raw: [UInt8]) { self = HistoryLogStreamResponse(cargo: raw) }

    /// The CGM readings contained in this frame, in wire order.
    public var cgmReadings: [CgmHistoryReading] {
        records.compactMap { HistoryLog.parseCgmRecord($0) }
    }

    /// The completed boluses contained in this frame, in wire order.
    public var bolusRecords: [BolusHistoryRecord] {
        records.compactMap { HistoryLog.parseBolusRecord($0) }
    }

    /// Every record decoded into a typed `HistoryLogEvent` (A4), in wire order. Unknown typeIds
    /// decode to `UnknownHistoryLog`. This is what a logbook renders.
    public var events: [any HistoryLogEvent] {
        records.map { HistoryLogParser.parse(record: $0) }
    }
}
