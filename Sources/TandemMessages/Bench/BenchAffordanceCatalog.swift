import Foundation

// BenchAffordanceCatalog — the PURE, testable description of HOW the saline-bench coverage runner can
// drive each state-changing command *reversibly*, so a bench session can exercise the full delivery +
// signed-write surface and always leave the pump in its prior state.
//
// This file is transport-free and platform-free (no CoreBluetooth): it is metadata only. It NEVER
// composes or mutates dose/wire bytes — it only names, per command, (a) the reversibility STRATEGY,
// (b) the partner command that restores prior state (for a pair), (c) the READ that serves as the
// oracle, and (d) whether the runner can safely auto-drive it today. The executable
// `TandemBenchHarness` `coverage` runner (which CANNOT be unit-tested — CoreBluetooth aborts under
// `swift test`) is a thin driver over this catalog, exactly like `BenchCommandCatalog`.
//
// Safety model (owner decision 2026-08-23):
//   • DELIVERY affordances (the 14 `modifiesInsulinDelivery` commands) are gated behind the SINGLE flag
//     `PUMPX2_DELIVER_SALINE` and verified by the pump's OWN history-log / state read-back.
//   • NON-DELIVERY signed writes do NOT need `PUMPX2_DELIVER_SALINE`, but MUST be reversible and
//     recorded — never left in a changed state. The preferred discipline is capture→(set|re-apply)→
//     verify→restore, with a READ as the oracle.
//   • GENUINELY destructive / irreversible / session-disrupting commands (factory reset, shelf mode,
//     force-disconnect, CGM-session/pairing changes, undocumented test ops) are NEVER auto-fired. They
//     are classified `.manualOnly` here and surface as documented GAP cells the owner decides at the
//     bench — never silently dropped.

/// The reversibility STRATEGY the harness uses to exercise a command safely.
public enum BenchAffordanceKind: String, Sendable, Codable, CaseIterable {
    /// Deliver a small SALINE dose and confirm via the pump's OWN history-log read-back (bolus family).
    case deliverOracle
    /// Drive a command, then AUTO-RESTORE prior state by sending its partner command
    /// (Suspend↔Resume, SetTempRate↔StopTempRate, EnterFillTubingMode↔exit, EnterChangeCartridge↔exit).
    case reversiblePair
    /// Create a throwaway resource, confirm it appeared, then DELETE it to restore (CreateIDP→DeleteIDP).
    case throwawayCreateDelete
    /// Read the prior value, set a DIFFERENT value, verify it changed, then RESTORE the captured prior.
    case captureSetRestore
    /// Read the CURRENT value and re-send the SAME value (a provable no-op), then verify the read-back is
    /// unchanged. Reversible by construction — the setting never actually changes — while still proving the
    /// pump ACCEPTS the signed write and round-trips it.
    case captureReapply
    /// A signed accept/NACK probe with no persistent SETTING change: it is self-reversing (permission is
    /// released, a sound is cosmetic) or appends only a benign, non-therapy history entry.
    case benignProbe
    /// Destructive / irreversible / session-disrupting — NEVER auto-fired. Documented GAP; owner-only.
    case manualOnly
    /// Reversible in principle, but a safe generic driver is not yet wired (needs a bespoke read↔write
    /// mapping). Documented GAP; drive manually or in a follow-up.
    case bespokePending
}

/// Whether the command is DRIVEN directly (`primary`) or covered as the auto-restore half of a pair.
public enum BenchAffordanceRole: String, Sendable, Codable {
    case primary
    case restorePartner
}

/// Whether — and how — the coverage RUNNER can auto-drive this command TODAY.
public enum BenchDriveability: Sendable, Equatable {
    /// The runner has a wired, self-reversing driver → exercised (recorded pass/fail).
    case drivable
    /// Covered as the restore-half of the named primary's pair — recorded when that pair runs.
    case viaPrimaryPair(String)
    /// Driven as a CONTEXT step inside the named workflow (not standalone) — e.g. PrimeTubingSuspend is
    /// only meaningful during an active fill-tubing prime, so it is fired inside the EnterFillTubingMode↔Exit
    /// pair and recorded when that (saline-gated) pair runs. Documented GAP until that workflow runs.
    case viaWorkflow(String)
    /// Destructive / irreversible — GAP, documented, owner decides at the bench. (Reason for the runbook.)
    case manual(String)
    /// Reversible in principle; generic driver not yet wired — GAP, documented. (Reason for the runbook.)
    case pending(String)
}

