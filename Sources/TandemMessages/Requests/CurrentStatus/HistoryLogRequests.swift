import Foundation

/// History-log read requests. The pump keeps a rolling on-device log of events — including CGM
/// (EGV) readings — indexed by sequence number. To backfill glucose beyond what live polling
/// captured (e.g. after the app was disconnected), query the available range with
/// `HistoryLogStatusRequest`, then stream entries with `HistoryLogRequest`; the pump replies
/// with `HistoryLogStreamResponse` frames on the HISTORY_LOG characteristic.
///
/// Ports of `request/currentStatus/HistoryLogStatusRequest` and `HistoryLogRequest`.

/// Empty-cargo request for the available history-log sequence-number range (opcode 58 → 59).
public struct HistoryLogStatusRequest: EmptyCurrentStatusRequest {
    public static let props = MessageProps(opCode: 58, size: 0, type: .request,
                                           characteristic: .currentStatus, responseOpCode: 59)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}

/// Requests `numberOfLogs` history-log entries starting at sequence number `startLog`
/// (opcode 60). The pump acks with `HistoryLogResponse` (61) and streams the entries as
/// `HistoryLogStreamResponse` frames. `numberOfLogs` is a single byte (max 255 per request).
public struct HistoryLogRequest: Message {
    public static let props = MessageProps(opCode: 60, size: 5, type: .request,
                                           characteristic: .currentStatus, responseOpCode: 61)
    public var cargo: [UInt8]
    public private(set) var startLog: UInt32 = 0
    public private(set) var numberOfLogs: Int = 0

    public init() { cargo = [] }

    public init(startLog: UInt32, numberOfLogs: Int) {
        self.startLog = startLog
        self.numberOfLogs = numberOfLogs
        self.cargo = Bytes.combine(Bytes.toUint32(startLog), [UInt8(numberOfLogs & 0xFF)])
    }

    public mutating func parse(_ raw: [UInt8]) {
        let body = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3)
        cargo = body
        startLog = Bytes.readUint32(body, 0)
        numberOfLogs = Int(body[4])
    }
}
