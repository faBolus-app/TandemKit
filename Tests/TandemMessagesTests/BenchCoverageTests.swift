import Testing
import Foundation
@testable import TandemMessages

// Pure-logic tests for the saline-bench command-coverage harness (deliverable #6). These prove the parts
// the executable coverage runner CANNOT prove under `swift test` (CoreBluetooth aborts there): command
// enumeration, per-model applicability, prerequisite gating, cell classification, and matrix
// accumulation/merge across sessions. Everything here is transport-free and deterministic.

@Suite struct BenchCommandCatalogTests {

    /// Every enumerated request type maps to exactly one descriptor, with no duplicate names.
    @Test func catalogEnumeratesEveryRequestWithoutDuplicates() {
        let names = BenchCommandCatalog.all.map { $0.name }
        #expect(names.count == BenchCommandCatalog.messageTypes.count)
        #expect(
            Set(names).count == names.count,
            "duplicate command names in the catalog: \(names.count) vs \(Set(names).count)")
        // The full request surface under Sources/TandemMessages/Requests is 125 types.
        #expect(names.count == 125, "catalog drifted from the 125-request surface (got \(names.count))")
    }

    /// The delivery-class surface is exactly 14: 3 UNIVERSAL + 11 Mobi-only (prior-research invariant).
    @Test func deliveryCommandsAreThreeUniversalPlusElevenMobiOnly() {
        let delivery = BenchCommandCatalog.deliveryCommands
        #expect(delivery.count == 14, "expected 14 modifiesInsulinDelivery commands, got \(delivery.count)")

        let universal = Set(BenchCommandCatalog.universalDeliveryCommands.map { $0.name })
        #expect(
            universal == ["InitiateBolusRequest", "AdditionalBolusRequest", "EnterChangeCartridgeModeRequest"],
            "universal delivery set drifted: \(universal.sorted())")

        let mobiOnly = Set(BenchCommandCatalog.mobiOnlyDeliveryCommands.map { $0.name })
        // Ground truth from the messages' own props (NOT hand-guessed): the delivery IDP op is
        // RenameIDP (0xA8), and EnterFillTubingMode dispenses to prime tubing — both delivery+Mobi;
        // SetIDPSegment/PrimeTubingSuspend are Mobi-only but NOT delivery-class.
        let expectedMobi: Set<String> = [
            "SetModesRequest", "SetActiveIDPRequest", "FillCannulaRequest", "EnterFillTubingModeRequest",
            "SetTempRateRequest", "StopTempRateRequest", "SuspendPumpingRequest", "ResumePumpingRequest",
            "CreateIDPRequest", "DeleteIDPRequest", "RenameIDPRequest"
        ]
        #expect(mobiOnly == expectedMobi, "Mobi-only delivery set drifted: \(mobiOnly.sorted())")
        #expect(mobiOnly.count == 11)
    }

    /// Applicability is derived from `supportedDevices` (nil = all models).
    @Test func applicablePumpModelsDerivedFromSupportedDevices() {
        let bolus = BenchCommandCatalog.all.first { $0.name == "InitiateBolusRequest" }!
        #expect(Set(bolus.applicablePumpModels) == Set(PumpModel.allCases))
        let temp = BenchCommandCatalog.all.first { $0.name == "SetTempRateRequest" }!
        #expect(temp.applicablePumpModels == [.mobi])
    }

    /// `requiresCGM` is a name-driven, self-maintaining predicate covering the CGM/glucose family.
    @Test func requiresCGMPredicateClassifiesTheCgmFamily() {
        for name in [
            "CurrentEgvGuiDataV2Request", "CGMStatusRequest", "StartDexcomG6SensorSessionRequest",
            "SetG6TransmitterIdRequest", "GetSavedG7PairingCodeRequest", "SetSensorTypeRequest",
            "CgmHighLowAlertRequest"
        ] {
            #expect(BenchCommandCatalog.requiresCGM(name: name), "\(name) should be CGM-dependent")
        }
        for name in [
            "InsulinStatusRequest", "InitiateBolusRequest", "CurrentBatteryV2Request",
            "ApiVersionRequest", "SetMaxBolusLimitRequest", "LastBGRequest"
        ] {
            #expect(!BenchCommandCatalog.requiresCGM(name: name), "\(name) should NOT be CGM-dependent")
        }
    }

    /// Lane classification: reads, signed non-delivery writes, delivery, and pairing.
    @Test func laneClassification() {
        func lane(_ n: String) -> BenchLane { BenchCommandCatalog.all.first { $0.name == n }!.lane }
        #expect(lane("InsulinStatusRequest") == .read)
        #expect(lane("ApiVersionRequest") == .read)
        #expect(lane("InitiateBolusRequest") == .delivery)
        #expect(lane("SetTempRateRequest") == .delivery)
        #expect(lane("SetMaxBolusLimitRequest") == .signedWrite)
        #expect(lane("FactoryResetRequest") == .signedWrite)
        #expect(lane("Jpake1aRequest") == .pairing)
        #expect(lane("CentralChallengeRequest") == .pairing)
    }

    /// Pairing scheme is attributed by message family.
    @Test func pairingSchemeAttribution() {
        let jpake = BenchCommandCatalog.all.first { $0.name == "Jpake2Request" }!
        #expect(jpake.pairingScheme == .jpake)
        let legacy = BenchCommandCatalog.all.first { $0.name == "PumpChallengeRequest" }!
        #expect(legacy.pairingScheme == .legacyV1)
    }

    /// A lane-`read` command can be instantiated for sending; a delivery command cannot (via this path).
    @Test func makeReadInstanceOnlyForReads() {
        #expect(BenchCommandCatalog.makeReadInstance("InsulinStatusRequest") != nil)
        #expect(BenchCommandCatalog.makeReadInstance("InitiateBolusRequest") == nil)
        #expect(BenchCommandCatalog.makeReadInstance("NotARealRequest") == nil)
    }
}

