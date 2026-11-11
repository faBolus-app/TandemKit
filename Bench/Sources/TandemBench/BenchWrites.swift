import Foundation
import TandemMessages

/// The bench's bolus kinds, each sent as one 0.05 U bolus of saline (or refused, with no cartridge).
///
/// The cargo layouts follow pumpX2's captures of a t:slim where one exists (`InitiateBolusRequestTest`):
/// units-only is the 1 U override capture's form (mask 8, every other field 0), and carb is the 13 g
/// capture's form (mask 1, the whole dose as food, carbs and BG filled in). Correction-only is in no
/// capture: its mask is the library's rule for a dose with no carbs and a correction (FOOD2 | CORRECTION,
/// 10), and the bench run is what confirms the pump takes it. Every mask comes from
/// `InitiateBolusRequest.typeBitmask`, the one the app uses too. `cancel` is a units-only bolus
/// cancelled as soon as the pump accepts it.
public enum BenchBolusKind: String, CaseIterable, Sendable {
    case units, carb, correction, cancel

    /// 0.05 U, the pump's smallest bolus.
    public static let milliunits: UInt32 = InitiateBolusRequest.minBolusMilliunits

    public var mask: Int {
        InitiateBolusRequest.typeBitmask(hasCarbs: self == .carb, hasCorrection: self == .correction, isExtended: false)
    }

    /// Where the layout comes from, printed with the request.
    public var source: String {
        switch self {
        case .units, .cancel: return "pumpX2 capture form (1 U override: mask 8, no food, correction, carbs or BG)"
        case .carb: return "pumpX2 capture form (13 g carbs: mask 1, the dose as food, carbs and BG)"
        case .correction:
            return "no capture: mask 10 (FOOD2 | CORRECTION), the dose as correction, with the BG; this run confirms it"
        }
    }

    public func request(bolusId: Int, carbs: Int, bg: Int) throws -> InitiateBolusRequest {
        let total = Self.milliunits
        switch self {
        case .units, .cancel:
            return try InitiateBolusRequest(validating: total, bolusID: bolusId, bolusTypeBitmask: mask)
        case .carb:
            return try InitiateBolusRequest(
                validating: total, bolusID: bolusId, bolusTypeBitmask: mask, foodVolume: total, bolusCarbs: carbs,
                bolusBG: bg)
        case .correction:
            return try InitiateBolusRequest(
                validating: total, bolusID: bolusId, bolusTypeBitmask: mask, correctionVolume: total, bolusBG: bg)
        }
    }
}

/// Every bench bolus sent, kept between runs so a restart can't repeat one: a bolus whose outcome
/// wasn't settled blocks the next until the person at the bench has checked the pump, and at most
/// three go out in any hour.
public struct BenchBolusLog: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var date: Date
        public var serial: Int
        public var kind: String
        public var bolusId: Int
        /// nil until the outcome is known: from the pump's replies, or `bolus settle` after a check.
        public var outcome: String?

        public init(date: Date, serial: Int, kind: String, bolusId: Int, outcome: String? = nil) {
            self.date = date
            self.serial = serial
            self.kind = kind
            self.bolusId = bolusId
            self.outcome = outcome
        }
    }

    public static let perHour = 3

    public var entries: [Entry] = []

    public init(entries: [Entry] = []) { self.entries = entries }

    /// Why no bolus may go out now, or nil.
    public func refusal(now: Date) -> String? {
        if let open = entries.last(where: { $0.outcome == nil }) {
            return "bench bolus \(open.bolusId) (\(open.kind), \(open.date)) has no settled outcome: check the pump's "
                + "history, then run `bolus settle`"
        }
        let recent = entries.filter { now.timeIntervalSince($0.date) < 3600 }.count
        if recent >= Self.perHour { return "\(recent) bench boluses in the last hour; the limit is \(Self.perHour)" }
        return nil
    }

    public mutating func settleLast(_ outcome: String) -> Bool {
        guard let i = entries.lastIndex(where: { $0.outcome == nil }) else { return false }
        entries[i].outcome = outcome
        return true
    }
}

/// The checks before a bench write or bolus goes out. Each returns why it may not, or nil.
public enum BenchSafetyGate {
    /// The serial typed at the prompt has to be this pump's, so a write never reaches the wrong pump.
    public static func serialRefusal(typed: String, pumpSerial: Int?) -> String? {
        guard let pumpSerial else { return "this pump's serial number isn't known yet" }
        let digits = typed.trimmingCharacters(in: .whitespaces)
        return digits == String(pumpSerial) ? nil : "the typed serial isn't this pump's (\(pumpSerial)); nothing sent"
    }

    /// UserInteraction and ChangeTimeDate: `PUMP_BENCH_WRITES=1` and the serial.
    public static func writeRefusal(environment: [String: String], typed: String, pumpSerial: Int?) -> String? {
        guard environment["PUMP_BENCH_WRITES"] == "1" else { return "set PUMP_BENCH_WRITES=1 to send a bench write" }
        return serialRefusal(typed: typed, pumpSerial: pumpSerial)
    }

    /// A bolus: either the rejection test with no cartridge (the pump reports no insulin), or saline
    /// attested with `PUMP_SALINE_ATTESTED=1`; and the serial.
    public static func bolusRefusal(
        environment: [String: String], typed: String, pumpSerial: Int?, noCartridge: Bool, reservoirUnits: Int?
    ) -> String? {
        if noCartridge {
            guard let reservoirUnits else { return "--no-cartridge needs the pump's InsulinStatus, which didn't answer" }
            if reservoirUnits != 0 { return "--no-cartridge, but the pump reports \(reservoirUnits) U in a cartridge" }
        } else if environment["PUMP_SALINE_ATTESTED"] != "1" {
            return "set PUMP_SALINE_ATTESTED=1 (a saline cartridge, tubing into a container, on no one) or use "
                + "--no-cartridge"
        }
        return serialRefusal(typed: typed, pumpSerial: pumpSerial)
    }
}

/// A clock-set target: the pump's time when it was read, moved on by the time since, plus `offset`.
public enum BenchClock {
    public static func target(pumpTime: UInt32, readAt: Double, now: Double, offset: Int) -> UInt32 {
        let elapsed = max(0, now - readAt)
        let t = Int64(pumpTime) + Int64(elapsed.rounded()) + Int64(offset)
        return UInt32(clamping: max(0, t))
    }
}
