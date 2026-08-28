// BenchCases.swift — the Tier-1 hardware cases expressed declaratively.
// SALINE OR EMPTY ONLY. NEVER real insulin. NEVER on a body. Delivered amount is proved from the pump's
// own history log (C4), never fabricated.

import Foundation
import Testing
import TandemMessages
import TandemBLE

enum BenchCases {
    /// The three representative Tier-1 cases named in the design doc (§4.2).
    static var all: [HardwareCase] { [salineBolusHistoryVerify, tempBasalSetAndRead, pairingReconnectCycle] }

    /// Runs in EVERY config (whole-suite `connected` gate only): the "RUNNABLE NOW" subset.
    static var readOnlyCases: [HardwareCase] { [pairingReconnectCycle, stateAndCapabilityReads, txIdMatchProbe] }

    /// Delivery (saline) cases — gated on `HardwareGate.delivery` (cartridge + saline + deliver flag).
    static var deliveryCases: [HardwareCase] { [salineBolusHistoryVerify, tempBasalSetAndRead] }

    /// The pump's OWN CGM read path — gated on `HardwareGate.cgmPresent`.
    static var cgmReadCases: [HardwareCase] { [cgmLiveEgvRead, cgmHistoryReadings] }

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // CASE 1 — Saline bolus, verified by history-log read-back (closes BENCH-SESSION-PLAN Obj 1 & 3).
    //   BolusPermission -> InitiateBolus (FOOD2, units-only) -> authoritative completion read-back.
    //   Self-verifies: BolusCompletedHistoryLog.insulinDelivered ≈ requested (within the pump's 0.05 U
    //   increment) AND LastBolusStatusV2.deliveredUnits agrees.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let salineBolusHistoryVerify = HardwareCase(
        name: "saline-bolus-1.0u-history-verify",
        requiresDelivery: true,
        requiresCGM: false,
        preconditions: [.salineCartridge, .idle, .minRemaining(units: 2.0)],
        command: { s in
            let requestedMilliunits: UInt32 = 1000            // 1.00 U saline
            try await s.refreshSigningTime()
            // Signed permission (pump mints a bolusId). Elevates to `.allowNonDelivery`, then restores.
            let permission = try await s.request(BolusPermissionRequest(), expect: BolusPermissionResponse.self)
            try #require(permission.granted, "pump did not grant bolus permission (nack \(permission.nackReasonId))")

            // Units-only manual bolus → no carbs → FOOD2 (shared helper is the single source of truth).
            let mask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)
            let req = try InitiateBolusRequest(validating: requestedMilliunits,
                                               bolusID: permission.bolusId, bolusTypeBitmask: mask)
            // Initiate (signed, delivery). Both walls: `.allowDelivery` (scoped) + `allowInsulinDelivery`.
            let initiate = try await s.request(req, expect: InitiateBolusResponse.self, deliver: true)
            try #require(initiate.accepted && initiate.bolusId == permission.bolusId,
                         "initiate not accepted / id mismatch (status \(initiate.status))")
            return permission.bolusId
        },
        verify: { s, bolusId, baseline in
            let requestedUnits = 1.0
            // AUTHORITATIVE: the pump's own completed-bolus history record (C4).
            let completed = try #require(await s.bolusCompleted(bolusId: bolusId, since: baseline),
                                         "no BolusCompletedHistoryLog for id \(bolusId)")
            // No named completion enum in Swift — compare the raw int (3 == normal completion in the
            // upstream wire vector) and compare delivered vs requested ourselves.
            #expect(completed.completionStatusId == 3, "unexpected completion status \(completed.completionStatusId)")
            #expect(abs(Double(completed.insulinDelivered) - requestedUnits) <= 0.05,
                    "delivered \(completed.insulinDelivered) != requested \(requestedUnits)")
            // Cross-check the live last-bolus mirror agrees with history.
            let last = try await s.request(LastBolusStatusV2Request(), expect: LastBolusStatusV2Response.self)
            #expect(last.bolusId == bolusId)
            #expect(abs(last.deliveredUnits - Double(completed.insulinDelivered)) <= 0.001,
                    "LastBolusStatusV2 and history disagree on delivered units")
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // CASE 2 — Temp basal set + read-back (Mobi-only; SKIPS with a clear reason on t:slim X2).
    //   Skips (green, recorded) via `mobiSkipSentinel` when the pump is not Mobi. On a Mobi pump:
    //   precondition CIQ OFF, in-harness bounds range-check, set → assert current-basal + the
    //   TempRateActivatedHistoryLog (typeId 2), then cleanup with StopTempRate.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let tempBasalSetAndRead = HardwareCase(
        name: "temp-basal-80pct-30min-set-read (Mobi-only)",
        requiresDelivery: true,
        requiresCGM: false,
        preconditions: [.salineCartridge, .idle],
        command: { s in
            // t:slim X2 gate: SetTempRate is Mobi-only. SKIP (not fail) on a non-Mobi pump.
            let api = try await s.request(ApiVersionRequest(), expect: ApiVersionResponse.self)
            guard api.isMobi else { return HardwareCase.mobiSkipSentinel }

            // CIQ must be OFF before a temp rate (checked AFTER the Mobi guard so t:slim doesn't red here).
            let ciq = try await s.request(ControlIQInfoV2Request(), expect: ControlIQInfoV2Response.self)
            try #require(!ciq.closedLoopEnabled, "Control-IQ must be OFF before a temp rate")

            let minutes = 30, percent = 80
            // Range-check in-harness (init does NOT — TempRateRequests.swift:14-18).
            try #require((SetTempRateRequest.minMinutes...SetTempRateRequest.maxMinutes).contains(minutes),
                         "temp-rate minutes out of range")
            try #require((SetTempRateRequest.minPercent...SetTempRateRequest.maxPercent).contains(percent),
                         "temp-rate percent out of range")
            try await s.refreshSigningTime()
            let resp = try await s.request(try SetTempRateRequest(minutes: minutes, percent: percent),
                                           expect: SetTempRateResponse.self, deliver: true)
            try #require(resp.accepted, "temp rate not accepted (status \(resp.status))")
            return resp.tempRateId
        },
        verify: { s, tempRateId, baseline in
            if tempRateId == HardwareCase.mobiSkipSentinel { return }   // correct Mobi-only SKIP — nothing to verify
            let basal = try await s.request(CurrentBasalStatusRequest(), expect: CurrentBasalStatusResponse.self)
            #expect(basal.basalModifiedBitmask != 0, "current basal not marked modified after temp rate")
            let activated = try #require(
                await s.streamHistory(from: baseline, count: 255)
                    .compactMap { $0 as? TempRateActivatedHistoryLog }
                    .first { $0.tempRateId == tempRateId },
                "no TempRateActivatedHistoryLog for id \(tempRateId)")
            #expect(activated.percent == 80.0)
            // Cleanup so the next case starts clean (state reset, doc §4.3).
            try await s.refreshSigningTime()
            _ = try? await s.request(StopTempRateRequest(), expect: StopTempRateResponse.self, deliver: true)
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // CASE 3 — Pairing + reconnect / state-restoration cycle (§5.2). NO delivery. RUNNABLE NOW.
    //   Pair (once, by the shared session — JPAKE 6-digit OR legacy V1 16-char, per the operator's
    //   code) -> read + record the firmware/version PROFILE (tags every result by pump version + auth
    //   scheme; a behavior on one firmware may not hold on another) -> a status read -> forced link
    //   drop -> reconnect -> RE-AUTH:
    //       • JPAKE (v7.7+): quick-pair RESUME (no new 6-digit code).
    //       • legacy V1 (pre-v7.7): a SILENT full CentralChallenge→PumpChallenge re-challenge (the app
    //         already holds the code — no on-screen confirm on reconnect).
    //   -> a status read still parses.
    //   Self-verifies: signing key still derived, reconnect completes in budget, reads parse before/after,
    //   and the write policy stayed `.readOnly` (fail-closed held). Scheme-agnostic assertions — both
    //   re-auth paths must leave a usable signing key with the policy still read-only.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let pairingReconnectCycle = HardwareCase(
        name: "pairing-reconnect-state-restoration",
        requiresDelivery: false,
        requiresCGM: false,
        preconditions: [],
        command: { s in
            let profile = try await s.readFirmwareProfile()   // tags results by pump version + auth scheme
            print("ℹ️ [hardware] pump firmware profile — \(profile)")
            _ = try await s.request(InsulinStatusRequest(), expect: InsulinStatusResponse.self)   // baseline read parses
            let t0 = Date()
            s.simulateLinkDrop()
            try await s.waitUntilReady(timeout: 45)   // rediscover → reconnect → JPAKE resume / V1 re-challenge
            let elapsed = Date().timeIntervalSince(t0)
            #expect(elapsed <= 45, "reconnect + re-auth exceeded the budget (\(elapsed)s)")
            return Int(elapsed)
        },
        verify: { s, _, _ in
            #expect(!s.authKey.isEmpty, "signing key not derived after re-auth (scheme=\(s.pairingScheme.rawValue))")
            #expect(s.client.writePolicy == .readOnly, "policy must stay read-only for a monitor cycle")
            _ = try await s.request(InsulinStatusRequest(), expect: InsulinStatusResponse.self)   // parses post-reconnect
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // READ-ONLY — state + capability discovery. RUNNABLE NOW (no cartridge, no CGM). All reads parse;
    //   a couple of invariants are asserted (signing timestamp == currentTime; derived cap == bitmask bit).
    //   The EGV read here is parse-only (tolerant of the no-CGM config — a live-reading assertion is the
    //   CGM-present case below).
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let stateAndCapabilityReads = HardwareCase(
        name: "read-only-state-and-capability-discovery",
        requiresDelivery: false,
        requiresCGM: false,
        preconditions: [],
        command: { _ in 0 },
        verify: { s, _, _ in
            let api = try await s.request(ApiVersionRequest(), expect: ApiVersionResponse.self)
            let time = try await s.request(TimeSinceResetRequest(), expect: TimeSinceResetResponse.self)
            #expect(time.signingTimestamp == time.currentTime, "signingTimestamp must equal currentTime (offset 0)")
            // Capability-bitmask dump — tolerant of an OLDER pump. PumpFeaturesV1 (op 78/79) may be
            // unsupported on a legacy (V1-paired, pre-v7.7) pump, which defaults to API_V2_1. Assert the
            // derived-bit invariant when the pump answers; a nil answer is acceptable ONLY on a legacy
            // (V1) pump — a missing bitmask on a modern pump is itself a finding, not a pass.
            if let features = try? await s.request(PumpFeaturesV1Request(), expect: PumpFeaturesV1Response.self) {
                #expect(features.controlIQSupported == ((features.featureBitmask & 1024) != 0),
                        "derived controlIQSupported must match the feature bitmask bit")
            } else {
                #expect(s.pairingScheme == .long16Char,
                        "PumpFeaturesV1 unsupported on a non-legacy pump (API \(api.majorVersion).\(api.minorVersion)) — investigate")
            }
            _ = try await s.request(GlobalMaxBolusSettingsRequest(), expect: GlobalMaxBolusSettingsResponse.self)
            _ = try await s.request(BasalLimitSettingsRequest(), expect: BasalLimitSettingsResponse.self)
            _ = try await s.request(ProfileStatusRequest(), expect: ProfileStatusResponse.self)
            _ = try await s.request(CurrentActiveIdpValuesRequest(), expect: CurrentActiveIdpValuesResponse.self)
            _ = try await s.request(InsulinStatusRequest(), expect: InsulinStatusResponse.self)
            _ = try await s.request(CurrentBatteryV2Request(), expect: CurrentBatteryV2Response.self)
            _ = try await s.request(CurrentBasalStatusRequest(), expect: CurrentBasalStatusResponse.self)
            _ = try await s.request(ControlIQIOBRequest(), expect: ControlIQIOBResponse.self)
            _ = try await s.request(ControlIQInfoV2Request(), expect: ControlIQInfoV2Response.self)
            _ = try await s.request(CurrentEgvGuiDataV2Request(), expect: CurrentEgvGuiDataV2Response.self) // parse only
            _ = try await s.request(HomeScreenMirrorRequest(), expect: HomeScreenMirrorResponse.self)
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // txId-match probe — read-only, no cartridge, no CGM.
    //   Measures whether the pump echoes request txIds in responses. A positive result could justify
    //   txId-match correlation and dropping delivery-class transport serialization later; this case only
    //   MEASURES — it does not change `PumpTransactionCoordinator` or remove serialization.
    //
    //   Three findings, recorded to `s.trace`: (a) echo on a single read; (b) distinct txIds preserved
    //   across successive commands; (c) pipelined same-opcode reads resolve by txId, not opcode-FIFO.
    //
    //   HARD SAFETY: pipelined probe uses read-only status requests only — never pipeline delivery commands.
    //   `exchangeCapturingTxId` throws on non-read messages. If all three pass, transport serialization
    //   may be revisited; if any fails, serialization stays.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let txIdMatchProbe = HardwareCase(
        name: "txid-match-probe (read-only)",
        requiresDelivery: false,
        requiresCGM: false,
        preconditions: [],
        command: { _ in 0 },
        verify: { s, _, _ in
            // (a) ECHO — necessary but not sufficient.
            let echo = try await s.exchangeCapturingTxId(InsulinStatusRequest())
            #expect(echo.echoed,
                    "txId ECHO: response frame[1]=\(echo.responseTxId) != request frame[1]=\(echo.requestTxId)")

            // (b) DISTINCT-ID PRESERVATION — successive commands get distinct txIds, each echoed.
            let b1 = try await s.exchangeCapturingTxId(InsulinStatusRequest())
            let b2 = try await s.exchangeCapturingTxId(InsulinStatusRequest())
            #expect(b1.requestTxId != b2.requestTxId, "successive requests must be assigned DISTINCT txIds")
            #expect(b1.echoed && b2.echoed, "each response must echo its own request txId (distinct-id preservation)")

            // (c) DECISIVE — two SAME-opcode reads pipelined (both issued before the first reply). Assert
            //     the two responses carry the two distinct request txIds (bijection) — attributable by txId
            //     even where opcode-FIFO cannot disambiguate. READ-ONLY commands only.
            async let firstExchange = s.exchangeCapturingTxId(InsulinStatusRequest())
            async let secondExchange = s.exchangeCapturingTxId(InsulinStatusRequest())
            let (first, second) = try await (firstExchange, secondExchange)
            let requestTxIds: Set<UInt8> = [first.requestTxId, second.requestTxId]
            let responseTxIds: Set<UInt8> = [first.responseTxId, second.responseTxId]
            #expect(requestTxIds.count == 2, "the two pipelined requests must have distinct txIds")
            #expect(responseTxIds == requestTxIds,
                    "concurrent same-opcode disambiguation: the two responses must carry the two distinct request txIds by echo — responses \(responseTxIds) vs requests \(requestTxIds)")
            // Informational (NOT an assertion): whether opcode-FIFO happened to attribute in issue order this
            // run. Both echoing in order ⇒ FIFO is currently safe; a swap ⇒ the reorder hazard txId-match fixes.
            let fifoMatchedIssueOrder = first.echoed && second.echoed
            _ = fifoMatchedIssueOrder
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // CGM-PRESENT — live EGV read from the pump's OWN CGM path (PUMP_CGM_PRESENT=1).
    //   Reads CurrentEgvGuiDataV2Response + HomeScreenMirrorResponse and asserts they reflect a live
    //   reading. Safety invariant unchanged: the pump is never on a body.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let cgmLiveEgvRead = HardwareCase(
        name: "cgm-live-egv-read (CGM-present)",
        requiresDelivery: false,
        requiresCGM: true,
        preconditions: [],
        command: { _ in 0 },
        verify: { s, _, _ in
            let egv = try await s.request(CurrentEgvGuiDataV2Request(), expect: CurrentEgvGuiDataV2Response.self)
            #expect(egv.hasValidReading, "PUMP_CGM_PRESENT set but the pump reports no valid EGV")
            #expect((20...600).contains(egv.cgmReading), "implausible EGV \(egv.cgmReading) mg/dL")
            #expect(egv.bgReadingTimestampSeconds != 0, "EGV has no reading timestamp")
            let home = try await s.request(HomeScreenMirrorRequest(), expect: HomeScreenMirrorResponse.self)
            #expect(home.cgmDisplayData, "home-screen mirror shows no CGM display data")
        })

    // ─────────────────────────────────────────────────────────────────────────────────────────
    // CGM-PRESENT — CGM records in the pump's history log (PUMP_CGM_PRESENT=1).
    //   Streams recent history and asserts at least one CGM record parses to a plausible glucose value.
    // ─────────────────────────────────────────────────────────────────────────────────────────
    static let cgmHistoryReadings = HardwareCase(
        name: "cgm-history-records (CGM-present)",
        requiresDelivery: false,
        requiresCGM: true,
        preconditions: [],
        command: { _ in 0 },
        verify: { s, _, _ in
            let events = try await s.recentHistory(count: 255)
            let cgmEvents = events.filter {
                $0 is DexcomG6CGMHistoryLog || $0 is DexcomG7CGMHistoryLog || $0 is CgmDataGxHistoryLog
            }
            #expect(!s.historyCgmReadings.isEmpty || !cgmEvents.isEmpty,
                    "no CGM records in recent history despite PUMP_CGM_PRESENT")
            for reading in s.historyCgmReadings {
                #expect((20...600).contains(reading.glucoseMgdl), "implausible CGM history value \(reading.glucoseMgdl) mg/dL")
            }
        })
}