/// Immutable, pure per-command reversibility metadata.
public struct BenchAffordance: Sendable, Equatable {
    /// The command being driven (a Swift request type name, e.g. "SetTempRateRequest").
    public let command: String
    public let kind: BenchAffordanceKind
    public let role: BenchAffordanceRole
    /// The partner command: for a `.primary` pair, the RESTORE command; for a `.restorePartner`, its
    /// PRIMARY. `nil` for self-restoring (captureSetRestore/captureReapply) and standalone kinds.
    public let partner: String?
    /// The READ command whose read-back is the oracle that state changed then restored (or delivered ==
    /// requested). `nil` where acceptance of the signed write is itself the check (benign probes).
    public let oracleRead: String?
    /// `true` ⇒ this affordance requires the `PUMPX2_DELIVER_SALINE` gate (a `modifiesInsulinDelivery`
    /// command). `false` ⇒ a non-delivery signed write, exercisable in any connected config.
    public let gatedOnSalineDelivery: Bool
    /// Whether / how the runner can auto-drive it today.
    public let driveability: BenchDriveability
    /// Human note describing HOW the harness drives it reversibly (or WHY it is manual/pending).
    public let note: String
}

/// The enumerated reversibility affordances for every state-changing command.
public enum BenchAffordanceCatalog {

    // Convenience constructors keep the big table below readable.
    private static func delivery(_ command: String, _ kind: BenchAffordanceKind,
                                 role: BenchAffordanceRole = .primary, partner: String? = nil,
                                 oracle: String?, drive: BenchDriveability = .drivable,
                                 _ note: String) -> BenchAffordance {
        BenchAffordance(command: command, kind: kind, role: role, partner: partner, oracleRead: oracle,
                        gatedOnSalineDelivery: true, driveability: drive, note: note)
    }
    private static func write(_ command: String, _ kind: BenchAffordanceKind,
                              role: BenchAffordanceRole = .primary, partner: String? = nil,
                              oracle: String? = nil, drive: BenchDriveability, _ note: String) -> BenchAffordance {
        BenchAffordance(command: command, kind: kind, role: role, partner: partner, oracleRead: oracle,
                        gatedOnSalineDelivery: false, driveability: drive, note: note)
    }

