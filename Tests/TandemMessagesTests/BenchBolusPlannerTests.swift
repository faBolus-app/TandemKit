import Testing
import Foundation
@testable import TandemMessages

/// Round-2 P1: the bench carb planner must match the Tandem oracle `BolusCalculator.parse()` — the same
/// formula faBolus's `BolusMath` ports and `faBolusCore`'s 563-vector `BolusMathParityTests` verifies.
/// The old harness formula used `max(0, (BG−target)/ISF)`, dropping the SIGNED below-target correction
/// (and its IOB interaction) and skipping two-decimal component rounding — an over-delivery risk on saline.
/// These deterministic cases lock the corrected behavior (signed correction, IOB, dp2, zero floor,
/// 0.05 U snap, bench cap) and the full request cargo.
@Suite struct BenchBolusPlannerTests {

    // A clean profile: 10 g/U, ISF 50 mg/dL/U, target 120 mg/dL.
    private func profile(iob: Double = 0) -> BenchBolusPlanner.Profile {
        BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 10, isfMgdlPerUnit: 50, targetBgMgdl: 120, iobUnits: iob)
    }
    private let F1 = InitiateBolusRequest.bitFood1
    private let F2 = InitiateBolusRequest.bitFood2
    private let CORR = InitiateBolusRequest.bitCorrection

    /// food+correction always equals total; a deliverable plan (≥ 0.05 U) builds a valid PX-07 request.
    private func assertCoherent(_ p: BenchBolusPlanner.Plan) {
        #expect(p.foodMilliunits + p.correctionMilliunits == p.totalMilliunits)
        if p.totalMilliunits >= InitiateBolusRequest.minBolusMilliunits {
            #expect((try? BenchBolusPlanner.request(for: p, bolusID: 42)) != nil)
        }
    }

    // MARK: above target

    @Test func aboveTargetCarbsNoIob() {
        let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: profile())
        // fromCarbs 3.00 + fromBG (170-120)/50=1.00 → total 4.00
        #expect(p.totalMilliunits == 4000)
        #expect(p.foodMilliunits == 3000 && p.correctionMilliunits == 1000)
        #expect(p.bitmask == (F1 | CORR))
        assertCoherent(p)
    }

    @Test func iobExceedingCorrectionAddsNothing() {
        let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 140, profile: profile(iob: 2.0))
        // fromBG 0.40, fromIOB -2.00 → corr -1.60 (<0) → add nothing → total = carbs 3.00
        #expect(p.totalMilliunits == 3000)
        #expect(p.correctionMilliunits == 0 && p.bitmask == F1)
        assertCoherent(p)
    }

    @Test func iobEqualToCorrectionAddsNothing() {
        let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: profile(iob: 1.0))
        // fromBG 1.00, fromIOB -1.00 → corr 0 → total = carbs 3.00
        #expect(p.totalMilliunits == 3000)
        assertCoherent(p)
    }

    // MARK: below target — the bug the old formula had

    @Test func belowTargetReducesDoseBelowFoodOnly() {
        let below = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 70, profile: profile())
        let foodOnly = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: nil, profile: profile())
        // fromBG (70-120)/50 = -1.00 → total 3.00 - 1.00 = 2.00, strictly LESS than food-only 3.00.
        #expect(below.totalMilliunits == 2000)
        #expect(foodOnly.totalMilliunits == 3000)
        #expect(below.totalMilliunits < foodOnly.totalMilliunits)   // the old max(0,…) got this wrong
        #expect(below.fromBGUnits == -1.00)
        assertCoherent(below); assertCoherent(foodOnly)
    }

    @Test func belowTargetWithIobFloorsAtZero() {
        // No carbs, deeply below target → correction alone can't take the total below 0.
        let p = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 50, profile: profile())
        // fromBG (50-120)/50 = -1.40, no carbs → total floored at 0.
        #expect(p.totalMilliunits == 0)
        #expect(p.bitmask == F2)          // no carbs ⇒ FOOD2, no correction component
        assertCoherent(p)
    }

    // MARK: correction-only (no carbs) → FOOD2 (+CORRECTION)

    @Test func correctionOnlyAboveTargetUsesFood2() {
        let p = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 200, profile: profile())
        // fromBG (200-120)/50 = 1.60 → total 1.60
        #expect(p.totalMilliunits == 1600)
        #expect(p.foodMilliunits == 0 && p.correctionMilliunits == 1600)
        #expect(p.bitmask == (F2 | CORR))
        assertCoherent(p)
    }

    // MARK: two-decimal HALF_UP component rounding

    @Test func componentIsTwoDecimalRounded() {
        let prof = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 7, isfMgdlPerUnit: 50, targetBgMgdl: 120, iobUnits: 0)
        let p = BenchBolusPlanner.plan(carbsGrams: 25, bgMgdl: 120, profile: prof)
        // 25/7 = 3.5714… → dp2 = 3.57 (not the raw binary value). Compare with tolerance (the dp() double
        // is the nearest binary to 3.57); the milliunit conversion snaps it cleanly.
        #expect(abs(p.fromCarbsUnits - 3.57) < 1e-9)
        assertCoherent(p)
    }

    // MARK: bench cap + sanity

    @Test func benchCapBoundsTheDose() {
        // 100/10 = 10.0 U, but the harness passes a tight 2.0 U saline cap.
        let p = BenchBolusPlanner.plan(carbsGrams: 100, bgMgdl: nil, profile: profile(), benchCapMilliunits: 2000)
        #expect(p.totalMilliunits == 2000)   // capped at the 2.0 U bench limit
        assertCoherent(p)
    }

    @Test func invalidProfileSanityFailsToZero() {
        let bad = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 0, isfMgdlPerUnit: 50, targetBgMgdl: 120, iobUnits: 0)
        let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: bad)
        #expect(p.sanityFailed)
        #expect(p.totalMilliunits == 0)
    }

    // MARK: full request cargo

    @Test func fullRequestCargoMatchesPlan() throws {
        let p = BenchBolusPlanner.plan(carbsGrams: 45, bgMgdl: 180, profile: profile(iob: 0.5))
        // fromCarbs 4.50 + fromBG 1.20 + fromIOB -0.50 → 5.20
        #expect(p.totalMilliunits == 5200)
        #expect(p.carbGrams == 45 && p.bgMgdl == 180)
        #expect(p.iobMilliunits == 500)
        #expect(p.bitmask == (F1 | CORR))
        let req = try BenchBolusPlanner.request(for: p, bolusID: 7)   // PX-07 validating build succeeds
        #expect(!req.cargo.isEmpty)
        assertCoherent(p)
    }

    /// The exact 37-byte cargo for a known plan — locks the planner's food/correction DECOMPOSITION and
    /// bitmask into a specific request (the encoder itself is oracle-byte-locked by OracleParityTests /
    /// InitiateBolusExtendedTests, so this pins what the *planner* chose, end to end). Round-trip parse too.
    @Test func requestCargoIsByteLocked() throws {
        let p = BenchBolusPlanner.plan(carbsGrams: 45, bgMgdl: 180, profile: profile(iob: 0.5))
        let req = try BenchBolusPlanner.request(for: p, bolusID: 7)
        let expected: [UInt8] = [
            0x50, 0x14, 0x00, 0x00,   // totalVolume 5200
            0x07, 0x00,               // bolusID 7
            0x00, 0x00,               // reserved
            0x03,                     // bitmask FOOD1|CORRECTION
            0x94, 0x11, 0x00, 0x00,   // foodVolume 4500
            0xBC, 0x02, 0x00, 0x00,   // correctionVolume 700
            0x2D, 0x00,               // bolusCarbs 45
            0xB4, 0x00,               // bolusBG 180
            0xF4, 0x01, 0x00, 0x00,   // bolusIOB 500
            0x00, 0x00, 0x00, 0x00,   // extendedVolume 0
            0x00, 0x00, 0x00, 0x00,   // extendedSeconds 0
            0x00, 0x00, 0x00, 0x00,   // extended3 0
        ]
        #expect(req.cargo == expected)
        var round = InitiateBolusRequest(); round.parse(req.cargo)   // bidirectional: cargo → fields
        #expect(round.totalVolume == 5200 && round.foodVolume == 4500 && round.correctionVolume == 700)
        #expect(round.bolusCarbs == 45 && round.bolusBG == 180 && round.bolusIOB == 500)
        #expect(round.bolusTypeBitmask == (F1 | CORR))
    }

    // MARK: R3-E — numeric-input safety (these inputs used to TRAP at the UInt32/Int conversions)

    /// The 0.05 U → milliunit snap must never trap: non-finite → 0, and a dose beyond UInt32 clamps to
    /// UInt32.max (the bench cap then bounds it). Finite in-range values are byte-identical to the old code.
    @Test func milliunitsSnappedIsNonTrappingAndSnapsCorrectly() {
        #expect(BenchBolusPlanner.milliunitsSnapped(4.0) == 4000)      // byte-identity spot-check
        #expect(BenchBolusPlanner.milliunitsSnapped(0.0) == 0)
        #expect(BenchBolusPlanner.milliunitsSnapped(-1.0) == 0)        // negative → 0
        #expect(BenchBolusPlanner.milliunitsSnapped(0.024) == 0)       // below the 0.05 half-step → 0
        #expect(BenchBolusPlanner.milliunitsSnapped(0.025) == 50)      // half rounds away → 0.05 U
        #expect(BenchBolusPlanner.milliunitsSnapped(.nan) == 0)
        #expect(BenchBolusPlanner.milliunitsSnapped(.infinity) == 0)
        #expect(BenchBolusPlanner.milliunitsSnapped(-.infinity) == 0)
        #expect(BenchBolusPlanner.milliunitsSnapped(1e12) == UInt32.max)  // huge finite clamps, no trap
    }

    /// Carb metadata → Int must never trap (Int is 32-bit on watchOS) and clamps to the uint16 ceiling.
    @Test func safeCarbIntIsNonTrappingAndClamped() {
        #expect(BenchBolusPlanner.safeCarbInt(45) == 45)
        #expect(BenchBolusPlanner.safeCarbInt(nil) == 0)
        #expect(BenchBolusPlanner.safeCarbInt(-5) == 0)
        #expect(BenchBolusPlanner.safeCarbInt(.nan) == 0)
        #expect(BenchBolusPlanner.safeCarbInt(.infinity) == 0)
        #expect(BenchBolusPlanner.safeCarbInt(65535) == 65535)
        #expect(BenchBolusPlanner.safeCarbInt(70000) == 65535)
        #expect(BenchBolusPlanner.safeCarbInt(1e9) == 65535)          // used to overflow Int(_:) on watchOS
    }

    /// `plan()` end to end must fail SAFE (0 dose or capped) on every pathological input — never crash.
    @Test func planDoesNotTrapOnPathologicalInput() {
        // Non-finite carbs → sanity fail, zero dose, zero carb metadata.
        let inf = BenchBolusPlanner.plan(carbsGrams: .infinity, bgMgdl: nil, profile: profile())
        #expect(inf.sanityFailed && inf.totalMilliunits == 0 && inf.carbGrams == 0)
        let nan = BenchBolusPlanner.plan(carbsGrams: .nan, bgMgdl: nil, profile: profile())
        #expect(nan.sanityFailed && nan.totalMilliunits == 0)
        // Huge FINITE carbs → not a sanity failure, but capped and carb metadata clamped to 65535.
        let huge = BenchBolusPlanner.plan(carbsGrams: 1e9, bgMgdl: nil, profile: profile(), benchCapMilliunits: 2000)
        #expect(!huge.sanityFailed && huge.totalMilliunits == 2000 && huge.carbGrams == 65535)
        // Huge BG → dose capped at the default 25 U ceiling, no trap.
        let hugeBg = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 1_000_000, profile: profile())
        #expect(hugeBg.totalMilliunits == 25000)
        // Non-finite IOB is ignored safely (inf → treated as no reduction below carbs; NaN → no IOB).
        let infIob = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: profile(iob: .infinity))
        #expect(infIob.totalMilliunits == 3000 && infIob.iobMilliunits == 0)   // correction canceled, carbs stand
        let nanIob = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: profile(iob: .nan))
        #expect(nanIob.totalMilliunits == 4000)                                // NaN IOB == no IOB
    }

    // MARK: R3-E — invalid-profile matrix (only carbRatio==0 was covered)

    @Test func invalidIsfAndTargetSanityFailToZero() {
        let badIsf = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 10, isfMgdlPerUnit: 0, targetBgMgdl: 120, iobUnits: 0)
        let lowTarget = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 10, isfMgdlPerUnit: 50, targetBgMgdl: 30, iobUnits: 0)
        let highTarget = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: 10, isfMgdlPerUnit: 50, targetBgMgdl: 500, iobUnits: 0)
        for bad in [badIsf, lowTarget, highTarget] {
            let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: 170, profile: bad)
            #expect(p.sanityFailed && p.totalMilliunits == 0)
        }
    }

    // MARK: R3-E — bench cap below the minimum dispensable dose

    @Test func capBelowMinimumYieldsNonDeliverablePlan() {
        let p = BenchBolusPlanner.plan(carbsGrams: 30, bgMgdl: nil, profile: profile(), benchCapMilliunits: 40)
        #expect(p.totalMilliunits == 40)                              // capped below the 0.05 U (50 mu) floor
        #expect(p.foodMilliunits + p.correctionMilliunits == p.totalMilliunits)
        #expect(throws: InitiateBolusRequest.ValidationError.self) {  // request build refuses a sub-min dose
            _ = try BenchBolusPlanner.request(for: p, bolusID: 1)
        }
    }

    // MARK: R3-E — matrix cells the earlier suite missed

    @Test func atTargetNoCarbsIsZeroFood2() {
        let p = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 120, profile: profile())
        #expect(p.totalMilliunits == 0 && p.bitmask == F2)
        assertCoherent(p)
    }

    @Test func belowTargetWithPositiveIobFloorsAtZero() {
        // The case belowTargetWithIobFloorsAtZero's NAME implied but did not exercise (its IOB was 0).
        let p = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 100, profile: profile(iob: 1.0))
        // fromBG (100-120)/50 = -0.40, fromIOB -1.00 → correction -1.40, no carbs → floored at 0.
        #expect(p.totalMilliunits == 0)
        assertCoherent(p)
    }

    @Test func carbsZeroBehavesLikeNil() {
        let zero = BenchBolusPlanner.plan(carbsGrams: 0, bgMgdl: 170, profile: profile())
        let none = BenchBolusPlanner.plan(carbsGrams: nil, bgMgdl: 170, profile: profile())
        // No carb dose in either → FOOD2|CORRECTION, correction 1.00 U.
        #expect(zero.totalMilliunits == 1000 && none.totalMilliunits == 1000)
        #expect(zero.bitmask == (F2 | CORR) && none.bitmask == (F2 | CORR))
        assertCoherent(zero); assertCoherent(none)
    }
}