@Suite struct BenchCoveragePlanTests {

    // Representative session configs.
    static let oldTslim = BenchSessionConfig(
        model: .tslim, apiVersion: .v2_5, firmwareLabel: "SW7.6 (API 2.5)", pairingScheme: .legacyV1,
        cartridgePresent: false, cgmPresent: false, salineAttested: false, deliveryEnabled: false)
    static let oldTslimSaline = BenchSessionConfig(
        model: .tslim, apiVersion: .v2_5, firmwareLabel: "SW7.6 (API 2.5)", pairingScheme: .legacyV1,
        cartridgePresent: true, cgmPresent: false, salineAttested: true, deliveryEnabled: true)
    static let newTslim = BenchSessionConfig(
        model: .tslim, apiVersion: .v3_4, firmwareLabel: "SW7.8 (API 3.4)", pairingScheme: .jpake,
        cartridgePresent: false, cgmPresent: false, salineAttested: false, deliveryEnabled: false)
    static let mobiSaline = BenchSessionConfig(
        model: .mobi, apiVersion: .mobi_v3_6, firmwareLabel: "SW7.7 (API 3.6)", pairingScheme: .jpake,
        cartridgePresent: true, cgmPresent: false, salineAttested: true, deliveryEnabled: true)
    static let mobiSalineCgm = BenchSessionConfig(
        model: .mobi, apiVersion: .mobi_v3_6, firmwareLabel: "SW7.7 (API 3.6)", pairingScheme: .jpake,
        cartridgePresent: true, cgmPresent: true, salineAttested: true, deliveryEnabled: true)

    private func cmd(_ n: String) -> BenchCommand { BenchCommandCatalog.all.first { $0.name == n }! }
    private func plan(_ n: String, _ cfg: BenchSessionConfig) -> BenchPlan { BenchCoverage.plan(for: cmd(n), in: cfg) }

    /// A read runs in any connected config.
    @Test func readsExerciseInAnyConfig() {
        #expect(plan("InsulinStatusRequest", Self.oldTslim) == .exercise(.read))
        #expect(plan("InsulinStatusRequest", Self.mobiSaline) == .exercise(.read))
    }

    /// A CGM-dependent read (with a satisfiable API floor) is deferred without a sensor, exercised with one.
    @Test func cgmReadGatedOnCgmPresent() {
        if case .deferred(let r) = plan("CGMStatusRequest", Self.mobiSaline) {
            #expect(r.contains("CGM"))
        } else {
            Issue.record("expected deferred without CGM")
        }
        #expect(plan("CGMStatusRequest", Self.mobiSalineCgm) == .exercise(.read))
    }

