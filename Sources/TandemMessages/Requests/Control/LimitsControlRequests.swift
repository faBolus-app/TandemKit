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
        characteristic: .control, responseOpCode: 0x87,
        minApi: .benchConservativeUnverifiedFloor)   // CONSERVATIVE/UNVERIFIED bench floor (T-1, >2.5 only)

    /// CX-T-07 owner decision (2026-08-25, option-a ALIGN UP — see faBolus OWNER-DECISIONS.md 15-05 Task 1):
    /// matches pumpX2's own unconditionally-enforced floor/ceiling (`SetMaxBolusLimitRequest.java`
    /// MIN/MAX_BOLUS_LIMIT_MILLIUNITS), but the app team has not independently bench-confirmed it, so it is
    /// treated CONSERVATIVE/UNVERIFIED pending Phase-12 bench (T-1), like the minApi floors.
    public static let minMaxBolusMilliunits = 1_000     // 1.0 U — CONSERVATIVE/UNVERIFIED (T-1)
    public static let maxMaxBolusMilliunits = 25_000    // 25.0 U — matches Interlocks.absoluteMaxUnits

    /// CX-T-07 (PX-07 convention): reject out-of-range args by throwing BEFORE the byte-encode.
    public enum ValidationError: Error, Equatable, LocalizedError {
        case maxBolusMilliunitsOutOfRange(Int)
        // 15-IN-02: human-readable message for a caller surfacing `error.localizedDescription`.
        public var errorDescription: String? {
            switch self {
            case .maxBolusMilliunitsOutOfRange(let mu): return "Max bolus limit \(Double(mu) / 1000) U is out of range — must be 1.0 to 25.0 U."
            }
        }
    }

    public var cargo: [UInt8]
    public private(set) var maxBolusMilliunits = 0
    public init() { cargo = [] }
    public init(maxBolusMilliunits: Int) throws {
        guard (Self.minMaxBolusMilliunits...Self.maxMaxBolusMilliunits).contains(maxBolusMilliunits) else {
            throw ValidationError.maxBolusMilliunitsOutOfRange(maxBolusMilliunits)
        }
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
        characteristic: .control, responseOpCode: 0x89,
        minApi: .benchConservativeUnverifiedFloor)   // CONSERVATIVE/UNVERIFIED bench floor (T-1, >2.5 only)

    /// CX-T-07 owner decision (2026-08-25, option-a ALIGN UP — see faBolus OWNER-DECISIONS.md 15-05 Task 1):
    /// matches pumpX2's own unconditionally-enforced floor/ceiling (`SetMaxBasalLimitRequest.java`
    /// MIN/MAX_BASAL_LIMIT_MILLIUNITS), CONSERVATIVE/UNVERIFIED pending Phase-12 bench (T-1).
    public static let minMaxHourlyBasalMilliunits: UInt32 = 1_000    // 1.0 U/hr — CONSERVATIVE/UNVERIFIED (T-1)
    public static let maxMaxHourlyBasalMilliunits: UInt32 = 15_000   // 15.0 U/hr

    /// CX-T-07 (PX-07 convention): reject out-of-range args by throwing BEFORE the byte-encode.
    public enum ValidationError: Error, Equatable, LocalizedError {
        case maxHourlyBasalMilliunitsOutOfRange(UInt32)
        // 15-IN-02: human-readable message for a caller surfacing `error.localizedDescription`.
        public var errorDescription: String? {
            switch self {
            case .maxHourlyBasalMilliunitsOutOfRange(let mu): return "Max basal limit \(Double(mu) / 1000) U/hr is out of range — must be 1.0 to 15.0 U/hr."
            }
        }
    }

    public var cargo: [UInt8]
    public private(set) var maxHourlyBasalMilliunits: UInt32 = 0
    public init() { cargo = [] }
    public init(maxHourlyBasalMilliunits: UInt32) throws {
        guard (Self.minMaxHourlyBasalMilliunits...Self.maxMaxHourlyBasalMilliunits).contains(maxHourlyBasalMilliunits) else {
            throw ValidationError.maxHourlyBasalMilliunitsOutOfRange(maxHourlyBasalMilliunits)
        }
        self.maxHourlyBasalMilliunits = maxHourlyBasalMilliunits
        self.cargo = Bytes.toUint32(maxHourlyBasalMilliunits)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 4 { maxHourlyBasalMilliunits = Bytes.readUint32(body, 0) }
    }
}
