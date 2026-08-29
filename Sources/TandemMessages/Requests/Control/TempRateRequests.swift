import Foundation

/// Sets a temporary basal rate. Signed, **modifies insulin delivery**, Mobi-only. Control-IQ must
/// be off before a temp rate can be set (the pump rejects it otherwise). Port of
/// `request/control/SetTempRateRequest` (opcode -92 / 0xA4).
///
/// Cargo: uint32 duration in milliseconds (minutes × 60 000) + little-endian uint16 percent.
public struct SetTempRateRequest: Message {
    public static let props = MessageProps(
        opCode: 0xA4, size: 6, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xA5,
        supportedDevices: [.mobi], minApi: .mobi_v3_5) // upstream MOBI_ONLY + MOBI_API_V3_5

    /// Duration bounds enforced by the pump (durations < 15 min or > 72 h are rejected).
    public static let minMinutes = 15
    public static let maxMinutes = 72 * 60
    /// Percent bounds enforced by the pump (0–250 %).
    public static let minPercent = 0
    public static let maxPercent = 250

    /// Reject out-of-range args by throwing BEFORE any truncating byte-encode
    /// helper — never silently convert an invalid value into a different valid command (e.g. percent
    /// 65536 would truncate to 0% via `Bytes.firstTwoBytesLittleEndian`).
    public enum ValidationError: Error, Equatable, LocalizedError {
        case minutesOutOfRange(Int)
        case percentOutOfRange(Int)
        // Human-readable messages so a caller surfacing `error.localizedDescription` (e.g. the
        // app's generic control-error catch) shows a clear cause, not a bridged NSError string.
        public var errorDescription: String? {
            switch self {
            case .minutesOutOfRange(let m): return "Temp rate duration \(m) min is out of range — must be 15 to 4320 minutes (72 h)."
            case .percentOutOfRange(let p): return "Temp rate \(p)% is out of range — must be 0 to 250%."
            }
        }
    }

    public var cargo: [UInt8]
    public private(set) var minutes: Int = 0
    public private(set) var percent: Int = 0

    public init() { self.cargo = [] }

    public init(minutes: Int, percent: Int) throws {
        guard (Self.minMinutes...Self.maxMinutes).contains(minutes) else {
            throw ValidationError.minutesOutOfRange(minutes)
        }
        guard (Self.minPercent...Self.maxPercent).contains(percent) else {
            throw ValidationError.percentOutOfRange(percent)
        }
        self.minutes = minutes
        self.percent = percent
        self.cargo = Bytes.combine(
            Bytes.toUint32(UInt32(minutes * 60_000)),
            Bytes.firstTwoBytesLittleEndian(percent))
    }

    public mutating func parse(_ raw: [UInt8]) {
        self.cargo = raw
        guard raw.count >= 6 else { return }
        self.minutes = Int(Bytes.readUint32(raw, 0) / 1000 / 60)
        self.percent = Bytes.readShort(raw, 4)
    }
}

/// Stops an active temporary basal rate. Signed, modifies insulin delivery, Mobi-only, empty cargo.
/// Port of `request/control/StopTempRateRequest` (opcode -90 / 0xA6).
public struct StopTempRateRequest: Message {
    public static let props = MessageProps(
        opCode: 0xA6, size: 0, signed: true, type: .request,
        characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xA7,
        supportedDevices: [.mobi], minApi: .mobi_v3_5) // upstream MOBI_ONLY + MOBI_API_V3_5
    public var cargo: [UInt8]
    public init() { self.cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { self.cargo = [] }
}
