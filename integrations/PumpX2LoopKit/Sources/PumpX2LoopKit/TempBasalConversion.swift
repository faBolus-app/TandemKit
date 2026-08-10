import Foundation

/// LoopKit passes temp basal as an absolute **U/hr** rate; Tandem's `SetTempRateRequest` is a
/// **percent of the currently scheduled basal**. This conversion is inherently lossy, so it reports the
/// *effective* achievable U/hr — the driver must tell LoopKit the rate the pump can actually hold, not
/// the rate that was requested.
public enum TandemTempBasalConversion {
    public enum ConversionError: Error, Equatable {
        /// Scheduled basal is 0 U/hr, so a percent-of-scheduled temp is undefined — refuse, don't guess.
        case scheduledRateZero
    }

    /// - Returns: the clamped Tandem percent and the *effective* U/hr it yields against `scheduled`.
    public static func percent(forUnitsPerHour requested: Double,
                               scheduledUnitsPerHour scheduled: Double,
                               minPercent: Int,
                               maxPercent: Int) throws -> (percent: Int, effectiveUnitsPerHour: Double) {
        guard scheduled > 0 else { throw ConversionError.scheduledRateZero }
        let raw = (requested / scheduled) * 100.0
        let clamped = min(max(Int(raw.rounded()), minPercent), maxPercent)
        let effective = scheduled * Double(clamped) / 100.0
        return (clamped, effective)
    }
}
