import Foundation

/// A **pure, testable** carb/correction bolus planner for the saline bench harness (audit round-2 P1).
///
/// The bench harness previously computed its dose inline in the BLE monitor with a wrong formula:
/// `correction = max(0, (BG − target)/ISF)` dropped the **signed below-target correction** (and its IOB
/// interaction), and it rounded the total straight to 0.05 U with no two-decimal component rounding — so a
/// below-target BG did **not** reduce a food dose, risking an over-delivery on the bench.
///
/// This planner mirrors the Tandem oracle `BolusCalculator.parse()` exactly — the same logic faBolus's
/// `BolusMath` ports and that `faBolusCore`'s `BolusMathParityTests` verifies against **563** real oracle
/// vectors. It keeps the BG correction **signed**, lets **positive IOB** offset it, applies two-decimal
/// HALF_UP rounding per component, floors the total at zero, then snaps to the 0.05 U pump increment and
/// applies an explicit bench cap. It also produces the full `InitiateBolusRequest` cargo so the bench can
/// snapshot the entire planned request, not just the type byte.
public enum BenchBolusPlanner {

    /// Pump bolus-calculator inputs, in human units (carb ratio g/U, ISF mg/dL per U, target mg/dL, IOB U).
    public struct Profile: Sendable, Equatable {
        public var carbRatioGramsPerUnit: Double
        public var isfMgdlPerUnit: Int
        public var targetBgMgdl: Int
        public var iobUnits: Double
        public init(carbRatioGramsPerUnit: Double, isfMgdlPerUnit: Int, targetBgMgdl: Int, iobUnits: Double) {
            self.carbRatioGramsPerUnit = carbRatioGramsPerUnit
            self.isfMgdlPerUnit = isfMgdlPerUnit
            self.targetBgMgdl = targetBgMgdl
            self.iobUnits = iobUnits
        }
    }

    /// A fully-decomposed plan. Component doubles are for printing/verification; the milliunit fields are
    /// the wire cargo. `foodMilliunits + correctionMilliunits == totalMilliunits` always holds.
    public struct Plan: Sendable, Equatable {
        public let totalMilliunits: UInt32
        public let foodMilliunits: UInt32
        public let correctionMilliunits: UInt32
        public let carbGrams: Int
        public let bgMgdl: Int              // 0 ⇒ no BG entered
        public let iobMilliunits: UInt32
        public let bitmask: Int
        /// True when the profile failed the oracle sanity check (bad carb ratio / target / ISF) → 0 dose.
        public let sanityFailed: Bool
        // Component breakdown in human units (pre-increment), for the bench print-out.
        public let fromCarbsUnits: Double
        public let fromBGUnits: Double
        public let fromIOBUnits: Double
        public let oracleTotalUnits: Double   // the oracle getTotal() before the 0.05 U snap / bench cap
    }

    /// The oracle's `BolusCalcUnits.doublePrecision`: `BigDecimal.valueOf(v).setScale(2, HALF_UP)`.
    /// Built from the value's shortest decimal string so it rounds the human-decimal value (2.675 → 2.68),
    /// with round-half-away-from-zero (== Java HALF_UP).
    static func dp(_ v: Double) -> Double {
        if !v.isFinite { return v }
        var d = Decimal(string: String(v)) ?? Decimal(v)
        var r = Decimal()
        NSDecimalRound(&r, &d, 2, .plain)
        return NSDecimalNumber(decimal: r).doubleValue
    }

    /// Snap a **units** value to the 0.05 U pump increment and convert to milliunits **without ever
    /// trapping** (R3-E). The bench cap in `plan` is applied *after* this, so this must fail safe on the
    /// pathological inputs that would otherwise crash `UInt32(_:)`: a non-finite value → 0, and a dose
    /// larger than `UInt32` clamps to `UInt32.max` (the cap then bounds it). Finite, in-range values are
    /// byte-identical to the previous inline `UInt32((v * 1000 / 50).rounded() * 50)`.
    static func milliunitsSnapped(_ units: Double) -> UInt32 {
        guard units.isFinite, units > 0 else { return 0 }
        let mu = (units * 1000 / 50).rounded() * 50
        guard mu.isFinite, mu > 0 else { return 0 }
        return mu >= Double(UInt32.max) ? UInt32.max : UInt32(mu)
    }

    /// Carb grams as the `Int` metadata field, **without trapping** (R3-E): a non-finite or non-positive
    /// value → 0, and anything at/above the uint16 wire ceiling clamps to 65535 (so `Int(_:)` never
    /// overflows — `Int` is 32-bit on watchOS — and the value still passes `InitiateBolusRequest`'s
    /// 0...0xFFFF check). Finite in-range values match the previous `max(0, Int(g.rounded()))`.
    static func safeCarbInt(_ grams: Double?) -> Int {
        guard let grams, grams.isFinite, grams > 0 else { return 0 }
        return grams >= 65535 ? 65535 : Int(grams.rounded())
    }