    /// The full affordance table, keyed by command name. Every `modifiesInsulinDelivery` command (14)
    /// and every non-delivery signed CONTROL write is present — the completeness test guards against drift.
    public static let all: [BenchAffordance] = [
        // ── DELIVERY (14) — gated behind PUMPX2_DELIVER_SALINE; oracle = pump's own history/state read ──
        // Bolus family — deliver a small saline dose, confirm via the pump's own recorded units.
        delivery("InitiateBolusRequest", .deliverOracle, oracle: "LastBolusStatusV2Request",
                 "deliver 0.10 u saline; poll LastBolusStatusV2 until recorded units == requested"),
        delivery("AdditionalBolusRequest", .deliverOracle, oracle: "LastBolusStatusV2Request",
                 "establish a small EXTENDED saline bolus, extend it via AdditionalBolus(bolusID), confirm accepted + history read-back"),
        // Cartridge-change mode — enter, confirm via LoadStatus, exit to restore (universal).
        delivery("EnterChangeCartridgeModeRequest", .reversiblePair, partner: "ExitChangeCartridgeModeRequest",
                 oracle: "LoadStatusRequest",
                 "enter cartridge-change mode, confirm LoadStatus reflects it, then exit to restore"),
        // Modes — capture current user-mode, toggle sleep, confirm change, restore prior (Mobi; CIQ must be ON).
        delivery("SetModesRequest", .captureSetRestore, oracle: "ControlIQInfoV1Request",
                 "capture currentUserModeType, toggle sleep mode, confirm it changed, then RESTORE the prior mode (needs Control-IQ ON)"),
        // Active IDP — capture active profile id, switch, confirm, restore (Mobi; needs ≥2 profiles).
        delivery("SetActiveIDPRequest", .captureSetRestore, oracle: "ProfileStatusRequest",
                 "capture ProfileStatus.activeIdpId, switch to another profile, confirm, then RESTORE the prior active IDP (needs ≥2 profiles)"),
        // Fill cannula — a one-way saline prime; exercise a small primeSize, confirm via LoadStatus (Mobi).
        delivery("FillCannulaRequest", .captureReapply, oracle: "LoadStatusRequest", drive: .drivable,
                 "dispense a small saline cannula prime, confirm accepted + LoadStatus; one-way (records, no reverse)"),
        // Fill-tubing mode — enter (primes tubing on saline), confirm, exit to restore (Mobi).
        delivery("EnterFillTubingModeRequest", .reversiblePair, partner: "ExitFillTubingModeRequest",
                 oracle: "LoadStatusRequest",
                 "enter fill-tubing mode (primes tubing on saline), confirm via LoadStatus, then exit to restore"),
        // Temp rate — set 80%/30m, confirm via TempRateStatus, stop to restore (Mobi; CIQ must be OFF).
        delivery("SetTempRateRequest", .reversiblePair, partner: "StopTempRateRequest",
                 oracle: "TempRateStatusRequest",
                 "set 80%/30m, confirm TempRateStatus.active + basalModified, then StopTempRate to restore (needs Control-IQ OFF)"),
        delivery("StopTempRateRequest", .reversiblePair, role: .restorePartner, partner: "SetTempRateRequest",
                 oracle: "TempRateStatusRequest", drive: .viaPrimaryPair("SetTempRateRequest"),
                 "the restore half of SetTempRate — recorded when that pair runs"),
        // Suspend/resume — suspend, confirm basal==0, resume to restore (Mobi).
        delivery("SuspendPumpingRequest", .reversiblePair, partner: "ResumePumpingRequest",
                 oracle: "CurrentBasalStatusRequest",
                 "suspend pumping, confirm CurrentBasalStatus shows delivery stopped, then Resume to restore"),
        delivery("ResumePumpingRequest", .reversiblePair, role: .restorePartner, partner: "SuspendPumpingRequest",
                 oracle: "CurrentBasalStatusRequest", drive: .viaPrimaryPair("SuspendPumpingRequest"),
                 "the restore half of SuspendPumping — recorded when that pair runs"),
        // IDP create/delete — create a throwaway profile, confirm count grew, delete it to restore (Mobi).
        delivery("CreateIDPRequest", .throwawayCreateDelete, partner: "DeleteIDPRequest",
                 oracle: "ProfileStatusRequest",
                 "create a throwaway IDP, confirm ProfileStatus count grew, then DELETE it to restore"),
        delivery("DeleteIDPRequest", .throwawayCreateDelete, role: .restorePartner, partner: "CreateIDPRequest",
                 oracle: "ProfileStatusRequest", drive: .viaPrimaryPair("CreateIDPRequest"),
                 "the delete half of the throwaway CreateIDP→DeleteIDP pair — recorded when that pair runs"),
        // Rename IDP — capture the active profile's name, rename to a temp, confirm, restore prior name (Mobi).
        delivery("RenameIDPRequest", .captureSetRestore, oracle: "IDPSettingsRequest",
                 "capture the active IDP name via IDPSettings, rename to a temp name, confirm, then RESTORE the prior name"),

        // ── Signed-write RESTORE PARTNERS that are NOT delivery-class (driven inside a delivery pair) ──
        write("ExitChangeCartridgeModeRequest", .reversiblePair, role: .restorePartner,
              partner: "EnterChangeCartridgeModeRequest", oracle: "LoadStatusRequest",
              drive: .viaPrimaryPair("EnterChangeCartridgeModeRequest"),
              "exits cartridge-change mode — the restore half of the EnterChangeCartridgeMode pair"),
        write("ExitFillTubingModeRequest", .reversiblePair, role: .restorePartner,
              partner: "EnterFillTubingModeRequest", oracle: "LoadStatusRequest",
              drive: .viaPrimaryPair("EnterFillTubingModeRequest"),
              "exits fill-tubing mode — the restore half of the EnterFillTubingMode pair"),

        // ── NON-DELIVERY signed writes — captureReapply (read → re-send SAME value → verify unchanged) ──
        write("ChangeTimeDateRequest", .captureReapply, oracle: "TimeSinceResetRequest", drive: .drivable,
              "read currentTime, re-set the clock to the SAME value (no-op), verify unchanged"),
        write("SetMaxBolusLimitRequest", .captureReapply, oracle: "GlobalMaxBolusSettingsRequest", drive: .drivable,
              "read GlobalMaxBolusSettings.maxBolus, re-apply the SAME limit, verify read-back unchanged"),
        write("SetMaxBasalLimitRequest", .captureReapply, oracle: "BasalLimitSettingsRequest", drive: .drivable,
              "read BasalLimitSettings.basalLimit, re-apply the SAME limit, verify read-back unchanged"),
        write("ChangeControlIQSettingsRequest", .captureReapply, oracle: "ControlIQInfoV1Request", drive: .drivable,
              "read Control-IQ enabled/weight/TDI, re-apply the SAME settings, verify read-back unchanged"),
        write("SetLowInsulinAlertRequest", .captureReapply, oracle: "PumpSettingsRequest", drive: .drivable,
              "read PumpSettings.lowInsulinThreshold, re-apply the SAME threshold, verify read-back unchanged"),

        // ── NON-DELIVERY signed writes — benignProbe (accept/NACK; self-reversing or benign append) ──
        write("BolusPermissionRequest", .benignProbe, partner: "BolusPermissionReleaseRequest", drive: .drivable,
              "signed accept/NACK proof — grants a bolusId, then released immediately (no dose)"),
        write("BolusPermissionReleaseRequest", .benignProbe, role: .restorePartner, partner: "BolusPermissionRequest",
              drive: .viaPrimaryPair("BolusPermissionRequest"),
              "the release half of the BolusPermission pair — recorded when that probe runs"),
        write("PlaySoundRequest", .benignProbe, drive: .drivable,
              "find-my-pump chime — cosmetic, no therapy or setting effect (risk .benign)"),
        write("UserInteractionRequest", .benignProbe, drive: .drivable,
              "marks a user interaction (empty cargo) — no setting/therapy change; accept/NACK probe"),
        write("RemoteCarbEntryRequest", .benignProbe, drive: .drivable,
              "records a benign carb entry (does not dose); appends a non-therapy history entry, no setting change"),
        write("RemoteBgEntryRequest", .benignProbe, drive: .drivable,
              "records a benign BG entry (useForCgmCalibration=false, so no recalibration); appends a non-therapy entry"),
        write("CancelBolusRequest", .benignProbe, drive: .drivable,
              "cancel with no active bolus — the pump cleanly reports already-delivered/invalid; proves the signed cancel path, no state change"),

        // ── NON-DELIVERY signed writes — manualOnly (destructive / irreversible / session-disrupting) ──
        write("ActivateShelfModeRequest", .manualOnly, drive: .manual("activates shelf/storage mode — takes the pump offline"),
              "MANUAL: shelf mode powers the pump down — never auto-fired"),
        write("DisconnectPumpRequest", .manualOnly, drive: .manual("force-disconnects the BLE session — drops the link the sweep needs"),
              "MANUAL: force-disconnect drops the session mid-sweep"),
        write("FactoryResetRequest", .manualOnly, drive: .manual("ERASES the pump to factory state — irreversible"),
              "MANUAL: factory reset is irreversible — owner-only"),
        write("FactoryResetBRequest", .manualOnly, drive: .manual("ERASES the pump to factory state (B variant) — irreversible"),
              "MANUAL: factory reset (B) is irreversible — owner-only"),
        write("SendTipsControlGenericTestRequest", .manualOnly, drive: .manual("undocumented internal test op — effect unknown"),
              "MANUAL: undocumented test op — effect on pump state unknown"),
        write("StreamDataPreflightRequest", .manualOnly, drive: .manual("internal data-stream preflight (minApi API_FUTURE) — not exercisable on known firmware"),
              "MANUAL: stream preflight — API_FUTURE floored; defers on all known firmware"),
        write("SetG6TransmitterIdRequest", .manualOnly, drive: .manual("changes the paired CGM transmitter id — disrupts the sensor pairing"),
              "MANUAL: changes CGM transmitter pairing — owner-only, CGM session"),
        write("StartDexcomG6SensorSessionRequest", .manualOnly, drive: .manual("starts a CGM sensor session — disrupts an in-progress sensor"),
              "MANUAL: starts a CGM sensor session — owner-only"),
        write("StopDexcomCGMSensorSessionRequest", .manualOnly, drive: .manual("stops the CGM sensor session — disrupts an in-progress sensor"),
              "MANUAL: stops the CGM sensor session — owner-only"),
        write("SetSensorTypeRequest", .manualOnly, drive: .manual("switches the CGM sensor type — disrupts the active sensor"),
              "MANUAL: changes CGM sensor type — owner-only"),
        write("SetDexcomG7PairingCodeRequest", .manualOnly, drive: .manual("changes the G7 pairing code — disrupts the sensor pairing"),
              "MANUAL: changes CGM G7 pairing — owner-only"),

        // ── NON-DELIVERY signed writes — captureReapply (bespoke read↔write no-op, now WIRED) ──
        // Each reads its paired setting and re-applies the SAME value with the write's per-field CHANGE
        // bitmask = 0 ("apply no field"), so the pump changes NOTHING while proving it accepts + round-trips
        // the signed write. The pure read→write field mapping lives in `BenchReapplyMapping` (unit-tested).
        write("SetAutoOffAlertRequest", .captureReapply, oracle: "PumpSettingsRequest", drive: .drivable,
              "read PumpSettings auto-off enabled+duration, re-apply the SAME values with the change-bitmask 0 (applies nothing), verify unchanged"),
        write("SetPumpSoundsRequest", .captureReapply, oracle: "PumpGlobalsRequest", drive: .drivable,
              "read PumpGlobals annunciations, re-apply the SAME values with changeBitmask 0 (applies nothing), verify the readable annunciations unchanged"),
        // CGM-alert config (needs a CGM session → plan() DEFERS these without a sensor; wired regardless).
        write("CgmHighLowAlertRequest", .captureReapply, oracle: "CGMGlucoseAlertSettingsRequest", drive: .drivable,
              "read CGM high+low glucose-alert settings, re-apply the SAME values (both alertTypes) with change-bitmask 0, verify unchanged (CGM session → DEFERRED without a sensor)"),
        write("CgmOutOfRangeAlertRequest", .captureReapply, oracle: "CGMOORAlertSettingsRequest", drive: .drivable,
              "read CGM out-of-range alert settings, re-apply the SAME values with change-bitmask 0, verify unchanged (CGM session → DEFERRED without a sensor)"),
        write("CgmRiseFallAlertRequest", .captureReapply, oracle: "CGMRateAlertSettingsRequest", drive: .drivable,
              "read CGM rise+fall rate-alert settings, re-apply the SAME values (both alertTypes) with change-bitmask 0, verify unchanged (CGM session → DEFERRED without a sensor)"),

        // ── NON-DELIVERY signed write — context step inside the fill-tubing prime workflow (now WIRED) ──
        write("PrimeTubingSuspendRequest", .reversiblePair, partner: "EnterFillTubingModeRequest",
              oracle: "LoadStatusRequest", drive: .viaWorkflow("EnterFillTubingModeRequest"),
              "context step inside the fill-tubing prime: enter fill-tubing → suspend the active prime → exit to restore; recorded when the EnterFillTubingMode saline pair runs (Mobi, saline-gated)"),

        // ── NON-DELIVERY signed writes — bespokePending (STILL a documented GAP; honest reasons) ──
        // These remain manual because a VERIFIABLE no-op cannot be built from the available reads (or the
        // write edits a live dose-path profile / has no read-back at all). See docs/BENCH-COVERAGE.md.
        write("SetPumpAlertSnoozeRequest", .bespokePending,
              drive: .pending("no read-back exposes the snooze enabled/duration setting, so it is genuinely unrecoverable — cannot be made a verifiable no-op"),
              "PENDING: no corresponding read → genuinely unrecoverable; documented manual"),
        write("SetQuickBolusSettingsRequest", .bespokePending, oracle: "PumpGlobalsRequest",
              drive: .pending("the write's 5-byte increment `magic` must EXACTLY match a known QuickBolusIncrement enum and the modeRaw↔magic mapping is not exposed by PumpGlobals; no change-bitmask to guarantee a no-op — echoing could alter the increment"),
              "PENDING: opaque increment magic + no change-bitmask → cannot prove a no-op re-apply"),
        write("SetSleepScheduleRequest", .bespokePending, oracle: "ControlIQSleepScheduleRequest",
              drive: .pending("ControlIQSleepSchedule exposes the 6 schedule bytes per slot but NOT the write's trailing `flag` byte, which has no documented semantics and no read-back — re-applying it cannot be proven a no-op (Mobi-only, Control-IQ-sleep-affecting)"),
              "PENDING: undocumented `flag` byte not in the read-back → cannot prove a no-op"),
        write("SetBgReminderRequest", .bespokePending, oracle: "RemindersRequest",
              drive: .pending("Reminders exposes only the high/low BG thresholds, NOT the per-reminder enabled/minutes/type the write sets, so a no-op cannot be verified for the functional fields"),
              "PENDING: Reminders read does not expose the reminder enabled/minutes/type fields"),
        write("SetSiteChangeReminderRequest", .bespokePending, oracle: "RemindersRequest",
              drive: .pending("Reminders exposes only siteChangeDays, NOT the write's enable/timeOfDay, so a no-op cannot be verified"),
              "PENDING: Reminders read does not expose enable/timeOfDay"),
        write("SetMissedMealBolusReminderRequest", .bespokePending, oracle: "RemindersRequest",
              drive: .pending("Reminders exposes none of this write's fields (index/enabled/window/days), so a no-op cannot be verified"),
              "PENDING: Reminders read exposes none of the missed-meal-reminder fields"),
        write("SetIDPSegmentRequest", .bespokePending, oracle: "IDPSegmentRequest",
              drive: .pending("edits a LIVE basal/delivery profile segment (basal rate, carb ratio, ISF, target); IDPSegment does not expose profileIndex and the operation selector must be MODIFY — a mis-map silently rewrites the dose-path profile, so it is not auto-fired"),
              "PENDING: edits a live delivery-profile segment; profileIndex/operation not safely recoverable"),
        write("SetIDPSettingsRequest", .bespokePending, oracle: "IDPSettingsRequest",
              drive: .pending("edits live insulin-duration (IOB/dose-path) + carb-entry; IDPSettings does not expose profileIndex and the changeType selector is required — a mis-map silently rewrites a dose-path setting, so it is not auto-fired"),
              "PENDING: edits live insulin-duration; profileIndex/changeType not safely recoverable"),
    ]

