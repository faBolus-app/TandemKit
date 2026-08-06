import Foundation
import LoopKit
import PumpX2Messages

/// Translates the pump's own history-log records into LoopKit `NewPumpEvent`s.
///
/// The one safety-critical invariant: a bolus's `deliveredUnits` is the pump's authoritative
/// `insulinDelivered`, never the requested amount. `value` carries the requested amount (LoopKit's
/// convention: `value` = programmed, `deliveredUnits` = actually delivered).
///
/// Dedup: LoopKit keys a dose by `NewPumpEvent.raw.hexadecimalString`. We build `raw` deterministically
/// from the pump's own ids — a bolus uses its `bolusId` (stable across the live-delivery path and its
/// later history record, so they collapse to one), everything else uses the monotonic `sequenceNum`.
/// Never wall-clock.
public enum TandemHistoryMapping {

    public static func newPumpEvents(from events: [any HistoryLogEvent], pumpSerial: String?) -> [NewPumpEvent] {
        events.compactMap { newPumpEvent(from: $0, pumpSerial: pumpSerial) }
    }

    public static func newPumpEvent(from event: any HistoryLogEvent, pumpSerial: String?) -> NewPumpEvent? {
        let t = event.pumpTime
        switch event {
        case let e as BolusCompletedHistoryLog:
            let dose = DoseEntry(
                type: .bolus, startDate: t, endDate: t,
                value: Double(e.insulinRequested), unit: .units,
                deliveredUnits: Double(e.insulinDelivered), isMutable: false)
            return NewPumpEvent(
                date: t, dose: dose,
                raw: TandemUnfinalizedDose.syncIdentifier(pumpSerial: pumpSerial, tag: "bolus", id: UInt32(clamping: e.bolusId)),
                title: "Bolus", type: .bolus)

        case let e as BolexCompletedHistoryLog:
            // Extended-bolus completion → report as a bolus carrying its authoritative delivered amount.
            let dose = DoseEntry(
                type: .bolus, startDate: t, endDate: t,
                value: Double(e.insulinRequested), unit: .units,
                deliveredUnits: Double(e.insulinDelivered), isMutable: false)
            return NewPumpEvent(
                date: t, dose: dose,
                raw: TandemUnfinalizedDose.syncIdentifier(pumpSerial: pumpSerial, tag: "bolex", id: UInt32(clamping: e.bolusId)),
                title: "Extended Bolus", type: .bolus)

        case let e as PumpingSuspendedHistoryLog:
            return NewPumpEvent(
                date: t, dose: DoseEntry(suspendDate: t),
                raw: TandemUnfinalizedDose.syncIdentifier(pumpSerial: pumpSerial, tag: "seq", id: e.sequenceNum),
                title: "Suspend", type: .suspend)

        case let e as PumpingResumedHistoryLog:
            return NewPumpEvent(
                date: t, dose: DoseEntry(resumeDate: t),
                raw: TandemUnfinalizedDose.syncIdentifier(pumpSerial: pumpSerial, tag: "seq", id: e.sequenceNum),
                title: "Resume", type: .resume)

        default:
            // Temp-rate and basal-rate-change history are deliberately NOT reconstructed into U/hr
            // DoseEntries in this first cut: a single Tandem event carries a *percent* (temp) or a rate
            // without the surrounding schedule needed to express honest absolute U/hr segments. Dropping
            // them is safer than fabricating a rate/duration. `pumpRecordsBasalProfileStartEvents` is
            // therefore reported false, so the host reconstructs basal from the programmed schedule.
            return nil
        }
    }
}