    /// A command with an API_FUTURE floor (known to the app, unparseable by any current firmware) defers on
    /// EVERY known config — the honest disposition (no session can cover it until such firmware exists).
    @Test func futureApiFlooredReadDefersOnAllKnownFirmware() {
        let egvV2 = cmd("CurrentEgvGuiDataV2Request")
        #expect(egvV2.minApi == .future)
        if case .deferred = plan("CurrentEgvGuiDataV2Request", Self.mobiSalineCgm) {
        } else {
            Issue.record("an API_FUTURE-floored read must defer even on the fullest config")
        }
    }

    /// A universal delivery command: deferred without a cartridge, deferred without saline attest, then exercised.
    @Test func universalDeliveryGating() {
        let noCart = BenchSessionConfig(
            model: .tslim, apiVersion: .v3_4, firmwareLabel: "SW7.8", pairingScheme: .jpake,
            cartridgePresent: false, cgmPresent: false, salineAttested: false, deliveryEnabled: false)
        if case .deferred(let r) = plan("InitiateBolusRequest", noCart) {
            #expect(r.contains("cartridge"))
        } else {
            Issue.record("expected deferred (no cartridge)")
        }

        let cartNoSaline = BenchSessionConfig(
            model: .tslim, apiVersion: .v3_4, firmwareLabel: "SW7.8", pairingScheme: .jpake,
            cartridgePresent: true, cgmPresent: false, salineAttested: false, deliveryEnabled: false)
        if case .deferred(let r) = plan("InitiateBolusRequest", cartNoSaline) {
            #expect(r.contains("saline"))
        } else {
            Issue.record("expected deferred (no saline attest)")
        }

        #expect(plan("InitiateBolusRequest", Self.oldTslimSaline) == .exercise(.delivery))
    }

    /// A Mobi-only delivery command is N/A on t:slim (any firmware), and exercisable on a saline Mobi.
    @Test func mobiOnlyDeliveryIsNotApplicableOnTslim() {
        if case .notApplicable = plan("SetTempRateRequest", Self.oldTslimSaline) {
        } else {
            Issue.record("expected N/A on t:slim")
        }
        if case .notApplicable = plan("SetTempRateRequest", Self.newTslim) {
        } else {
            Issue.record("expected N/A on new t:slim")
        }
        #expect(plan("SetTempRateRequest", Self.mobiSaline) == .exercise(.delivery))
    }

    /// Signed-write disposition now follows the reversible-affordance catalog: destructive/irreversible →
    /// MANUAL gap; reversible-but-not-yet-wired → pending gap; a wired reversible affordance → exercise.
    @Test func signedWriteDispositionFollowsAffordanceCatalog() {
        // Destructive → MANUAL gap (never auto-fired).
        if case .gap(let r) = plan("FactoryResetRequest", Self.oldTslim) {
            #expect(r.contains("MANUAL"))
        } else {
            Issue.record("expected MANUAL gap for FactoryReset")
        }
        if case .gap(let r) = plan("ActivateShelfModeRequest", Self.oldTslim) {
            #expect(r.contains("MANUAL"))
        } else {
            Issue.record("expected MANUAL gap for ActivateShelfMode")
        }
        // Reversible-but-unwired → pending gap.
        if case .gap(let r) = plan("SetBgReminderRequest", Self.oldTslim) {
            #expect(r.contains("pending"))
        } else {
            Issue.record("expected pending gap for SetBgReminder")
        }
        // Wired reversible affordances → exercise (no PUMPX2_DELIVER_SALINE needed).
        // SetMaxBolusLimit / ChangeTimeDate / PlaySound now carry the conservative minApi floor
        // (.benchConservativeUnverifiedFloor = 3.4, ported from experimental@245b531 — C4-01/CX-T-03),
        // which the classifier checks BEFORE the affordance logic, so the API-2.5 oldTslim session
        // correctly DEFERS them instead of exercising (fail-safe: never send to a firmware that op-77s).
        if case .deferred(let r) = plan("SetMaxBolusLimitRequest", Self.oldTslim) {
            #expect(r.contains("3.4"))
        } else {
            Issue.record("SetMaxBolusLimit should defer on the API-2.5 t:slim (conservative minApi floor)")
        }
        if case .deferred(let r) = plan("ChangeTimeDateRequest", Self.oldTslim) {
            #expect(r.contains("3.4"))
        } else {
            Issue.record("ChangeTimeDate should defer on the API-2.5 t:slim (conservative minApi floor)")
        }
        #expect(plan("BolusPermissionRequest", Self.oldTslim) == .exercise(.signedWrite))  // benignProbe (minApi .v2_5)
        if case .deferred(let r) = plan("PlaySoundRequest", Self.oldTslim) {
            #expect(r.contains("3.4"))
        } else {
            Issue.record("PlaySound should defer on the API-2.5 t:slim (conservative minApi floor)")
        }
        #expect(plan("CancelBolusRequest", Self.oldTslim) == .exercise(.signedWrite))  // benignProbe
        // Restore-half of a delivery pair → GAP (recorded when the primary pair runs behind the saline gate).
        if case .gap(let r) = plan("ExitChangeCartridgeModeRequest", Self.oldTslim) {
            #expect(r.contains("restore-half"))
        } else {
            Issue.record("expected restore-half gap for ExitChangeCartridgeMode")
        }
    }

