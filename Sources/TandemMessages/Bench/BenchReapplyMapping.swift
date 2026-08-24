import Foundation

// BenchReapplyMapping — PURE, unit-testable read→write field mappings that build a provable NO-OP
// re-apply for each newly-converted bespoke signed-write affordance. Given the pump's CURRENT setting
// (a parsed READ response), each function returns the SET request(s) that re-apply the SAME value, so
// sending them changes NOTHING on the pump while proving it accepts + round-trips the signed write.
//
// Two independent safety layers make every mapping a provable no-op:
//   1. Every echoed field is taken VERBATIM from the paired read, so re-applying equals the current value.
//   2. The pump's documented per-field CHANGE bitmask (the trailing byte of each of these writes) is set
//      to 0 = "apply no field". Even if a field were mis-mapped, the pump still changes nothing. The
//      runner additionally re-reads and verifies the readable fields are unchanged after the write.
//
// The change-bitmask semantics and the CGM alertType selectors below are taken from the vendored upstream
// pumpX2 request classes (vendor/pumpx2-oracle/.../request/control/*.java). They are declared HERE (in
// bench-only code) rather than on the protocol request structs so this work touches no wire encode/decode.
//
// This file is transport-free (no CoreBluetooth) so `swift test` can prove the mapping + no-op invariant.
// It ONLY constructs existing request structs via their public initializers — it never composes wire bytes
// directly and never alters any message's encode/decode.

public enum BenchReapplyMapping {

    /// A "change nothing" bitmask. Each of these writes' trailing byte is a per-field CHANGE selector
    /// (upstream: bit set ⇒ apply that field); 0 means "apply no field", making the write a guaranteed
    /// no-op regardless of the other bytes. Belt-and-suspenders with echoing the current values.
    public static let changeNothingBitmask = 0

    // CGM alert-type selectors (upstream constants: CgmHighLowAlertRequest ALERT_TYPE_HIGH/LOW,
    // CgmRiseFallAlertRequest ALERT_TYPE_RISE/FALL).
    public static let cgmAlertTypeHigh = 0
    public static let cgmAlertTypeLow = 1
    public static let cgmAlertTypeRise = 0
    public static let cgmAlertTypeFall = 1

    /// SetAutoOffAlert no-op from the current PumpSettings read. `enable`+`duration` are echoed and the
    /// change bitmask is 0 (applies nothing). Reversible by construction; verify via a PumpSettings re-read.
    /// NOTE: the write's own bitmask byte is a *change selector*, not a stored value (upstream doc:
    /// "bits: 0=enableAutoOff, 1=autoOffDuration"), so the read not exposing it does not block a no-op.
    public static func autoOffNoOp(from s: PumpSettingsResponse) -> SetAutoOffAlertRequest {
        SetAutoOffAlertRequest(enableAutoOff: s.autoShutdownEnabled != 0,
                               autoOffDuration: s.autoShutdownDuration,
                               bitmask: changeNothingBitmask)
    }

    /// SetPumpSounds no-op from the current PumpGlobals read. The four readable per-category annunciations
    /// (quick-bolus / reminder / alert / alarm) are echoed; `changeBitmask` is 0 so nothing is applied.
    /// The `general` and CGM annunciation bytes are not exposed by PumpGlobals, but with changeBitmask 0
    /// they are never applied. The runner verifies the four readable annunciations via a re-read.
    public static func pumpSoundsNoOp(from g: PumpGlobalsResponse) -> SetPumpSoundsRequest {
        SetPumpSoundsRequest(quickBolusAnnunRaw: g.quickBolusAnnun,
                             generalAnnunRaw: g.bolusAnnun,   // best-available; not applied (changeBitmask 0)
                             reminderAnnunRaw: g.reminderAnnun,
                             alertAnnunRaw: g.alertAnnun,
                             alarmAnnunRaw: g.alarmAnnun,
                             cgmAlertAnnunA: 0, cgmAlertAnnunB: 0,   // not read-exposed; not applied
                             changeBitmaskRaw: changeNothingBitmask)
    }

    /// CgmHighLowAlert no-op pair (HIGH + LOW) from the current CGM glucose-alert read. Each write echoes
    /// its threshold / repeat-duration / enabled with change-bitmask 0. Requires a CGM session (else the
    /// cell is DEFERRED). Two writes because one CgmHighLowAlert message targets one alertType.
    public static func cgmHighLowNoOps(from r: CGMGlucoseAlertSettingsResponse) -> [CgmHighLowAlertRequest] {
        [ CgmHighLowAlertRequest(alertType: cgmAlertTypeHigh,
                                 threshold: r.highGlucoseAlertThreshold,
                                 repeatDurationMinutes: r.highGlucoseRepeatDuration,
                                 enableAlert: r.highGlucoseAlertEnabled != 0,
                                 bitmask: changeNothingBitmask),
          CgmHighLowAlertRequest(alertType: cgmAlertTypeLow,
                                 threshold: r.lowGlucoseAlertThreshold,
                                 repeatDurationMinutes: r.lowGlucoseRepeatDuration,
                                 enableAlert: r.lowGlucoseAlertEnabled != 0,
                                 bitmask: changeNothingBitmask) ]
    }

    /// CgmRiseFallAlert no-op pair (RISE + FALL) from the current CGM rate-alert read.
    public static func cgmRiseFallNoOps(from r: CGMRateAlertSettingsResponse) -> [CgmRiseFallAlertRequest] {
        [ CgmRiseFallAlertRequest(alertType: cgmAlertTypeRise, enable: r.riseRateEnabled != 0,
                                  mgPerDl: r.riseRateThreshold, bitmask: changeNothingBitmask),
          CgmRiseFallAlertRequest(alertType: cgmAlertTypeFall, enable: r.fallRateEnabled != 0,
                                  mgPerDl: r.fallRateThreshold, bitmask: changeNothingBitmask) ]
    }

    /// CgmOutOfRangeAlert no-op from the current CGM out-of-range read. All three fields map cleanly.
    public static func cgmOutOfRangeNoOp(from r: CGMOORAlertSettingsResponse) -> CgmOutOfRangeAlertRequest {
        CgmOutOfRangeAlertRequest(enable: r.sensorTimeoutAlertEnabled != 0,
                                  alertDelay: r.sensorTimeoutAlertThreshold,
                                  bitmask: changeNothingBitmask)
    }
}
