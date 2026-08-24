import Testing
import Foundation
@testable import TandemMessages

// Pure-logic tests for the bespoke read→write no-op mappings (BenchReapplyMapping) and the affordance-catalog
// conversions that promote 6 formerly-`bespokePending` signed writes to real reversible affordances. These
// prove the parts the executable coverage runner CANNOT prove under `swift test` (CoreBluetooth aborts there):
// that each mapping echoes the paired read's CURRENT value into the SET request and sets the per-field CHANGE
// bitmask to 0 (so the write changes nothing), and that the catalog + classifier now treat the converted
// commands as drivable/context and keep the genuinely-unrecoverable ones honestly pending. Transport-free.

@Suite struct BenchReapplyMappingTests {

    /// SetAutoOffAlert: enable+duration echoed from PumpSettings; change-bitmask 0 (applies nothing).
    @Test func autoOffNoOpEchoesPumpSettingsWithZeroBitmask() {
        // PumpSettings 9B: low@0, cannula@1, autoShutdownEnabled@2, autoShutdownDuration short@3, ...
        let s = PumpSettingsResponse(cargo: [5, 30, 1, 120, 0, 0, 0, 0, 0])
        #expect(s.autoShutdownEnabled == 1)
        #expect(s.autoShutdownDuration == 120)
        let w = BenchReapplyMapping.autoOffNoOp(from: s)
        #expect(w.enableAutoOff == true)                 // echoes autoShutdownEnabled != 0
        #expect(w.autoOffDuration == 120)                // echoes autoShutdownDuration
        #expect(w.bitmask == 0)                          // change-nothing selector
        // Cargo is [enable, duration LE(2), bitmask] — last byte (the change selector) must be 0.
        #expect(w.cargo.count == 4)
        #expect(w.cargo.last == 0)
    }

    /// SetPumpSounds: readable annunciations echoed from PumpGlobals; changeBitmask 0 (applies nothing).
    @Test func pumpSoundsNoOpEchoesAnnunciationsWithZeroChangeBitmask() {
        // PumpGlobals 14B: ... quickBolusAnnun@8, bolusAnnun@9, reminderAnnun@10, alertAnnun@11, alarmAnnun@12.
        let g = PumpGlobalsResponse(cargo: [0, 0, 0, 0, 0, 0, 0, 9, 1, 2, 3, 0, 1, 0])
        #expect(g.quickBolusAnnun == 1 && g.bolusAnnun == 2 && g.reminderAnnun == 3 && g.alertAnnun == 0 && g.alarmAnnun == 1)
        let w = BenchReapplyMapping.pumpSoundsNoOp(from: g)
        #expect(w.quickBolusAnnunRaw == 1)
        #expect(w.generalAnnunRaw == 2)                  // best-available = bolusAnnun (not applied)
        #expect(w.reminderAnnunRaw == 3)
        #expect(w.alertAnnunRaw == 0)
        #expect(w.alarmAnnunRaw == 1)
        #expect(w.changeBitmaskRaw == 0)                 // change-nothing selector
        #expect(w.cargo.count == 9)
        #expect(w.cargo.last == 0)                       // changeBitmask byte is the last cargo byte
    }

    /// CgmHighLowAlert: one no-op write per alertType (HIGH=0, LOW=1), each echoing its read value + bitmask 0.
    @Test func cgmHighLowNoOpPairEchoesBothAlertTypes() {
        // CGMGlucoseAlert 12B: highThr short@0, highEn@2, highRep short@3, highBmask@5, lowThr short@6,
        //                      lowEn@8, lowRep short@9, lowBmask@11.
        let r = CGMGlucoseAlertSettingsResponse(cargo: [200, 0, 1, 120, 0, 7, 70, 0, 1, 60, 0, 7])
        #expect(r.highGlucoseAlertThreshold == 200 && r.highGlucoseAlertEnabled == 1 && r.highGlucoseRepeatDuration == 120)
        #expect(r.lowGlucoseAlertThreshold == 70 && r.lowGlucoseAlertEnabled == 1 && r.lowGlucoseRepeatDuration == 60)
        let ws = BenchReapplyMapping.cgmHighLowNoOps(from: r)
        #expect(ws.count == 2)
        let high = ws[0], low = ws[1]
        #expect(high.alertType == 0 && high.threshold == 200 && high.repeatDurationMinutes == 120 && high.enableAlert == true && high.bitmask == 0)
        #expect(low.alertType == 1 && low.threshold == 70 && low.repeatDurationMinutes == 60 && low.enableAlert == true && low.bitmask == 0)
        // Every write's last cargo byte (the change selector) is 0.
        #expect(ws.allSatisfy { $0.cargo.count == 7 && $0.cargo.last == 0 })
    }