    /// Name → affordance.
    public static let byName: [String: BenchAffordance] = {
        var m: [String: BenchAffordance] = [:]
        for a in all { m[a.command] = a }
        return m
    }()

    /// The affordance for a command, or nil if none is classified.
    public static func affordance(for command: String) -> BenchAffordance? { byName[command] }

    /// Whether the runner can auto-drive this command directly today (a wired, self-reversing driver).
    public static func isRunnerDrivable(_ command: String) -> Bool {
        byName[command]?.driveability == .drivable
    }

    // MARK: - Convenience slices (used by tests + the runbook)

    /// Every delivery-class affordance (the 14 `modifiesInsulinDelivery` commands).
    public static var deliveryAffordances: [BenchAffordance] { all.filter { $0.gatedOnSalineDelivery } }

    /// Non-delivery signed writes the runner drives directly (the "grown" auto-fire allowlist).
    public static var drivableSignedWrites: [BenchAffordance] {
        all.filter { !$0.gatedOnSalineDelivery && $0.driveability == .drivable }
    }

    /// Commands classified `.manualOnly` — documented GAPs the owner decides at the bench.
    public static var manualOnly: [BenchAffordance] {
        all.filter { if case .manual = $0.driveability { return true } else { return false } }
    }

    /// Commands with a reversible affordance not yet wired (documented GAPs).
    public static var bespokePending: [BenchAffordance] {
        all.filter { if case .pending = $0.driveability { return true } else { return false } }
    }
}