    /// Pairing coverage is attributed by scheme + API floor.
    @Test func pairingGatedBySchemeAndApi() {
        // JPAKE needs API >= 3.2 → deferred on the old (2.5) t:slim, exercised on a JPAKE session.
        if case .deferred = plan("Jpake1aRequest", Self.oldTslim) {
        } else {
            Issue.record("JPAKE should defer on API 2.5")
        }
        #expect(plan("Jpake1aRequest", Self.newTslim) == .exercise(.pairing))
        // Legacy V1 is exercised on the legacy session, deferred on a JPAKE session.
        #expect(plan("CentralChallengeRequest", Self.oldTslim) == .exercise(.pairing))
        if case .deferred = plan("CentralChallengeRequest", Self.newTslim) {
        } else {
            Issue.record("legacy V1 should defer on a JPAKE session")
        }
    }

    /// planSession classifies EVERY catalog command and never crashes; counts are sane.
    @Test func planSessionCoversEveryCommand() {
        let cells = BenchCoverage.planSession(Self.mobiSalineCgm, timestamp: "T0")
        #expect(cells.count == BenchCommandCatalog.all.count)
        // On a fully-loaded Mobi+CGM session, at least the universal + Mobi delivery commands are exercisable.
        let untested = cells.filter { $0.state == .untested }.map { $0.command }
        #expect(untested.contains("InitiateBolusRequest"))
        #expect(untested.contains("SetTempRateRequest"))
    }
}

@Suite struct BenchCoverageMatrixTests {

    private func cell(
        _ command: String, _ state: BenchCellState, model: String = "mobi",
        firmware: String = "SW7.7", cartridge: Bool = true, cgm: Bool = false,
        ts: String
    ) -> BenchCoverageCell {
        BenchCoverageCell(
            model: model, firmware: firmware, cartridge: cartridge, cgm: cgm,
            command: command, lane: .delivery, state: state, note: "", session: "s", timestamp: ts)
    }

    /// A real result (pass/fail) always beats a "can't-test-here" placeholder, regardless of order.
    @Test func realResultBeatsPlaceholder() {
        var m = BenchCoverageMatrix()
        m.record(cell("InitiateBolusRequest", .pass, ts: "T1"))
        // A later DEFERRED from a wrong-config session must NOT clobber the PASS.
        m.record(cell("InitiateBolusRequest", .deferred, ts: "T2"))
        #expect(m.cells.values.first { $0.command == "InitiateBolusRequest" }!.state == .pass)

        // And a placeholder-first, real-second ordering ends up real too.
        var n = BenchCoverageMatrix()
        n.record(cell("SetTempRateRequest", .deferred, ts: "T1"))
        n.record(cell("SetTempRateRequest", .pass, ts: "T2"))
        #expect(n.cells.values.first { $0.command == "SetTempRateRequest" }!.state == .pass)
    }

