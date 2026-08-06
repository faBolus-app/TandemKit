import Foundation
import LoopKit

/// Estimates in-progress bolus delivery from elapsed wall-clock time vs. the dose's estimated window,
/// exactly like OmniBLE's `PodDoseProgressEstimator`. This is a *display* estimate only — the
/// authoritative delivered amount is always the pump's own record, reconciled when the bolus finalizes.
final class TandemDoseProgressEstimator: DoseProgressTimerEstimator {
    let dose: DoseEntry
    weak var pumpManager: PumpManager?

    init(dose: DoseEntry, pumpManager: PumpManager, reportingQueue: DispatchQueue) {
        self.dose = dose
        self.pumpManager = pumpManager
        super.init(reportingQueue: reportingQueue)
    }

    override var progress: DoseProgress {
        let elapsed = -dose.startDate.timeIntervalSinceNow
        let duration = dose.endDate.timeIntervalSince(dose.startDate)
        let percent = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let estimate = percent * dose.programmedUnits
        let delivered = pumpManager?.roundToSupportedBolusVolume(units: estimate) ?? estimate
        return DoseProgress(deliveredUnits: delivered, percentComplete: percent)
    }

    override func timerParameters() -> (delay: TimeInterval, repeating: TimeInterval) {
        let duration = dose.endDate.timeIntervalSince(dose.startDate)
        return (delay: 0, repeating: max(duration / 50, 1))
    }
}
