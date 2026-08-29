import Foundation

/// Pump qualifying-events bitmap: little-endian 4-byte payload on `.qualifyingEvents`.
/// Port of upstream `QualifyingEvent`; bit values are a byte-exact transcription — never invent one.
///
/// Fail-closed: `decode(_:)` returns `[]` for any buffer shorter than 4 bytes — no past-the-end
/// read, no spurious bit from a partial buffer.
public struct QualifyingEvent: OptionSet, Sendable, Hashable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let alert = QualifyingEvent(rawValue: 1)
    public static let alarm = QualifyingEvent(rawValue: 2)
    public static let reminder = QualifyingEvent(rawValue: 4)
    public static let malfunction = QualifyingEvent(rawValue: 8)
    public static let cgmAlert = QualifyingEvent(rawValue: 16)
    public static let homeScreenChange = QualifyingEvent(rawValue: 32)
    public static let pumpSuspend = QualifyingEvent(rawValue: 64)
    public static let pumpResume = QualifyingEvent(rawValue: 128)
    public static let timeChange = QualifyingEvent(rawValue: 256)
    public static let basalChange = QualifyingEvent(rawValue: 512)
    public static let bolusChange = QualifyingEvent(rawValue: 1024)
    public static let iobChange = QualifyingEvent(rawValue: 2048)
    public static let extendedBolusChange = QualifyingEvent(rawValue: 4096)
    public static let profileChange = QualifyingEvent(rawValue: 8192)
    public static let bg = QualifyingEvent(rawValue: 16384)
    public static let cgmChange = QualifyingEvent(rawValue: 32768)
    public static let battery = QualifyingEvent(rawValue: 65536)
    public static let basalIQ = QualifyingEvent(rawValue: 131072)
    public static let remainingInsulin = QualifyingEvent(rawValue: 262144)
    /// The pump's comms-suspension signal — the bit app-side pause-sends acts on.
    public static let pumpCommunicationsSuspended = QualifyingEvent(rawValue: 524288)
    public static let activeProfileSegmentChange = QualifyingEvent(rawValue: 1_048_576)
    public static let basalIQStatus = QualifyingEvent(rawValue: 2_097_152)
    public static let controlIQInfo = QualifyingEvent(rawValue: 4_194_304)
    public static let controlIQSleep = QualifyingEvent(rawValue: 8_388_608)
    public static let globalPumpSettings = QualifyingEvent(rawValue: 16_777_216)
    public static let snoozeStatus = QualifyingEvent(rawValue: 33_554_432)
    public static let pumpingStatus = QualifyingEvent(rawValue: 67_108_864)
    public static let pumpReset = QualifyingEvent(rawValue: 134_217_728)
    public static let heartbeat = QualifyingEvent(rawValue: 268_435_456)
    public static let bolusPermissionRevoked = QualifyingEvent(rawValue: 0x8000_0000)  // 2_147_483_648

    /// Decode a little-endian 4-byte qualifying-events bitmap (reuses `Bytes.readUint32` —
    /// Don't-Hand-Roll a second little-endian reader). Any buffer shorter than 4 bytes decodes to
    /// `[]` fail-closed (never a precondition-crash, never a partial/spurious bit) — `readUint32`
    /// itself preconditions on `i + 3 < raw.count`, so the length guard MUST run first.
    public static func decode(_ bytes: [UInt8]) -> QualifyingEvent {
        guard bytes.count >= 4 else { return [] }
        return QualifyingEvent(rawValue: Bytes.readUint32(bytes, 0))
    }
}