    /// Between two real results the latest timestamp wins (a later FAIL surfaces a regression).
    @Test func latestRealResultWins() {
        var m = BenchCoverageMatrix()
        m.record(cell("InitiateBolusRequest", .pass, ts: "2026-01-01"))
        m.record(cell("InitiateBolusRequest", .fail, ts: "2026-02-01"))
        #expect(m.cells.values.first!.state == .fail)
    }

    /// Merging two sessions accumulates coverage (resume-across-sessions).
    @Test func mergingAccumulatesAcrossSessions() {
        // Session A (mobi, cartridge) proves delivery.
        var a = BenchCoverageMatrix()
        a.record(cell("InitiateBolusRequest", .pass, model: "mobi", cartridge: true, ts: "T1"))
        // Session B (t:slim, no cartridge) recorded delivery as deferred and a read as pass.
        var b = BenchCoverageMatrix()
        b.record(cell("InitiateBolusRequest", .deferred, model: "tslim", cartridge: false, ts: "T2"))
        b.record(
            BenchCoverageCell(
                model: "tslim", firmware: "SW7.8", cartridge: false, cgm: false,
                command: "InsulinStatusRequest", lane: .read, state: .pass,
                note: "", session: "s", timestamp: "T2"))
        let merged = a.merging(b)
        // Both sessions' distinct keys survive (different model axis) → 3 cells.
        #expect(merged.cells.count == 3)
    }

    /// rollups(): a command is COVERED for a (model,firmware) if ANY cart/cgm variant passed.
    @Test func rollupCoveredIfAnyVariantPassed() {
        var m = BenchCoverageMatrix()
        // Same command, same model/firmware, two cartridge variants: no-cart deferred + cart pass.
        m.record(cell("InitiateBolusRequest", .deferred, cartridge: false, ts: "T1"))
        m.record(cell("InitiateBolusRequest", .pass, cartridge: true, ts: "T2"))
        let roll = m.rollups().first { $0.command == "InitiateBolusRequest" }!
        #expect(roll.best == .pass)
        #expect(m.remaining().contains { $0.command == "InitiateBolusRequest" } == false)
    }

    /// remaining() lists deferred/untested/fail (with the config note) but not N/A or gap.
    @Test func remainingListsOnlyCoverableGaps() {
        var m = BenchCoverageMatrix()
        m.record(
            BenchCoverageCell(
                model: "tslim", firmware: "SW7.8", cartridge: false, cgm: true,
                command: "CurrentEgvGuiDataV2Request", lane: .read, state: .deferred,
                note: "needs a CGM-present session", session: "s", timestamp: "T1"))
        m.record(
            BenchCoverageCell(
                model: "tslim", firmware: "SW7.8", cartridge: false, cgm: false,
                command: "FactoryResetRequest", lane: .signedWrite, state: .gap,
                note: "destructive", session: "s", timestamp: "T1"))
        let rem = m.remaining()
        #expect(rem.contains { $0.command == "CurrentEgvGuiDataV2Request" })
        #expect(rem.contains { $0.command == "FactoryResetRequest" } == false, "gaps are not 'coverable-but-missing'")
    }

    /// The matrix round-trips through JSON (the persistence format the runner uses between sessions).
    @Test func matrixJsonRoundTrips() throws {
        var m = BenchCoverageMatrix()
        m.record(cell("InitiateBolusRequest", .pass, ts: "T1"))
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(BenchCoverageMatrix.self, from: data)
        #expect(back.cells.count == 1)
        #expect(back.cells.values.first!.state == .pass)
        #expect(back.schemaVersion == BenchCoverageMatrix.currentSchemaVersion)
    }

    /// Markdown rendering produces the expected sections (human-readable artifact).
    @Test func markdownRenderHasSections() {
        let cells = BenchCoverage.planSession(BenchCoveragePlanTests.mobiSaline, timestamp: "T0")
        var m = BenchCoverageMatrix()
        m.record(cells)
        let md = m.renderMarkdown(generatedAt: "2026-08-23")
        #expect(md.contains("# TandemKit bench command-coverage matrix"))
        #expect(md.contains("## Summary"))
        #expect(md.contains("## Coverage by session config"))
        #expect(md.contains("Still uncovered"))
        #expect(md.contains("Not auto-fired"))  // the manual/owner-judgment GAP section
    }
}