    /// Compute the plan. `carbsGrams == nil` ⇒ correction-only; `bgMgdl == nil` ⇒ no BG correction.
    /// `benchCapMilliunits` bounds the bench dose as defense-in-depth on saline; the bench harness passes
    /// a tight 2.0 U bound, while the calculator itself defaults to the app's absolute 25 U ceiling so the
    /// cap never silently alters a computed dose in tests.
    public static func plan(carbsGrams: Double?, bgMgdl: Int?, profile: Profile,
                            benchCapMilliunits: UInt32 = 25000) -> Plan {
        // --- addedFromCarbs: each component doublePrecision-rounded first ---
        var fromCarbs = 0.0
        var carbSanityFail = false
        if let carbs = carbsGrams {
            if profile.carbRatioGramsPerUnit > 0 { fromCarbs = dp(carbs / profile.carbRatioGramsPerUnit) }
            else { carbSanityFail = true }
        }
        // --- addedFromGlucose: SIGNED (below-target reduces the dose) ---
        var fromBG = 0.0
        var bgSanityFail = false
        if let bg = bgMgdl {
            if profile.targetBgMgdl < 40 || profile.targetBgMgdl > 400 { bgSanityFail = true }
            else if profile.isfMgdlPerUnit <= 0 { bgSanityFail = true }
            else { fromBG = dp(Double(bg - profile.targetBgMgdl) / Double(profile.isfMgdlPerUnit)) }
        }
        // --- addedFromIOB: only positive IOB reduces the dose ---
        let fromIOB = profile.iobUnits > 0 ? dp(-profile.iobUnits) : 0.0

        // --- parse() combination (mirrors BolusCalculator.parse) ---
        var total = fromCarbs
        if fromBG >= 0 {
            let corr = fromBG + fromIOB
            if corr > 0 { total += corr }   // POSITIVE_BG_CORRECTION (else IOB cancels it → add nothing)
        } else {
            let corr = fromBG + fromIOB     // below target: negative correction reduces the dose
            if total + corr > 0 { total += corr } else { total = 0.0 }
        }
        total = dp(total)

        // A non-finite total means a non-finite input (±inf / NaN carbs or IOB) reached the math — treat
        // it as a sanity failure (0 dose) so it never flows into an integer conversion that would trap.
        let sanityFailed = carbSanityFail || bgSanityFail || !total.isFinite
        let oracleTotal = sanityFailed ? 0.0 : max(0, total)

        // Snap to the 0.05 U pump increment, then apply the bench cap. `milliunitsSnapped` never traps.
        var totalMU = milliunitsSnapped(oracleTotal)
        totalMU = min(totalMU, benchCapMilliunits)

        // Wire split: the carb portion goes to foodVolume (snapped, bounded by total); the remainder —
        // which carries the signed BG/IOB effect — goes to correctionVolume, so food+correction == total.
        let foodComponent = sanityFailed ? 0.0 : max(0, fromCarbs)
        let foodMU = min(milliunitsSnapped(foodComponent), totalMU)
        let correctionMU = totalMU - foodMU

        let hasCarbs = (carbsGrams ?? 0) > 0 && fromCarbs > 0 && !sanityFailed
        let bits = InitiateBolusRequest.typeBitmask(hasCarbs: hasCarbs,
                                                    hasCorrection: correctionMU > 0,
                                                    isExtended: false)
        // IOB metadata (milliunits), clamped to 1_000_000 and non-trapping: a non-finite IOB → 0.
        let iobRaw = profile.iobUnits > 0 ? dp(profile.iobUnits) : 0
        let iobMU = iobRaw.isFinite ? UInt32(min(max(0, iobRaw) * 1000, 1_000_000).rounded()) : 0
        return Plan(totalMilliunits: totalMU, foodMilliunits: foodMU, correctionMilliunits: correctionMU,
                    carbGrams: safeCarbInt(carbsGrams), bgMgdl: max(0, bgMgdl ?? 0),
                    iobMilliunits: iobMU, bitmask: bits, sanityFailed: sanityFailed,
                    fromCarbsUnits: fromCarbs, fromBGUnits: fromBG, fromIOBUnits: fromIOB,
                    oracleTotalUnits: oracleTotal)
    }

    /// Build the full, validated `InitiateBolusRequest` for this plan (PX-07 validating constructor), so
    /// the bench snapshots the ENTIRE planned request cargo.
    public static func request(for plan: Plan, bolusID: Int) throws -> InitiateBolusRequest {
        try InitiateBolusRequest(validating: plan.totalMilliunits, bolusID: bolusID, bolusTypeBitmask: plan.bitmask,
                                 foodVolume: plan.foodMilliunits, correctionVolume: plan.correctionMilliunits,
                                 bolusCarbs: plan.carbGrams, bolusBG: plan.bgMgdl, bolusIOB: plan.iobMilliunits)
    }
}