    /// CgmRiseFallAlert: one no-op write per alertType (RISE=0, FALL=1), echoing rate + enabled + bitmask 0.
    @Test func cgmRiseFallNoOpPairEchoesBothAlertTypes() {
        // CGMRateAlert 6B: riseThr@0, riseEn@1, riseBmask@2, fallThr@3, fallEn@4, fallBmask@5.
        let r = CGMRateAlertSettingsResponse(cargo: [3, 1, 3, 2, 0, 3])
        let ws = BenchReapplyMapping.cgmRiseFallNoOps(from: r)
        #expect(ws.count == 2)
        let rise = ws[0], fall = ws[1]
        #expect(rise.alertType == 0 && rise.enable == true && rise.mgPerDl == 3 && rise.bitmask == 0)
        #expect(fall.alertType == 1 && fall.enable == false && fall.mgPerDl == 2 && fall.bitmask == 0)
        #expect(ws.allSatisfy { $0.cargo.count == 4 && $0.cargo.last == 0 })
    }

    /// CgmOutOfRangeAlert: enable+delay echoed from the read; change-bitmask 0.
    @Test func cgmOutOfRangeNoOpEchoesReadWithZeroBitmask() {
        // CGMOOR 3B: threshold@0, enabled@1, bitmask@2.
        let r = CGMOORAlertSettingsResponse(cargo: [20, 1, 3])
        let w = BenchReapplyMapping.cgmOutOfRangeNoOp(from: r)
        #expect(w.enable == true)                        // echoes sensorTimeoutAlertEnabled != 0
        #expect(w.alertDelay == 20)                      // echoes sensorTimeoutAlertThreshold
        #expect(w.bitmask == 0)                          // change-nothing selector
        #expect(w.cargo.count == 3 && w.cargo.last == 0)
    }

    /// A disabled read round-trips too: enabled=0 stays 0, and the change-bitmask stays 0 (still a no-op).
    @Test func mappingsPreserveDisabledState() {
        let s = PumpSettingsResponse(cargo: [5, 30, 0, 0, 0, 0, 0, 0, 0])   // auto-off disabled
        let w = BenchReapplyMapping.autoOffNoOp(from: s)
        #expect(w.enableAutoOff == false && w.autoOffDuration == 0 && w.bitmask == 0)

        let oor = CGMOORAlertSettingsResponse(cargo: [0, 0, 0])
        let wo = BenchReapplyMapping.cgmOutOfRangeNoOp(from: oor)
        #expect(wo.enable == false && wo.alertDelay == 0 && wo.bitmask == 0)
    }
}

// The affordance-catalog conversions: 6 formerly-bespoke writes are now real affordances (5 drivable
// captureReapply + 1 context-within-workflow), and the 8 genuinely-unrecoverable ones stay honestly pending.
@Suite struct BenchBespokeConversionTests {

    private func aff(_ n: String) -> BenchAffordance { BenchAffordanceCatalog.affordance(for: n)! }
    private func cmd(_ n: String) -> BenchCommand { BenchCommandCatalog.all.first { $0.name == n }! }
    private func plan(_ n: String, _ cfg: BenchSessionConfig) -> BenchPlan { BenchCoverage.plan(for: cmd(n), in: cfg) }

    /// The 5 no-op-drivable writes are captureReapply + `.drivable`, each with its paired read as oracle.
    @Test func fiveWritesConvertedToDrivableCaptureReapply() {
        let expected: [String: String] = [
            "SetAutoOffAlertRequest": "PumpSettingsRequest",
            "SetPumpSoundsRequest": "PumpGlobalsRequest",
            "CgmHighLowAlertRequest": "CGMGlucoseAlertSettingsRequest",
            "CgmOutOfRangeAlertRequest": "CGMOORAlertSettingsRequest",
            "CgmRiseFallAlertRequest": "CGMRateAlertSettingsRequest",
        ]
        for (name, oracle) in expected {
            #expect(aff(name).kind == .captureReapply, "\(name) should be captureReapply")
            #expect(aff(name).driveability == .drivable, "\(name) should be runner-drivable")
            #expect(aff(name).oracleRead == oracle, "\(name) oracle should be \(oracle)")
            #expect(!aff(name).gatedOnSalineDelivery, "\(name) is a non-delivery signed write")
            #expect(BenchAffordanceCatalog.isRunnerDrivable(name), "\(name) must be drivable")
        }
    }