// Pure-logic tests for the reversible-affordance layer (scope extension). These prove the affordance
// metadata + reversibility pairing + runner lane planning the coverage runner rests on — all
// transport-free and deterministic (the BLE driving itself can only be validated at the bench).
@Suite struct BenchAffordanceCatalogTests {

    private func aff(_ n: String) -> BenchAffordance { BenchAffordanceCatalog.affordance(for: n)! }
    private func cmd(_ n: String) -> BenchCommand { BenchCommandCatalog.all.first { $0.name == n }! }

    /// Completeness: EVERY state-changing catalog command (delivery + signed-write lane) has an affordance,
    /// so nothing falls through to an "unclassified" gap. Guards against drift as messages are added.
    @Test func everyStateChangingCommandHasAnAffordance() {
        for c in BenchCommandCatalog.all where c.lane == .delivery || c.lane == .signedWrite {
            #expect(
                BenchAffordanceCatalog.affordance(for: c.name) != nil,
                "\(c.name) (lane \(c.lane.rawValue)) has no reversible-affordance entry")
        }
        // Reads and pairing are NOT expected to have write affordances.
        #expect(BenchAffordanceCatalog.affordance(for: "InsulinStatusRequest") == nil)
    }

    /// The 14 delivery-class commands each have a saline-gated affordance; the 2 bolus ones are deliver-oracles.
    @Test func deliveryAffordancesAreFourteenAndGated() {
        let delivery = BenchAffordanceCatalog.deliveryAffordances
        #expect(delivery.count == 14, "expected 14 delivery affordances, got \(delivery.count)")
        #expect(
            delivery.allSatisfy { $0.gatedOnSalineDelivery }, "every delivery affordance must require the saline gate")
        #expect(aff("InitiateBolusRequest").kind == .deliverOracle)
        #expect(aff("AdditionalBolusRequest").kind == .deliverOracle)
        #expect(aff("FillCannulaRequest").oracleRead == "LoadStatusRequest")
    }

    /// The capture→set→restore delivery ones capture prior state via a specific oracle read.
    @Test func captureSetRestoreDeliveryOnes() {
        #expect(aff("SetModesRequest").kind == .captureSetRestore)
        #expect(aff("SetActiveIDPRequest").kind == .captureSetRestore)
        #expect(aff("RenameIDPRequest").kind == .captureSetRestore)
        #expect(aff("SetActiveIDPRequest").oracleRead == "ProfileStatusRequest")
        #expect(aff("RenameIDPRequest").oracleRead == "IDPSettingsRequest")
    }

    /// Reversible pairs are SYMMETRIC: each primary names its restore partner, and the partner points back
    /// with role `.restorePartner`. Covers the four delivery pairs + the throwaway create/delete + the two
    /// signed-write exit partners + the permission pair.
    @Test func reversiblePairsAreSymmetric() {
        let pairs = [
            ("SuspendPumpingRequest", "ResumePumpingRequest"),
            ("SetTempRateRequest", "StopTempRateRequest"),
            ("EnterChangeCartridgeModeRequest", "ExitChangeCartridgeModeRequest"),
            ("EnterFillTubingModeRequest", "ExitFillTubingModeRequest"),
            ("CreateIDPRequest", "DeleteIDPRequest"),
            ("BolusPermissionRequest", "BolusPermissionReleaseRequest")
        ]
        for (primary, partner) in pairs {
            #expect(aff(primary).role == .primary, "\(primary) should be the primary")
            #expect(aff(primary).partner == partner, "\(primary) should pair with \(partner)")
            #expect(aff(partner).role == .restorePartner, "\(partner) should be the restore partner")
            #expect(aff(partner).partner == primary, "\(partner) should point back to \(primary)")
        }
    }

    /// Every partner + oracleRead name references a REAL catalog command (no typos, no drift).
    @Test func affordanceCrossRefsAreRealCommands() {
        let names = Set(BenchCommandCatalog.all.map { $0.name })
        for a in BenchAffordanceCatalog.all {
            if let p = a.partner { #expect(names.contains(p), "\(a.command) partner \(p) is not a catalog command") }
            if let o = a.oracleRead {
                #expect(names.contains(o), "\(a.command) oracleRead \(o) is not a catalog command")
            }
        }
    }

    /// Destructive / irreversible commands are `.manualOnly` and are NEVER in the drivable allowlist.
    @Test func destructiveCommandsAreManualOnly() {
        let manual = Set(BenchAffordanceCatalog.manualOnly.map { $0.command })
        for n in [
            "ActivateShelfModeRequest", "DisconnectPumpRequest", "FactoryResetRequest",
            "FactoryResetBRequest", "StopDexcomCGMSensorSessionRequest", "SetDexcomG7PairingCodeRequest"
        ] {
            #expect(manual.contains(n), "\(n) must be manual-only")
            #expect(!BenchAffordanceCatalog.isRunnerDrivable(n), "\(n) must never be runner-drivable")
        }
    }

    /// The derived `benchExercisableSignedWrites` allowlist GREW beyond the old 3 and contains only
    /// non-delivery, runner-drivable writes (captureReapply + benignProbe). It replaces the hand-list.
    @Test func exercisableSignedWritesAreDerivedAndGrown() {
        let allow = BenchCommandCatalog.benchExercisableSignedWrites
        #expect(allow == Set(BenchAffordanceCatalog.drivableSignedWrites.map { $0.command }))
        #expect(allow.count > 3, "the allowlist should have grown past the original 3 (got \(allow.count))")
        // Sample of the newly-covered writes.
        for n in [
            "ChangeTimeDateRequest", "SetMaxBolusLimitRequest", "SetMaxBasalLimitRequest",
            "ChangeControlIQSettingsRequest", "SetLowInsulinAlertRequest", "PlaySoundRequest",
            "UserInteractionRequest", "RemoteCarbEntryRequest", "CancelBolusRequest"
        ] {
            #expect(allow.contains(n), "\(n) should now be runner-drivable")
        }
        // Delivery writes and destructive writes are NOT in the non-delivery allowlist.
        #expect(!allow.contains("InitiateBolusRequest"))
        #expect(!allow.contains("FactoryResetRequest"))
    }

    /// Runner lane planning: on a saline Mobi (+CGM) every one of the 14 delivery commands is exercisable;
    /// on a no-cartridge t:slim the universal ones defer (no cartridge) and the Mobi-only ones are N/A.
    @Test func l0BdeliveryPlanningAcrossConfigs() {
        let mobiFull = BenchCoveragePlanTests.mobiSalineCgm
        for a in BenchAffordanceCatalog.deliveryAffordances {
            let c = cmd(a.command)
            // Mobi + CGM + saline: exercisable regardless of model (all 14 are Mobi-legal or universal).
            #expect(
                BenchCoverage.plan(for: c, in: mobiFull) == .exercise(.delivery),
                "\(a.command) should be exercisable on a saline Mobi+CGM session")
        }
        // No-cartridge t:slim: universal delivery defers on cartridge; Mobi-only delivery is N/A.
        if case .deferred = BenchCoverage.plan(
            for: cmd("EnterChangeCartridgeModeRequest"), in: BenchCoveragePlanTests.oldTslim)
        {
        } else {
            Issue.record("universal delivery should defer (no cartridge) on the old t:slim")
        }
        if case .notApplicable = BenchCoverage.plan(
            for: cmd("SuspendPumpingRequest"), in: BenchCoveragePlanTests.oldTslim)
        {
        } else {
            Issue.record("Mobi-only delivery should be N/A on a t:slim")
        }
        // Drivable signed writes need no saline gate, but SetMaxBolusLimitRequest now carries the
        // conservative minApi floor (3.4, ported C4-01/CX-T-03) which gates it ahead of the affordance
        // check — it correctly DEFERS on the API-2.5 old t:slim rather than exercising.
        if case .deferred(let r) = BenchCoverage.plan(
            for: cmd("SetMaxBolusLimitRequest"), in: BenchCoveragePlanTests.oldTslim)
        {
            #expect(r.contains("3.4"))
        } else {
            Issue.record("SetMaxBolusLimit should defer on the API-2.5 t:slim (conservative minApi floor)")
        }
    }
}
