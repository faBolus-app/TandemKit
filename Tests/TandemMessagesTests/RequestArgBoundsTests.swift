import Testing
import TandemMessages

/// CX-T-07: restore upstream request-argument bounds validation at the TandemKit construction boundary.
/// Today `SetTempRateRequest(minutes:percent:)` encodes `percent` via `Bytes.firstTwoBytesLittleEndian`,
/// which silently TRUNCATES (percent 65536 -> 0%) — turning an out-of-range value into a DIFFERENT valid
/// command instead of rejecting it. `SetMaxBolusLimitRequest`/`SetMaxBasalLimitRequest` had no bounds at
/// all; `FillCannulaRequest` had no init bound (0 is upstream-invalid). Mirrors the `InitiateBolusRequest`
/// throwing convention (PX-07): validate BEFORE any truncating byte-encode helper.
///
/// Owner decision (2026-08-25, see OWNER-DECISIONS.md 15-05 Task 1): ALIGN UP — the max-bolus/max-basal
/// LIMIT floor is raised to pumpX2's documented 1.0 U (1000 mU / 1000 mU/hr), CONSERVATIVE/UNVERIFIED.
@Suite struct RequestArgBoundsTests {

    // MARK: - SetTempRateRequest (unconditional — no owner-decision dependency)

    @Test func tempRateRejectsPercentThatWouldTruncateToZero() {
        // Today: Bytes.firstTwoBytesLittleEndian(65536) masks to 0x0000 -> silently becomes 0%.
        #expect(throws: SetTempRateRequest.ValidationError.percentOutOfRange(65536)) {
            _ = try SetTempRateRequest(minutes: 30, percent: 65536)
        }
    }

    @Test func tempRateRejectsMinutesBelowFloor() {
        #expect(throws: SetTempRateRequest.ValidationError.minutesOutOfRange(14)) {
            _ = try SetTempRateRequest(minutes: 14, percent: 50)
        }
    }

    @Test func tempRateRejectsMinutesAboveCeiling() {
        #expect(throws: SetTempRateRequest.ValidationError.minutesOutOfRange(4321)) {
            _ = try SetTempRateRequest(minutes: 4321, percent: 50)
        }
    }

    @Test func tempRateRejectsPercentAboveCeiling() {
        #expect(throws: SetTempRateRequest.ValidationError.percentOutOfRange(251)) {
            _ = try SetTempRateRequest(minutes: 30, percent: 251)
        }
    }

    @Test func tempRateAcceptsInRangeAndEncodesByteStable() throws {
        let req = try SetTempRateRequest(minutes: 30, percent: 150)
        // Boundary values must also construct successfully.
        _ = try SetTempRateRequest(minutes: 15, percent: 0)
        _ = try SetTempRateRequest(minutes: 4320, percent: 250)
        #expect(req.cargo == Bytes.combine(Bytes.toUint32(UInt32(30 * 60_000)), Bytes.firstTwoBytesLittleEndian(150)))
    }

    // MARK: - FillCannulaRequest (unconditional)

    @Test func fillCannulaRejectsZero() {
        // 0 is upstream-invalid (pumpX2 requires primeSizeMilliUnits > 0) — never a valid "no-op" fill.
        #expect(throws: FillCannulaRequest.ValidationError.primeSizeOutOfRange(0)) {
            _ = try FillCannulaRequest(primeSize: 0)
        }
    }

    @Test func fillCannulaRejectsNegative() {
        #expect(throws: FillCannulaRequest.ValidationError.primeSizeOutOfRange(-1)) {
            _ = try FillCannulaRequest(primeSize: -1)
        }
    }

    @Test func fillCannulaRejectsAboveCeiling() {
        #expect(throws: FillCannulaRequest.ValidationError.primeSizeOutOfRange(3001)) {
            _ = try FillCannulaRequest(primeSize: 3001)
        }
    }

    @Test func fillCannulaAcceptsInRangeAndEncodesByteStable() throws {
        let req = try FillCannulaRequest(primeSize: 300)
        _ = try FillCannulaRequest(primeSize: 1)      // floor
        _ = try FillCannulaRequest(primeSize: 3000)   // ceiling
        #expect(req.cargo == Bytes.firstTwoBytesLittleEndian(300))
    }

    // MARK: - SetMaxBolusLimitRequest / SetMaxBasalLimitRequest (owner decision: option-a, ALIGN UP)

    @Test func maxBolusLimitRejectsBelowNewFloor() {
        // Below the app's OLD 0.05u/50mU floor -> also below the kit's new 1000 mU floor.
        #expect(throws: SetMaxBolusLimitRequest.ValidationError.maxBolusMilliunitsOutOfRange(500)) {
            _ = try SetMaxBolusLimitRequest(maxBolusMilliunits: 500)
        }
    }

    @Test func maxBolusLimitRejectsAboveCeiling() {
        #expect(throws: SetMaxBolusLimitRequest.ValidationError.maxBolusMilliunitsOutOfRange(25001)) {
            _ = try SetMaxBolusLimitRequest(maxBolusMilliunits: 25001)
        }
    }

    @Test func maxBolusLimitAcceptsInRangeAndEncodesByteStable() throws {
        let req = try SetMaxBolusLimitRequest(maxBolusMilliunits: 25000)
        _ = try SetMaxBolusLimitRequest(maxBolusMilliunits: 1000)   // floor
        #expect(req.cargo == Bytes.firstTwoBytesLittleEndian(25000))
    }

    @Test func maxBasalLimitRejectsBelowFloor() {
        #expect(throws: SetMaxBasalLimitRequest.ValidationError.maxHourlyBasalMilliunitsOutOfRange(999)) {
            _ = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 999)
        }
    }

    @Test func maxBasalLimitRejectsAboveCeiling() {
        #expect(throws: SetMaxBasalLimitRequest.ValidationError.maxHourlyBasalMilliunitsOutOfRange(15001)) {
            _ = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 15001)
        }
    }

    @Test func maxBasalLimitAcceptsInRangeAndEncodesByteStable() throws {
        let req = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 15000)
        _ = try SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: 1000)   // floor
        #expect(req.cargo == Bytes.toUint32(15000))
    }
}