    /// PrimeTubingSuspend is a context step inside the fill-tubing prime workflow (not standalone).
    @Test func primeTubingSuspendIsViaWorkflow() {
        #expect(aff("PrimeTubingSuspendRequest").driveability == .viaWorkflow("EnterFillTubingModeRequest"))
        #expect(!BenchAffordanceCatalog.isRunnerDrivable("PrimeTubingSuspendRequest"))
        // plan() gaps it (documented) — recorded only when the saline fill-tubing pair runs.
        if case .gap(let r) = plan("PrimeTubingSuspendRequest", BenchCoveragePlanTests.mobiSalineCgm) {
            #expect(r.contains("context step") && r.contains("EnterFillTubingMode"))
        } else { Issue.record("PrimeTubingSuspend should be a context gap in plan()") }
    }

    /// The 8 genuinely-unrecoverable / dose-path-editing writes stay honestly `bespokePending`.
    @Test func eightRemainHonestlyPending() {
        let stillPending: Set<String> = [
            "SetPumpAlertSnoozeRequest", "SetQuickBolusSettingsRequest", "SetSleepScheduleRequest",
            "SetBgReminderRequest", "SetSiteChangeReminderRequest", "SetMissedMealBolusReminderRequest",
            "SetIDPSegmentRequest", "SetIDPSettingsRequest",
        ]
        let pending = Set(BenchAffordanceCatalog.bespokePending.map { $0.command })
        #expect(pending == stillPending, "bespokePending drifted: \(pending.sorted())")
        // None of the converted 6 remain pending.
        for n in ["SetAutoOffAlertRequest", "SetPumpSoundsRequest", "CgmHighLowAlertRequest",
                  "CgmOutOfRangeAlertRequest", "CgmRiseFallAlertRequest", "PrimeTubingSuspendRequest"] {
            #expect(!pending.contains(n), "\(n) should no longer be pending")
        }
    }

    /// The derived auto-fire allowlist GREW to include the 5 new non-CGM+CGM drivable writes.
    @Test func allowlistGrewWithConvertedWrites() {
        let allow = BenchCommandCatalog.benchExercisableSignedWrites
        for n in ["SetAutoOffAlertRequest", "SetPumpSoundsRequest", "CgmHighLowAlertRequest",
                  "CgmOutOfRangeAlertRequest", "CgmRiseFallAlertRequest"] {
            #expect(allow.contains(n), "\(n) should now be runner-drivable")
        }
        // Still excludes the pending + destructive + delivery ones.
        #expect(!allow.contains("SetQuickBolusSettingsRequest"))
        #expect(!allow.contains("SetPumpAlertSnoozeRequest"))
        #expect(!allow.contains("PrimeTubingSuspendRequest"))   // via-workflow, not directly drivable
    }

    /// Classifier gating: the 2 non-CGM writes exercise in ANY connected config; the 3 CGM writes DEFER
    /// without a sensor and exercise with one; PrimeTubingSuspend gaps everywhere (context step).
    @Test func planGatesConvertedWritesCorrectly() {
        // Non-CGM captureReapply: exercisable on the no-cartridge/no-CGM t:slim. Uses the newer API-3.4 t:slim
        // because SetAutoOffAlert/SetPumpSounds are bench-observed op-77-unsupported on tslim ≤2.5 (T-1) and
        // therefore correctly DEFER there — the affordance-drivability being tested holds where they're supported.
        #expect(plan("SetAutoOffAlertRequest", BenchCoveragePlanTests.newTslim) == .exercise(.signedWrite))
        #expect(plan("SetPumpSoundsRequest", BenchCoveragePlanTests.newTslim) == .exercise(.signedWrite))
        // CGM captureReapply: DEFERRED without a sensor, exercisable with one.
        for n in ["CgmHighLowAlertRequest", "CgmOutOfRangeAlertRequest", "CgmRiseFallAlertRequest"] {
            if case .deferred(let r) = plan(n, BenchCoveragePlanTests.oldTslim) {
                #expect(r.contains("CGM"), "\(n) defer reason should mention CGM")
            } else { Issue.record("\(n) should DEFER without a CGM sensor") }
            #expect(plan(n, BenchCoveragePlanTests.mobiSalineCgm) == .exercise(.signedWrite),
                    "\(n) should exercise on a CGM-present session")
        }
    }
}
