import Foundation
import LoopKit

/// A dose the driver has issued or observed whose *authoritative* delivered amount may not be final yet.
///
/// Mirrors LoopKit's OmniBLE `UnfinalizedDose` pattern, adapted for Tandem. The safety-critical
/// distinction it encodes (C4 / "accepted ≠ delivered"):
///
/// - `programmedUnits` is what was *asked for* (bolus units, or temp-basal U/hr). It becomes the emitted
///   `DoseEntry.value`.
/// - `finalizedUnits` is the pump's *own authoritative* delivered amount. It stays `nil` until the pump
///   confirms it, and becomes `DoseEntry.deliveredUnits`. The driver never fabricates it from the
///   programmed amount.
///
/// A bolus / temp-basal is `isMutable` until the pump has given an authoritative terminal
/// (`finalizedUnits != nil`), so an in-flight or indeterminate dose is reported to the host as still
/// mutable — never as a completed dose the pump never confirmed.
public struct TandemUnfinalizedDose: Equatable, Codable {
    public enum DoseType: String, Equatable, Codable { case bolus, tempBasal, suspend, resume }

    /// Whether the command is known to have reached the pump. `.uncertain` is the indeterminate path:
    /// a write was issued but no authoritative outcome was read (disconnect / lost reply / deadline).
    public enum ScheduledCertainty: String, Equatable, Codable { case certain, uncertain }

    var doseType: DoseType
    /// Programmed amount — bolus units or temp-basal U/hr. Reported as `DoseEntry.value`.
    var programmedUnits: Double
    /// Pump-authoritative delivered amount; `nil` until the pump confirms. Reported as `deliveredUnits`.
    var finalizedUnits: Double?
    var startTime: Date
    /// Estimated/known duration — for temp basal, the temp duration; for a bolus, the estimated delivery
    /// window so `endDate` is sensible; 0 for suspend/resume.
    var duration: TimeInterval
    var scheduledCertainty: ScheduledCertainty
    var automatic: Bool
    var insulinType: InsulinType?
    /// The pump's own bolus id (from `BolusPermissionResponse`), used to reconcile this dose against
    /// `LastBolusStatusV2Response` and as its stable sync identifier. nil for non-bolus doses.
    var bolusId: Int?
    /// Stable, pump-sourced identity for LoopKit dedup. `NewPumpEvent.init` overwrites the dose's
    /// `syncIdentifier` with `raw.hexadecimalString`, so this Data IS the dose's sync identifier — it
    /// must be deterministic from the pump's own ids (bolus id / history sequence number + serial),
    /// never wall-clock.
    var syncIdentifier: Data

    var finishTime: Date { startTime.addingTimeInterval(duration) }

    /// A bolus/temp-basal stays mutable until the pump has confirmed an authoritative delivered amount.
    /// This is deliberately keyed on `finalizedUnits`, not wall-clock — the driver does not declare a
    /// dose finished just because its estimated window elapsed.
    func isMutable() -> Bool {
        switch doseType {
        case .bolus, .tempBasal: return finalizedUnits == nil
        case .suspend, .resume: return false
        }
    }

    var eventTitle: String {
        switch doseType {
        case .bolus: return "Bolus \(String(format: "%.2f", programmedUnits))U"
        case .tempBasal: return "Temp Basal \(String(format: "%.2f", programmedUnits))U/hr"
        case .suspend: return "Suspend"
        case .resume: return "Resume"
        }
    }

    /// Build the deterministic sync-identifier Data from the pump's own identifiers. Never uses time.
    /// `tag` distinguishes an issued-bolus id from a history sequence number so the two id spaces can't
    /// collide into the same LoopKit `syncIdentifier`.
    static func syncIdentifier(pumpSerial: String?, tag: String, id: UInt32) -> Data {
        Data("\(pumpSerial ?? "unknown").\(tag).\(id)".utf8)
    }
}

extension DoseEntry {
    /// Translate to LoopKit's `DoseEntry`. `value` = programmed, `deliveredUnits` = pump-authoritative
    /// (nil until confirmed). Mirrors OmniBLE `DoseEntry(_ dose: UnfinalizedDose)`.
    init(_ dose: TandemUnfinalizedDose) {
        switch dose.doseType {
        case .bolus:
            self = DoseEntry(
                type: .bolus,
                startDate: dose.startTime,
                endDate: dose.finishTime,
                value: dose.programmedUnits,
                unit: .units,
                deliveredUnits: dose.finalizedUnits,
                insulinType: dose.insulinType,
                automatic: dose.automatic,
                isMutable: dose.isMutable()
            )
        case .tempBasal:
            self = DoseEntry(
                type: .tempBasal,
                startDate: dose.startTime,
                endDate: dose.finishTime,
                value: dose.programmedUnits,
                unit: .unitsPerHour,
                deliveredUnits: dose.finalizedUnits,
                insulinType: dose.insulinType,
                automatic: dose.automatic,
                isMutable: dose.isMutable()
            )
        case .suspend:
            self = DoseEntry(suspendDate: dose.startTime, automatic: dose.automatic)
        case .resume:
            self = DoseEntry(resumeDate: dose.startTime, insulinType: dose.insulinType, automatic: dose.automatic)
        }
    }
}

extension NewPumpEvent {
    /// Mirrors OmniBLE `NewPumpEvent(_ dose:)`: `raw` becomes the dose's `syncIdentifier` (hex), so
    /// re-ingesting the same pump record yields the same identifier and LoopKit dedups it.
    init(_ dose: TandemUnfinalizedDose) {
        self.init(date: dose.startTime, dose: DoseEntry(dose), raw: dose.syncIdentifier, title: dose.eventTitle)
    }
}
