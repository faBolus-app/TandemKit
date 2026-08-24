import Foundation
import CoreBluetooth
import TandemMessages
import TandemAuth
import TandemBLE

// TandemBenchHarness — the oracle/test CLI (Milestone 1e).
//
// SAFETY: experimental software in development; not FDA-cleared. Use at your own
// responsibility.
//
// Modes:
//   (no args)   serialization self-check (no BLE) — always works
//   scan        scan for pumps and print discoveries
//   monitor     READ-ONLY: connect → JPAKE pair (6-digit) → poll status reads. Writes that
//               could change pump state are hard-blocked (client.readOnly). This is the safe
//               first hardware test. Set PUMP_PAIRING_CODE=<6 digits>.
//
// A bolus/delivery mode is intentionally NOT provided here yet — deliver via the app once the
// read-only monitor is validated on hardware.

// Unbuffered stdout so progress prints appear LIVE even when piped (e.g. `… | tee run.log`).
// Swift block-buffers stdout to a pipe, which makes a stable (low-output) run look "stuck".
setbuf(stdout, nil)

let args = Array(CommandLine.arguments.dropFirst())

func serializationSelfCheck() {
    print("TandemBenchHarness — serialization self-check (no BLE)")
    if let packets = try? Packetize.packetize(ApiVersionRequest(), txId: 0) {
        print("  ApiVersionRequest(txId=0): \(packets.map { Hex.encode($0.build()) })")
    }
    print("  Bolus opcodes: permission=0x\(String(BolusPermissionRequest.props.opCode, radix: 16)) "
        + "initiate=0x\(String(InitiateBolusRequest.props.opCode, radix: 16)) "
        + "cancel=0x\(String(CancelBolusRequest.props.opCode, radix: 16))")
}

/// Read-only pump monitor: connect, pair over JPAKE, and poll status. Never writes a control
/// or insulin-affecting message (enforced by `client.readOnly`).
@MainActor
final class Monitor: NSObject, PumpBLEClientDelegate {
    let client = PumpBLEClient()
    let pairingCode = ProcessInfo.processInfo.environment["PUMP_PAIRING_CODE"] ?? ""
    var coordinator: (any PairingCoordinating)?
    /// The pairing scheme chosen from the operator's code: JPAKE (6-digit, v7.7+) vs legacy V1
    /// (16-char, pre-v7.7). Used to tag results by auth scheme.
    var pairingScheme: PairingCodeType = .short6Char
    enum Mode: Equatable {
        case scan, monitor, permissionTest, probe, coverage
        case deliverBolus(milliunits: UInt32)
        case carbBolus(carbs: Double, bg: Int?)
    }
    let mode: Mode
    var pollTimer: Timer?
    /// Maps each poll read's txId → its name for the current cycle, so an op-77 ErrorResponse (which
    /// this legacy pump returns with a ZEROED requestCodeId) can be attributed to the exact read that
    /// triggered it via the echoed txId. Cleared at the start of each `poll()`.
    var pollTxMap: [UInt8: String] = [:]
    var authKey: [UInt8] = []
    var signingTimestamp: UInt32 = 0
    /// True while connected AND paired (reset on any non-`.ready` state). The probe sequence waits on
    /// this so each step runs only against a live, re-paired link.
    var isPaired = false
    /// The comprehensive `probe` sequence is launched once (on first pair) and survives reconnects.
    var probeStarted = false
    /// The `coverage` sequence is launched once (on first pair) and survives reconnects.
    var coverageStarted = false
    /// Set true once the BolusPermission→Release accept/NACK probe proved the release half in `coverage`.
    var coveragePermissionReleasePassed = false
    /// Results for RESTORE-PARTNER commands (StopTempRate / ResumePumping / DeleteIDP / the signed-write
    /// Exit* partners / BolusPermissionRelease), filled as a side effect when their PRIMARY affordance runs.
    /// The coverage loop reads a partner's cell state from here instead of driving it standalone (a restore
    /// command only makes sense in its primary's context — e.g. StopTempRate needs an active temp rate).
    var deliveryPairResults: [String: (state: BenchCellState, note: String)] = [:]
    /// op-77 NACK txId-echo sub-probe state (Addendum G / P1a). While `nackProbeActive`, the ErrorResponse
    /// delegate case records the pump's ECHOED txId (frame[1], surfaced as `parsed.txId`) so the sub-probe
    /// can assert it equals the failing request's SENT txId. UNVALIDATED until bench hardware (see the probe
    /// header block above `probeTxIdMatch`).
    var nackProbeActive = false
    var nackProbeEchoedTxId: UInt8?
    /// Set once the shared reconnect ladder exhausts AND our bench-layer recovery budget is spent — the
    /// remaining coverage reads then defer IMMEDIATELY instead of each burning a 45 s `awaitPaired` timeout
    /// against a dead link. Revived by any fresh `.ready`.
    var linkGaveUp = false
    /// How many times this session we've re-kicked a scan to recover an exhausted reconnect ladder.
    var exhaustionRecoveries = 0
    static let maxExhaustionRecoveries = 3
    /// Control-IQ closed-loop state (from ControlIQInfoV1) — decides the temp-basal (needs OFF) vs
    /// SetModes (needs ON) preconditions when interpreting the Mobi-only write probes.
    var ciqClosedLoopEnabled: Bool?
    var permissionSent = false
    var currentBolusId: Int = 0
    // Bolus type bits are derived by the shared library helper `InitiateBolusRequest.typeBitmask`
    // (PX-06): FOOD1 when carbs present, else FOOD2 — never both. (The harness previously OR-ed FOOD2
    // into carb boluses, contradicting the oracle FOOD1 byte-lock.)

    // Carb-bolus computed plan (milliunits) + inputs collected from the pump.
    var carbGrams: Double = 0
    var carbBg: Int?
    var calc: BolusCalcDataSnapshotResponse?
    var iobMilliunits: UInt32?
    var haveTime = false
    var planTotalMU: UInt32 = 0, planFoodMU: UInt32 = 0, planCorrectionMU: UInt32 = 0, planBits = 0
    var carbPlan: BenchBolusPlanner.Plan?

    init(mode: Mode) {
        self.mode = mode
        super.init()
        switch mode {
        case .permissionTest: client.writePolicy = .allowNonDelivery
        case .deliverBolus, .carbBolus: client.writePolicy = .allowDelivery   // experimental delivery
        default: client.writePolicy = .readOnly
        }
        client.delegate = self
    }

    var isBolusMode: Bool {
        switch mode { case .deliverBolus, .carbBolus: return true; default: return false }
    }
    var isCarbMode: Bool { if case .carbBolus = mode { return true } else { return false } }

    func pumpClient(_ c: PumpBLEClient, didChange state: PumpBLEClient.State) {
        print("[state] \(state)")
        if state != .ready { isPaired = false }   // a drop clears paired; the probe waits for re-pair
        if state == .ready { linkGaveUp = false }  // a fresh, healthy link revives the sweep
        if state == .idle { c.startScan() }
        // Bench-layer recovery: the SHARED reconnect ladder gave up (`maxReconnectAttempts`). A legacy pump
        // that tore the link down on an op-77 must not strand the rest of the sweep. Re-kick a fresh scan →
        // `connect` (which clears `reconnectExhausted`), capped so a truly-gone pump can't spin forever. This
        // only reacts to the shared client's state — it does NOT change the shared ladder's semantics.
        if state == .reconnectExhausted {
            if exhaustionRecoveries < Self.maxExhaustionRecoveries {
                exhaustionRecoveries += 1
                print("  ↻ [recovery] reconnect ladder exhausted — re-scanning to recover "
                    + "(attempt \(exhaustionRecoveries)/\(Self.maxExhaustionRecoveries))")
                c.startScan()
            } else {
                linkGaveUp = true
                print("  ⛔️ [recovery] reconnect ladder exhausted \(Self.maxExhaustionRecoveries)× — giving up "
                    + "the link; remaining cells recorded `deferred` (retry a fresh session)")
            }
        }
    }

    func pumpClient(_ c: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {
        print("[discover] \(peripheral.name ?? "unknown") rssi=\(rssi)")
        if mode != .scan { c.connect(peripheral) }
    }

    func pumpClientDidBecomeReady(_ c: PumpBLEClient) {
        print("[ready] connected + characteristics discovered")
        guard !pairingCode.isEmpty else {
            print("[warn] PUMP_PAIRING_CODE not set — cannot pair; reads will be rejected by the pump")
            return
        }
        do {
            // Route by the operator's code (single decision point). A 16-char code selects the legacy
            // V1 CentralChallenge→PumpChallenge handshake; a 6-digit code selects JPAKE. Both drive
            // through the shared `PairingCoordinating` surface; AUTHORIZATION msgs are risk `.read`.
            let scheme = PairingAuth.detectType(pairingCode)
            pairingScheme = scheme
            let coord: any PairingCoordinating
            switch scheme {
            case .short6Char: coord = try PairingCoordinator(pairingCode: pairingCode)       // JPAKE 6-digit
            case .long16Char: coord = try LegacyPairingCoordinator(pairingCode: pairingCode) // legacy V1 16-char
            }
            coord.onSendRequest = { msg in try? c.send(msg) }   // AUTHORIZATION msgs pass the interlock
            coord.onError = { print("[pairing] error: \($0)") }
            coord.onPaired = { [weak self] authKey, _ in
                guard let self else { return }
                self.authKey = authKey
                self.isPaired = true
                print("[paired] \(scheme == .long16Char ? "legacy V1 (16-char)" : "JPAKE (6-digit)") complete; signing key derived (\(authKey.count) bytes).")
                switch self.mode {
                case .monitor:
                    self.readFirmwareProfile()   // print API/version/capability profile, then poll status
                    self.startPolling()
                case .probe:
                    self.readFirmwareProfile()
                    // Launch the sequence once; it internally awaits re-pairs across the pump's drops.
                    if !self.probeStarted { self.probeStarted = true; Task { await self.runProbeSequence() } }
                case .coverage:
                    self.readFirmwareProfile()
                    // Launch the resumable coverage sweep once; it survives the pump's reconnect cycles.
                    if !self.coverageStarted { self.coverageStarted = true; Task { await self.runCoverageSequence() } }
                case .permissionTest, .deliverBolus:
                    print("[write] reading pump time for signing…")
                    try? c.send(TimeSinceResetRequest())   // read (allowed); triggers the signed flow
                case .carbBolus:
                    print("[carb-bolus] reading pump time + calculator settings (carb ratio/ISF/target) + IOB…")
                    try? c.send(TimeSinceResetRequest())
                    try? c.send(BolusCalcDataSnapshotRequest())
                    try? c.send(ControlIQIOBRequest())
                case .scan: break
                }
            }
            coordinator = coord
            print("[pairing] starting \(scheme == .long16Char ? "legacy V1 (16-char) CentralChallenge→PumpChallenge" : "JPAKE (6-digit)")…")
            coord.start()
        } catch {
            print("[pairing] failed to start: \(error)")
        }
    }

    /// Signature test: send a SIGNED BolusPermissionRequest (does NOT dispense) to prove the
    /// pump accepts our HMAC, then release. Delivery is still hard-blocked by writePolicy.
    func sendSignedPermission() {
        permissionSent = true
        print(isBolusMode
            ? "[bolus] requesting SIGNED bolus permission…"
            : "[permission-test] sending SIGNED BolusPermissionRequest (no insulin delivered)…")
        do {
            try client.send(BolusPermissionRequest(), authenticationKey: authKey,
                            pumpTimeSinceReset: signingTimestamp)
        } catch { print("[permission-test] send failed: \(error)") }
    }

    func releasePermission(bolusId: Int) {
        print("[permission-test] releasing bolus permission id \(bolusId)…")
        try? client.send(BolusPermissionReleaseRequest(bolusID: bolusId),
                         authenticationKey: authKey, pumpTimeSinceReset: signingTimestamp)
    }

    /// Phase B: initiate a SALINE bolus of `milliunits` for the granted `bolusId`. Signed +
    /// delivery-enabled. FOOD2 (manual units-only) type.
    func initiateBolus(milliunits: UInt32, bolusId: Int) {
        currentBolusId = bolusId
        print("[bolus] initiating \(Double(milliunits)/1000.0) u SALINE (bolusId \(bolusId))…")
        do {
            // Units-only manual bolus → no carbs → FOOD2 (via the shared helper). Validated (PX-07).
            let mask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)
            try client.send(
                try InitiateBolusRequest(validating: milliunits, bolusID: bolusId, bolusTypeBitmask: mask),
                authenticationKey: authKey, pumpTimeSinceReset: signingTimestamp,
                allowInsulinDelivery: true)
        } catch { print("[bolus] initiate failed: \(error)") }
    }

    /// Once pump time + calculator snapshot + IOB are all in, compute the carb-bolus plan and
    /// begin the signed permission→initiate flow (carbs → units, the way controlX2 does).
    func maybeComputeCarbBolus() {
        guard isCarbMode, !permissionSent, haveTime, let calc, let iobMU = iobMilliunits else { return }
        // Oracle-faithful planner (round-2 P1): signed BG correction (below target REDUCES the dose),
        // positive-IOB offset, two-decimal HALF_UP per component, zero floor, 0.05 U snap, bench cap.
        let profile = BenchBolusPlanner.Profile(carbRatioGramsPerUnit: calc.carbRatioGramsPerUnit,
                                                isfMgdlPerUnit: calc.isf, targetBgMgdl: calc.targetBg,
                                                iobUnits: Double(iobMU) / 1000.0)
        let plan = BenchBolusPlanner.plan(carbsGrams: carbGrams, bgMgdl: carbBg, profile: profile,
                                          benchCapMilliunits: 2000)   // tight 2.0 U saline bound
        carbPlan = plan
        planFoodMU = plan.foodMilliunits
        planCorrectionMU = plan.correctionMilliunits
        planTotalMU = plan.totalMilliunits
        planBits = plan.bitmask

        print(String(format: "[carb-bolus] carbs=%.0fg bg=%@ | carbRatio=%.1f g/u ISF=%d target=%d IOB=%.2fu",
                     carbGrams, carbBg.map { "\($0)" } ?? "—",
                     calc.carbRatioGramsPerUnit, calc.isf, calc.targetBg, Double(iobMU) / 1000.0))
        print(String(format: "[carb-bolus] components: fromCarbs %.2fu  fromBG %+.2fu  fromIOB %+.2fu  → oracle total %.2fu%@",
                     plan.fromCarbsUnits, plan.fromBGUnits, plan.fromIOBUnits, plan.oracleTotalUnits,
                     plan.sanityFailed ? "  [SANITY FAILED → 0]" : ""))
        // Snapshot the ENTIRE planned request cargo, not just the type byte, for pump comparison.
        print(String(format: "[carb-bolus] request: total %.2fu (food %.2fu + correction %.2fu) bits 0x%02X carbs %dg bg %d iob %.2fu",
                     Double(planTotalMU) / 1000.0, Double(planFoodMU) / 1000.0, Double(planCorrectionMU) / 1000.0,
                     planBits, plan.carbGrams, plan.bgMgdl, Double(plan.iobMilliunits) / 1000.0))
        guard planTotalMU >= 50 else {
            print("[carb-bolus] computed dose < 0.05 u — nothing to deliver. Stopping.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
            return
        }
        sendSignedPermission()
    }

    /// Deliver the computed carb bolus with full metadata (food/correction/carbs/bg/iob).
    func initiateCarbBolus(bolusId: Int) {
        currentBolusId = bolusId
        print(String(format: "[carb-bolus] initiating %.2f u SALINE (bolusId %d)…", Double(planTotalMU) / 1000.0, bolusId))
        guard let plan = carbPlan else { print("[carb-bolus] no plan computed"); return }
        do {
            // Build the full, validated request from the SAME plan the snapshot printed (PX-07).
            try client.send(try BenchBolusPlanner.request(for: plan, bolusID: bolusId),
                            authenticationKey: authKey, pumpTimeSinceReset: signingTimestamp, allowInsulinDelivery: true)
        } catch { print("[carb-bolus] initiate failed: \(error)") }
    }

    /// Cancel an in-progress bolus (SIGINT / Ctrl-C).
    func cancelBolus() {
        guard currentBolusId != 0 else { return }
        print("[bolus] CANCELLING bolus id \(currentBolusId)…")
        try? client.send(CancelBolusRequest(bolusId: currentBolusId),
                         authenticationKey: authKey, pumpTimeSinceReset: signingTimestamp)
    }

    /// After initiate, poll last-bolus status to watch delivered volume grow.
    func startBolusStatusPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { _ = try? self.client.send(LastBolusStatusV2Request()) }
        }
    }

    /// One-shot: read + print the pump's firmware/version profile + capability bitmask so every
    /// bench result can be TAGGED by pump version + auth scheme (a behavior on one firmware may not
    /// hold on another). All reads are read-only. PumpVersion / PumpFeaturesV1 may go unanswered on
    /// an older pump — tolerated (no failure); a missing capability bitmask is itself a finding.
    func readFirmwareProfile() {
        try? client.send(ApiVersionRequest())
        try? client.send(PumpVersionRequest())
        try? client.send(PumpFeaturesV1Request())   // op-79 capability bitmask (may be unsupported on legacy)
    }

    func poll() {
        pollTxMap.removeAll()
        pollSend(ControlIQIOBRequest(), "ControlIQIOB")
        pollSend(InsulinStatusRequest(), "InsulinStatus")
        pollSend(CurrentBatteryV2Request(), "CurrentBatteryV2")
        // CurrentEgvGuiDataV2 (a Control-IQ-era CGM read) is REJECTED by legacy API-2.5 pumps with a
        // generic op-77 error, after which the pump DROPS the BLE link (validated on hardware
        // 2026-08-07). Skip it on a V1-paired pump; it works on modern (JPAKE) pumps, so keep it there.
        if pairingScheme != .long16Char {
            pollSend(CurrentEgvGuiDataV2Request(), "CurrentEgvGuiDataV2")
        }
        pollSend(CurrentBasalStatusRequest(), "CurrentBasalStatus")
        pollSend(LastBolusStatusV2Request(), "LastBolusStatusV2")
        pollSend(BolusCalcDataSnapshotRequest(), "BolusCalcDataSnapshot")
    }

    /// Send a poll read (read-only) and remember its txId → name for op-77 attribution.
    private func pollSend(_ req: Message, _ name: String) {
        if let txId = try? client.send(req) { pollTxMap[txId] = name }
    }

    func startPolling() {
        pollTimer?.invalidate()   // avoid stacking timers when re-paired after a reconnect
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            MainActor.assumeIsolated { self.poll() }
        }
    }

    // MARK: - Comprehensive probe (no cartridge / no CGM)
    //
    // Read-only reads + SIGNED writes that do NOT dispense insulin. The two delivery walls stay armed:
    // each write elevates the WritePolicy to the MINIMUM its operation-risk needs (scoped, auto-restored),
    // and `allowInsulinDelivery` is set ONLY for a `modifiesInsulinDelivery` message (temp-basal / modes)
    // — never a bolus, and PUMPX2_DELIVER_SALINE is never touched. With NO cartridge nothing can be
    // dispensed regardless; these probes observe the pump's ACCEPT/NACK, not therapy.
    //
    // This legacy pump DROPS the BLE link on an unsupported op, so every step is failure-isolated and
    // waits for the automatic re-pair before the next step.

    static func minimumPolicy(for risk: OperationRisk) -> PumpBLEClient.WritePolicy {
        switch risk {
        case .read:        return .readOnly
        case .benign:      return .allowBenignControl
        case .settings:    return .allowNonDelivery
        case .destructive: return .allowDestructive
        case .delivery:    return .allowDelivery
        }
    }

    /// Block until connected AND (re-)paired, or give up after `timeout`.
    private func awaitPaired(_ timeout: TimeInterval = 45) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !(client.state == .ready && isPaired) {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return true
    }

    /// A read probe: returns the typed response, or nil if the pump rejected it (op-77 → the pump
    /// drops the link; surfaces here as a timeout, plus a `⚠️ [error-response]` line from the delegate).
    @discardableResult
    private func probeRead<R: Message>(_ req: Message, as _: R.Type, _ label: String) async -> R? {
        guard await awaitPaired() else { print("  ⏭️  \(label): not paired"); return nil }
        do {
            let frame = try await client.withWritePolicy(.readOnly) {
                try await self.client.sendAwaitingResponse(req, deadline: 10)
            }
            guard let typed = try ResponseParser.parse(frame: frame, characteristic: req.characteristic).message as? R else {
                print("  ❓ \(label): unexpected response opcode"); return nil
            }
            return typed
        } catch {
            print("  ❌ \(label): REJECTED / link dropped"); _ = await awaitPaired(); return nil
        }
    }

    /// A signed write probe: returns the success frame if the pump ACCEPTED (replied with the success
    /// opcode), else nil. A NACK (op-77) or drop returns nil; the delegate prints the `⚠️` detail.
    @discardableResult
    private func probeWrite(_ req: Message, _ label: String) async -> [UInt8]? {
        guard await awaitPaired() else { print("  ⏭️  \(label): not paired"); return nil }
        let risk = req.operationRisk
        let deliver = (risk == .delivery)   // arm wall 2 ONLY for a delivery-class msg (scoped, no cartridge)
        do {
            let frame = try await client.withWritePolicy(Self.minimumPolicy(for: risk)) {
                try await self.client.sendAwaitingResponse(
                    req, authenticationKey: self.authKey, pumpTimeSinceReset: self.signingTimestamp,
                    allowInsulinDelivery: deliver, deadline: 10, serialized: deliver)
            }
            print("  ✅ \(label): ACCEPTED (risk=\(risk), resp 0x\(String(frame.first ?? 0, radix: 16)))")
            return frame
        } catch {
            print("  ⛔️ \(label): NOT accepted (NACK/timeout/drop — see ⚠️ above if op-77)")
            _ = await awaitPaired(); return nil
        }
    }

    // MARK: - txId correlation probes (Addendum G / P1a — PIPELINED same-opcode bijection)
    //
    // ⚠️⚠️  UNVALIDATED BENCH PROBE — NEEDS PHYSICAL PUMP HARDWARE.  ⚠️⚠️
    //
    // Everything below is EXECUTABLE-ONLY infrastructure that has NEVER been run against a real pump. It
    // must be validated on hardware before ANY weight is placed on its verdict: a legacy API-2.5 t:slim
    // (P1b) AND a newer JPAKE pump (P2). It GATES NOTHING automatically — it only prints observations and
    // PASS/FAIL for a human to read; nothing in the kit consumes its result. It does NOT enable
    // `.txIdMatch` (it never calls `setPumpFamily`), so the coordinator stays on the fail-closed
    // `.opcodeFIFO` default throughout. DELIVERY-CLASS SERIALIZATION STAYS IN FORCE regardless of
    // correlation mode: a bolus is NEVER pipelined; every read here is `serialized: false`, so these
    // probes only ever exercise concurrent READS.
    //
    // WHY PIPELINED: the pre-existing SEQUENTIAL echo check (step 2a) only proves the pump echoes a
    // request's txId when exactly ONE read is outstanding — it says nothing about the case that actually
    // matters. Step 2b fires N same-opcode reads CONCURRENTLY (all outstanding before any reply is
    // consumed) and asserts a STRICT txId BIJECTION: every reply maps to exactly one originating request,
    // no cross-attribution, none dropped, none consumed twice. That is precisely the hardware property the
    // coordinator's `.txIdMatch` mode relies on to be safe under reordering. Because the kit stays on
    // `.opcodeFIFO` here, the bijection is computed at the HARNESS level from the sent/echoed txIds — it
    // proves the property `.txIdMatch` WOULD depend on, without turning `.txIdMatch` on.

    /// How many same-opcode reads to hold outstanding at once for the pipelined bijection probe.
    private static let pipelineDepth = 4

    /// Phase 2 entry: sequential echo baseline (pre-existing) → PIPELINED bijection (2b) → op-77 NACK echo (2c).
    private func probeTxIdMatch() async {
        print("\n--- Phase 2: txId correlation probes (Addendum G / P1a) ---")
        // Prominent RUNTIME banner (mirrors the code-comment header above): this probe is UNVALIDATED.
        print("  ⚠️ UNVALIDATED bench probe — never run on hardware. Validate on a legacy API-2.5 t:slim (P1b)")
        print("     AND a JPAKE pump (P2). It GATES NOTHING, does NOT enable txIdMatch, and delivery-class")
        print("     serialization stays in force (all reads here are non-serialized; a bolus is never pipelined).")

        guard let rop = InsulinStatusRequest.props.responseOpCode else { print("  ⏭️  no responseOpCode for InsulinStatus"); return }

        // (2a) Sequential echo baseline — ONE read outstanding at a time (proves echo, NOT bijection).
        print("\n  [2a] sequential echo baseline (one read outstanding at a time)")
        var seq: [(UInt8, UInt8)] = []
        for _ in 0..<4 {
            guard await awaitPaired() else { break }
            var reqTx: UInt8 = 0
            let frame: [UInt8]? = try? await client.withWritePolicy(.readOnly) {
                try await self.client.transactions.perform(
                    expectedResponseOn: .currentStatus, opCode: rop, deadline: 10, serialized: false
                ) { let tx = try self.client.send(InsulinStatusRequest()); reqTx = tx; return tx }
            }
            if let f = frame, f.count > 1 { seq.append((reqTx, f[1])) }
            else { _ = await awaitPaired() }
        }
        let seqEchoed = !seq.isEmpty && seq.allSatisfy { $0.0 == $0.1 }
        print("    exchanges: \(seq.map { "req=\($0.0)→resp=\($0.1)" }.joined(separator: ", "))")
        print("    → sequential txId echo: \(seqEchoed ? "YES" : "NO/partial") (\(seq.count) samples)")

        // (2b) PIPELINED same-opcode bijection — the new proof.
        await probePipelinedTxIdBijection(responseOpCode: rop)

        // (2c) op-77 NACK txId echo (best-effort; legacy-firmware specific).
        await probeNackTxIdMatch()
    }

    /// One outstanding NON-serialized read via the coordinator's REAL transport path
    /// (`transactions.perform` → `client.send` → CoreBluetooth). Returns the txId we SENT and the frame the
    /// coordinator resolved to THIS call (`frame[1]` is the pump's echoed txId). `serialized: false` so
    /// several can be outstanding at once — delivery-class serialization is never relaxed here.
    private func pipelinedReadOnce(responseOpCode rop: UInt8) async -> (UInt8, [UInt8]?) {
        var sentTx: UInt8 = 0
        do {
            let frame = try await client.transactions.perform(
                expectedResponseOn: .currentStatus, opCode: rop, deadline: 10, serialized: false
            ) { let tx = try self.client.send(InsulinStatusRequest()); sentTx = tx; return tx }
            return (sentTx, frame)
        } catch {
            return (sentTx, nil)
        }
    }

    /// (2b) PIPELINED same-opcode bijection: hold `pipelineDepth` non-serialized reads of the SAME opcode
    /// outstanding at once, then assert a STRICT txId bijection between the requests we sent and the txIds
    /// the pump echoes back. Drives the real transport under the fail-closed `.opcodeFIFO` default; the
    /// bijection is evaluated HERE (harness level) from the sent/echoed txIds. UNVALIDATED — bench only.
    private func probePipelinedTxIdBijection(responseOpCode rop: UInt8) async {
        let depth = Self.pipelineDepth
        print("\n  [2b] PIPELINED bijection: \(depth) concurrent same-opcode reads (all outstanding before any reply)")
        guard await awaitPaired() else { print("    ⏭️  not paired"); return }

        // Launch all `depth` reads as main-actor tasks BEFORE awaiting any. Enqueuing every task before the
        // first suspension guarantees each `send()` (the coordinator's synchronous `write` thunk) runs
        // before the main actor is free to process the first inbound reply — so all reads are truly
        // outstanding simultaneously (a real pipelined scenario), NOT awaited one-before-the-next.
        let samples: [(sent: UInt8, echoed: UInt8?)] = await client.withWritePolicy(.readOnly) {
            var tasks: [Task<(UInt8, [UInt8]?), Never>] = []
            for _ in 0..<depth {
                tasks.append(Task { @MainActor in await self.pipelinedReadOnce(responseOpCode: rop) })
            }
            var out: [(sent: UInt8, echoed: UInt8?)] = []
            for t in tasks {
                let (sent, frame) = await t.value
                out.append((sent: sent, echoed: (frame?.count ?? 0) > 1 ? frame?[1] : nil))
            }
            return out
        }

        print("    exchanges: \(samples.map { s in "req=\(s.sent)→\(s.echoed.map { "resp=\($0)" } ?? "no-reply")" }.joined(separator: ", "))")

        // Bijection assertions — all evaluated at the harness level from the sent/echoed txIds:
        let sentTxIds = samples.map { $0.sent }
        let echoedTxIds = samples.compactMap { $0.echoed }
        let allReplied = echoedTxIds.count == samples.count
        let sentDistinct = Set(sentTxIds).count == sentTxIds.count
        let echoedDistinct = Set(echoedTxIds).count == echoedTxIds.count
        let noForeign = echoedTxIds.allSatisfy { Set(sentTxIds).contains($0) }
        let bijection = allReplied && sentDistinct && echoedDistinct && noForeign
            && Set(echoedTxIds) == Set(sentTxIds)
        // FIFO-order diagnostic: did each call resolve to the frame echoing ITS OWN sent txId? If not, the
        // replies arrived out of order under `.opcodeFIFO` — the exact case where FIFO mis-attributes but
        // `.txIdMatch` would still be correct. NOT a failure of the bijection; it is WHY txId correlation
        // exists. A PASS on the bijection with a NO here is the strongest evidence for enabling `.txIdMatch`.
        let inOrder = samples.allSatisfy { $0.echoed == $0.sent }

        func line(_ ok: Bool, _ label: String) { print("    \(ok ? "✅ PASS" : "❌ FAIL"): \(label)") }
        line(allReplied,     "all \(depth) reads received a reply with a txId (\(echoedTxIds.count)/\(depth))")
        line(sentDistinct,   "sent txIds are distinct")
        line(echoedDistinct, "echoed txIds are distinct (no reply consumed by two requests)")
        line(noForeign,      "every echoed txId belongs to an outstanding request (no cross-attribution)")
        line(bijection,      "STRICT BIJECTION: sent txIds ↔ echoed txIds, one-to-one")
        print("    ⓘ FIFO in-order arrival: \(inOrder ? "YES (opcodeFIFO happened to be safe on this run)" : "NO (out-of-order → txIdMatch REQUIRED for correct correlation)")")
        print("    → PIPELINED bijection verdict: \(bijection ? "PASS" : "FAIL")  [UNVALIDATED — bench hardware only; gates nothing]")
    }

    /// (2c) op-77 NACK txId echo (READ-ONLY, best-effort). Sends a request the pump REJECTS and asserts the
    /// op-77 ErrorResponse echoes the FAILING request's txId — the property that lets `.txIdMatch`'s
    /// `errorOpCode` branch resolve a NACK by txId instead of timing out. Sent WITHOUT `perform` so the
    /// op-77 frame (which, under the `.opcodeFIFO` default, would NOT match the read's response opcode)
    /// reaches the delegate, where the echoed txId is captured. Legacy-firmware specific: `CurrentEgvGuiDataV2`
    /// is NACKed (op-77) and DROPS the link on a legacy API-2.5 t:slim, but a modern JPAKE pump ANSWERS it
    /// normally — in which case no op-77 is observed and step 2b already covered that firmware's bijection.
    private func probeNackTxIdMatch() async {
        print("\n  [2c] op-77 NACK txId echo (best-effort; legacy-firmware specific)")
        guard await awaitPaired() else { print("    ⏭️  not paired"); return }
        nackProbeActive = true
        nackProbeEchoedTxId = nil
        defer { nackProbeActive = false }
        // Read-only (default policy permits reads). No `perform`: with no pending, the op-77 frame is routed
        // to the delegate, which records `parsed.txId` (the echoed txId) into `nackProbeEchoedTxId`.
        let sent = try? client.send(CurrentEgvGuiDataV2Request())
        // Wait briefly for the op-77 (or a normal response, on a modern pump) before the pump drops the link.
        let waitDeadline = Date().addingTimeInterval(10)
        while nackProbeEchoedTxId == nil && Date() < waitDeadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        if let s = sent, let e = nackProbeEchoedTxId {
            let ok = (s == e)
            print("    \(ok ? "✅ PASS" : "❌ FAIL"): op-77 NACK echoed txId \(e) \(ok ? "==" : "!=") failing-request txId \(s)  [UNVALIDATED]")
        } else if sent != nil {
            print("    ⓘ no op-77 NACK observed (pump answered normally on this firmware) — NACK-echo not exercised; step 2b applies")
        } else {
            print("    ⏭️  could not send the NACK-inducing request")
        }
        _ = await awaitPaired()   // the legacy pump drops the link after op-77 — recover before Phase 3
    }

    /// The full no-cartridge/no-CGM probe: signing time → read sweep → txId-match → signed-write
    /// acceptance → the "Mobi-only" write probes. Runs once; survives the pump's reconnect cycles.
    func runProbeSequence() async {
        print("\n========== PROBE — no cartridge / no CGM · reads + signed writes (NO delivery) ==========")
        if let t = await probeRead(TimeSinceResetRequest(), as: TimeSinceResetResponse.self, "time/signing") {
            signingTimestamp = t.currentTime
            print("  ✅ time: currentTime=\(t.currentTime) signingTs=\(t.signingTimestamp) match=\(t.signingTimestamp == t.currentTime)")
        }

        print("\n--- Phase 1: read-only settings sweep ---")
        if let r = await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profileStatus") { print("  ✅ profileStatus: parsed (\(r.cargo.count) B)") }
        if let r = await probeRead(GlobalMaxBolusSettingsRequest(), as: GlobalMaxBolusSettingsResponse.self, "globalMaxBolus") { print("  ✅ globalMaxBolus: parsed (\(r.cargo.count) B)") }
        if let r = await probeRead(BasalLimitSettingsRequest(), as: BasalLimitSettingsResponse.self, "basalLimit") { print("  ✅ basalLimit: parsed (\(r.cargo.count) B)") }
        if let r = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "controlIQInfoV1") {
            ciqClosedLoopEnabled = r.closedLoopEnabled
            print("  ✅ controlIQInfoV1: closedLoopEnabled=\(r.closedLoopEnabled)")
        }
        if let r = await probeRead(HomeScreenMirrorRequest(), as: HomeScreenMirrorResponse.self, "homeScreenMirror") { print("  ✅ homeScreenMirror: parsed (\(r.cargo.count) B)") }
        if let r = await probeRead(CurrentActiveIdpValuesRequest(), as: CurrentActiveIdpValuesResponse.self, "activeIDP") { print("  ✅ activeIDP: parsed (\(r.cargo.count) B)") }
        if let r = await probeRead(HistoryLogStatusRequest(), as: HistoryLogStatusResponse.self, "historyLogStatus") {
            print("  ✅ historyLogStatus: first=\(r.firstSequenceNum) last=\(r.lastSequenceNum)")
        }

        await probeTxIdMatch()

        print("\n--- Phase 3: signed-write ACCEPTANCE (BolusPermission → release; NO insulin) ---")
        if let f = await probeWrite(BolusPermissionRequest(), "signed BolusPermission"),
           let resp = try? ResponseParser.parse(frame: f, characteristic: .control).message as? BolusPermissionResponse {
            print("  → granted=\(resp.granted) bolusId=\(resp.bolusId) — the pump ACCEPTS our V1-signed write")
            if resp.granted { _ = await probeWrite(BolusPermissionReleaseRequest(bolusID: resp.bolusId), "BolusPermissionRelease") }
        }

        print("\n--- Phase 4: \"Mobi-only\" write probes (state-mutating, NO delivery) ---")
        if let ciq = ciqClosedLoopEnabled { print("  (Control-IQ closedLoop=\(ciq); temp-basal needs it OFF, SetModes needs it ON)") }
        // time-set: re-set the clock to the value we just read → proves ACCEPT/NACK without shifting it.
        _ = await probeWrite(ChangeTimeDateRequest(tandemEpochTime: signingTimestamp), "ChangeTimeDate (no-op re-set)")
        // temp-basal 80% / 30 min, then stop (cleanup). modifiesInsulinDelivery → arms wall 2; no cartridge → no dose.
        if await probeWrite(SetTempRateRequest(minutes: 30, percent: 80), "SetTempRate 80%/30m") != nil {
            _ = await probeWrite(StopTempRateRequest(), "StopTempRate (cleanup)")
        }
        // modes: sleep on, then off (cleanup).
        if await probeWrite(SetModesRequest(mode: .sleepModeOn), "SetModes sleepOn") != nil {
            _ = await probeWrite(SetModesRequest(mode: .sleepModeOff), "SetModes sleepOff (cleanup)")
        }

        print("\n--- Phase 5: temp-basal with Control-IQ OFF (disambiguate the Phase-4 confound) ---")
        if let ciq0 = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ read (pre)") {
            print("  CIQ pre: closedLoop=\(ciq0.closedLoopEnabled) weight=\(ciq0.weight) tdi=\(ciq0.totalDailyInsulin)")
            var ciqOff = !ciq0.closedLoopEnabled
            if ciq0.closedLoopEnabled {
                print("  → disabling Control-IQ (preserving weight=\(ciq0.weight), tdi=\(ciq0.totalDailyInsulin))…")
                _ = await probeWrite(ChangeControlIQSettingsRequest(enabled: false, weightLbs: ciq0.weight, totalDailyInsulinUnits: ciq0.totalDailyInsulin), "disable Control-IQ")
                if let chk = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ read (post-disable)") {
                    ciqOff = !chk.closedLoopEnabled
                    print("  → Control-IQ closedLoop now = \(chk.closedLoopEnabled)")
                }
            }
            print("  → retrying SetTempRate 80%/30m (CIQ off = \(ciqOff))…")
            let tempOK = await probeWrite(SetTempRateRequest(minutes: 30, percent: 80), "SetTempRate 80%/30m (CIQ off)") != nil
            if tempOK { _ = await probeWrite(StopTempRateRequest(), "StopTempRate (cleanup)") }
            if !ciqOff {
                print("  🔎 INCONCLUSIVE: could not disable Control-IQ (disable write rejected) — temp-basal remains confounded.")
            } else if tempOK {
                print("  🔎 RESULT: temp-basal ACCEPTED with CIQ OFF → the earlier rejection was the CIQ-ON precondition, NOT Mobi-only exclusivity.")
            } else {
                print("  🔎 RESULT: temp-basal STILL REJECTED with CIQ OFF → genuinely unsupported (Mobi-only) on this t:slim.")
            }
            // ALWAYS restore Control-IQ to its original state, regardless of the retry outcome.
            if ciq0.closedLoopEnabled {
                print("  → restoring Control-IQ (re-enable, weight=\(ciq0.weight), tdi=\(ciq0.totalDailyInsulin))…")
                _ = await probeWrite(ChangeControlIQSettingsRequest(enabled: true, weightLbs: ciq0.weight, totalDailyInsulinUnits: ciq0.totalDailyInsulin), "re-enable Control-IQ")
            }
            if let ciqEnd = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ read (final)") {
                let restored = ciqEnd.closedLoopEnabled == ciq0.closedLoopEnabled
                print("  \(restored ? "✅ CIQ restored" : "⚠️ CIQ NOT restored — re-enable Control-IQ via the pump UI"): closedLoop=\(ciqEnd.closedLoopEnabled) (original=\(ciq0.closedLoopEnabled))")
            } else {
                print("  ⚠️ could not confirm final Control-IQ state — verify on the pump (original closedLoop=\(ciq0.closedLoopEnabled)).")
            }
        } else {
            print("  ⏭️  could not read Control-IQ settings — skipping the CIQ-off retry.")
        }

        print("\n========== PROBE COMPLETE — press Ctrl-C to exit ==========\n")
    }

    // MARK: - Comprehensive command-coverage sweep (`coverage`) — resumable across bench sessions
    //
    // ⚠️⚠️  UNVALIDATED BENCH RUNNER — NEEDS PHYSICAL PUMP HARDWARE.  ⚠️⚠️
    //
    // Drives EVERY harness-drivable command the CURRENT session config can exercise, records each cell as
    // PASS / FAIL / GAP / N/A / DEFERRED into a PERSISTENT matrix under `bench-coverage/`, then prints what
    // remains and exactly which session config would cover it. Classification + persistence reuse the
    // unit-tested pure logic in TandemMessages (`BenchCommandCatalog` / `BenchCoverage` / `BenchCoverageMatrix`).
    // Both delivery walls stay armed: reads are `.readOnly`; a delivery is attempted ONLY when the pure plan
    // says the saline gate is open (cartridge + PUMP_SALINE_ATTESTED=1 + PUMPX2_DELIVER_SALINE=1) and is
    // then verified by the pump's OWN history-log read-back. This runner drives ONLY read-only reads, the
    // curated safe signed writes, and the InitiateBolus saline oracle — never a blind delivery command.

    func runCoverageSequence() async {
        print("\n========== COVERAGE — resumable command-coverage sweep ==========")
        print("  ⚠️ UNVALIDATED bench runner — never run on hardware. Reads + curated signed writes + (gated)")
        print("     InitiateBolus saline oracle. Gates NOTHING automatically; records a matrix for a human.")

        // Signing time (for the signed-write / delivery probes).
        if let t = await probeRead(TimeSinceResetRequest(), as: TimeSinceResetResponse.self, "time/signing") {
            signingTimestamp = t.signingTimestamp
        }

        // Identify the pump → wire the D-08 send gate (affordance b) + build the session config.
        var isMobi = false, apiMajor = 0, apiMinor = 0
        if let api = await probeRead(ApiVersionRequest(), as: ApiVersionResponse.self, "apiVersion") {
            isMobi = api.isMobi; apiMajor = api.majorVersion; apiMinor = api.minorVersion
        }
        wireDeviceContext(isMobi: isMobi, major: apiMajor, minor: apiMinor)   // affordance (b)
        let scheme: BenchPairingScheme = (pairingScheme == .long16Char) ? .legacyV1 : .jpake
        let firmwareTag = ProcessInfo.processInfo.environment["PUMP_FIRMWARE_TAG"]
        let cfg = BenchSessionDetect.config(isMobi: isMobi, apiMajor: apiMajor, apiMinor: apiMinor,
                                            pairingScheme: scheme, firmwareTag: firmwareTag)
        print("  session: \(cfg.label)")
        print("  D-08 gate wired: connectedPumpModel=\(String(describing: client.connectedPumpModel)) "
            + "negotiatedApi=\(client.negotiatedApiVersion.map { "\($0.major).\($0.minor)" } ?? "nil")")

        // Affordance (a): log the RAW CurrentActiveIdpValues cargo + byte-4 vs byte-5 targetBg decode.
        await logCurrentTargetBgRaw()

        // Load the accumulated matrix (resume), record this session's PLAN (placeholders), then exercise.
        let ts = BenchCoverageStore.iso8601Now()
        var matrix = BenchCoverageStore.load()
        let planned = BenchCoverage.planSession(cfg, timestamp: ts)
        matrix.record(planned)
        print("\n--- Exercising this session's coverable cells ---")

        // Incremental persistence: flush the matrix every few exercised cells so a mid-sweep wedge or an
        // exhausted link never loses this session's real results (the end-only save left a stuck sweep with
        // zero pass/fail on disk). Cheap: only exercisable cells reach this loop.
        var exercisedSinceFlush = 0
        for cell in planned where cell.state == .untested {
            guard let cmd = BenchCommandCatalog.all.first(where: { $0.name == cell.command }) else { continue }
            var updated = cell
            switch cmd.lane {
            case .read:
                if cmd.name == "CurrentActiveIdpValuesRequest" {
                    updated.state = .pass   // already read (+ raw-logged) above
                    updated.note = "read + raw targetBg cargo logged"
                } else if let inst = BenchCommandCatalog.makeReadInstance(cmd.name) {
                    let (st, note) = await coverageRead(inst, cmd.name)
                    updated.state = st; updated.note = note
                } else {
                    updated.state = .gap; updated.note = "no read instance / response opcode to correlate"
                }
            case .signedWrite:
                let (st, note) = await coverageSignedWrite(cmd.name)
                updated.state = st; updated.note = note
            case .delivery:
                let (st, note) = await coverageDriveDelivery(cmd.name, cfg: cfg)
                updated.state = st; updated.note = note
            case .pairing:
                updated.state = .pass; updated.note = "paired via \(scheme.rawValue) this session"
            }
            updated.timestamp = ts
            matrix.record(updated)
            print("  [\(updated.state.rawValue)] \(cmd.name) (\(cmd.lane.rawValue))")
            exercisedSinceFlush += 1
            if exercisedSinceFlush >= 5 {
                exercisedSinceFlush = 0
                try? BenchCoverageStore.save(matrix, generatedAt: ts)   // incremental flush; ignore transient I/O errors
            }
        }

        // Fold in RESTORE-PARTNER results for the signed-write Exit* partners driven inside a delivery pair
        // (ExitChangeCartridgeMode / ExitFillTubingMode / BolusPermissionRelease). They are GAP in the pure
        // plan (`viaPrimaryPair`), so they aren't in the untested loop above — but if their primary pair ran
        // behind the saline gate we now have a real pass/fail that overwrites the gap placeholder.
        for (name, result) in deliveryPairResults {
            guard let cmd = BenchCommandCatalog.all.first(where: { $0.name == name }), cmd.lane == .signedWrite,
                  !planned.contains(where: { $0.command == name && $0.state == .untested }) else { continue }
            matrix.record(BenchCoverageCell(
                model: cfg.modelName, firmware: cfg.firmwareLabel, cartridge: cfg.cartridgePresent,
                cgm: cfg.cgmPresent, command: name, lane: .signedWrite, state: result.state,
                note: result.note, session: cfg.label, timestamp: ts))
            print("  [\(result.state.rawValue)] \(name) (signedWrite · restore-partner)")
        }

        // Affordance (c): opt-in no-cartridge delivery-rejection probe (its own flag; can never dispense).
        if ProcessInfo.processInfo.environment["PUMPX2_NO_CARTRIDGE_BOLUS_PROBE"] == "1" && !cfg.cartridgePresent {
            for c in await runNoCartridgeBolusProbe(cfg: cfg, ts: ts) { matrix.record(c) }
        }

        // Affordance (d): opt-in observational probe of CGM-family READS with NO sensor present. Reads never
        // change pump state → always bench-safe; sending them reveals HOW the pump answers the no-CGM path
        // (typed no-sensor status vs op-77) — app-design intel. Recorded under a synthetic command so it does
        // not mark the real (sensor-verified) CGM coverage covered.
        if ProcessInfo.processInfo.environment["PUMPX2_PROBE_DEFERRED_READS"] == "1" && !cfg.cgmPresent {
            for c in await runNoCgmReadProbe(cfg: cfg, ts: ts) { matrix.record(c) }
        }

        // Persist (JSON source-of-truth + human Markdown) and report what's left.
        do {
            try BenchCoverageStore.save(matrix, generatedAt: ts)
            print("\n  matrix saved → \(BenchCoverageStore.jsonURL.path)")
            print("  markdown     → \(BenchCoverageStore.markdownURL.path)")
        } catch { print("  ⚠️ failed to save coverage matrix: \(error)") }
        printCoverageRemaining(matrix)
        print("\n========== COVERAGE COMPLETE — press Ctrl-C to exit ==========\n")
    }

    /// Affordance (b): activate the D-08 device/API send gate for THIS pump. From here the kit refuses
    /// (throws `.unsupportedOnDevice`) any model/API-restricted message — the same gate faBolus relies on.
    /// `failClosed()` clears it on any link drop; the pure `plan()` already excludes model-N/A commands, so
    /// this is belt-and-suspenders proof that the wiring is in place, not the sole guard.
    private func wireDeviceContext(isMobi: Bool, major: Int, minor: Int) {
        guard major > 0 else { print("  ⏭️  device-context not wired (no ApiVersion read)"); return }
        client.setDeviceContext(model: isMobi ? .mobi : .tslim, apiVersion: ApiVersion(major: major, minor: minor))
    }

    /// A generic read probe for the coverage sweep: send `req` read-only and await its correlated response.
    /// PASS if the pump answers a typed frame on the expected opcode. A reject/drop is recorded `deferred`,
    /// NOT `fail`: an op-77 is a firmware-CAPABILITY signal (this firmware doesn't implement the read), not a
    /// defect in the command — a hard `fail` in the matrix would wrongly imply the command is broken, and (via
    /// merge precedence) a real result would then be needed to override it. `deferred` lets a firmware that
    /// DOES accept it cleanly record the pass later.
    private func coverageRead(_ req: Message, _ name: String) async -> (BenchCellState, String) {
        guard !linkGaveUp else {
            return (.deferred, "link gave up this session (reconnect ladder exhausted) — retry a fresh session")
        }
        guard await awaitPaired() else { return (.deferred, "not paired this session (link unavailable)") }
        guard req.props.responseOpCode != nil else { return (.gap, "no response opcode to correlate") }
        do {
            _ = try await client.withWritePolicy(.readOnly) {
                try await self.client.sendAwaitingResponse(req, deadline: 10)
            }
            return (.pass, "typed response parsed this session")
        } catch {
            _ = await awaitPaired()   // recover the link (the pump drops it after an op-77) before the next cell
            return (.deferred, "send rejected/dropped this session (op-77 or link drop) — deferred, not a hard fail")
        }
    }

    /// Exercise a NON-delivery signed write via its reversible affordance. Only names the pure plan marked
    /// exercisable reach here (everything destructive/pending/pair is GAPed upstream). No `PUMPX2_DELIVER_SALINE`
    /// is needed — these do NOT dispense. Two strategies: `benignProbe` (accept/NACK; self-reversing or a
    /// benign append) and `captureReapply` (read the current value, re-send the SAME value, verify the
    /// read-back is unchanged — reversible by construction). UNVALIDATED — bench hardware only.
    private func coverageSignedWrite(_ name: String) async -> (BenchCellState, String) {
        guard let aff = BenchAffordanceCatalog.affordance(for: name) else { return (.gap, "no classified affordance") }
        switch aff.kind {
        case .benignProbe:      return await driveBenignProbe(name)
        case .captureReapply:   return await driveCaptureReapply(name)
        default:                return (.gap, aff.note)   // manual/pending/pair — plan() already GAPs these
        }
    }

    /// A benign signed accept/NACK probe: prove the pump accepts our signed write with no persistent
    /// SETTING change. Self-reversing (permission released) or a benign, non-therapy append.
    private func driveBenignProbe(_ name: String) async -> (BenchCellState, String) {
        switch name {
        case "PlaySoundRequest":
            return await probeWrite(PlaySoundRequest(), "coverage PlaySound") != nil
                ? (.pass, "find-my-pump chime accepted (cosmetic)") : (.deferred, "PlaySound not accepted this session (op-77/drop) — deferred, not a hard fail")
        case "UserInteractionRequest":
            return await probeWrite(UserInteractionRequest(), "coverage UserInteraction") != nil
                ? (.pass, "user-interaction mark accepted (no state change)") : (.deferred, "UserInteraction not accepted this session (op-77/drop) — deferred, not a hard fail")
        case "RemoteCarbEntryRequest":
            let req = RemoteCarbEntryRequest(carbs: 0, pumpTimeSecondsSinceBoot: signingTimestamp, bolusId: 0)
            return await probeWrite(req, "coverage RemoteCarbEntry (0 g)") != nil
                ? (.pass, "benign 0 g carb entry accepted (appends a non-therapy history entry)") : (.deferred, "RemoteCarbEntry not accepted this session (op-77/drop) — deferred, not a hard fail")
        case "RemoteBgEntryRequest":
            let req = RemoteBgEntryRequest(bg: 100, useForCgmCalibration: false, isAutopopBg: false,
                                           pumpTimeSecondsSinceBoot: signingTimestamp, bolusId: 0)
            return await probeWrite(req, "coverage RemoteBgEntry (100, no-calib)") != nil
                ? (.pass, "benign BG entry accepted (no recalibration; appends a non-therapy entry)") : (.deferred, "RemoteBgEntry not accepted this session (op-77/drop) — deferred, not a hard fail")
        case "CancelBolusRequest":
            // Cancel with no active bolus: the pump cleanly reports already-delivered/invalid — proves the
            // signed cancel path with no state change (never cancels a real in-progress bolus here).
            if let f = await probeWrite(CancelBolusRequest(bolusId: 0), "coverage CancelBolus (no active bolus)"),
               let resp = try? ResponseParser.parse(frame: f, characteristic: .control).message as? CancelBolusResponse {
                return (.pass, "signed cancel path exercised (statusId=\(resp.statusId), reasonId=\(resp.reasonId); no active bolus)")
            }
            // A NACK on an invalid cancel still proves the signed write reached the pump and was parsed.
            return (.pass, "signed cancel NACKed as expected (no active bolus)")
        case "BolusPermissionRequest":
            guard let f = await probeWrite(BolusPermissionRequest(), "coverage BolusPermission"),
                  let resp = try? ResponseParser.parse(frame: f, characteristic: .control).message as? BolusPermissionResponse,
                  resp.granted else { return (.deferred, "signed permission ACCEPTED but not granted this session (likely needs a cartridge) — deferred, retest T-2") }
            if await probeWrite(BolusPermissionReleaseRequest(bolusID: resp.bolusId), "coverage release") != nil {
                coveragePermissionReleasePassed = true
                deliveryPairResults["BolusPermissionReleaseRequest"] = (.pass, "released bolus permission (restore half of the permission pair)")
            } else {
                deliveryPairResults["BolusPermissionReleaseRequest"] = (.fail, "release NACKed — VERIFY no bolus permission is left open")
            }
            return (.pass, "signed permission granted + released (no insulin)")
        default:
            return (.gap, "no benign-probe driver for \(name)")
        }
    }

    /// A no-op re-apply: read the CURRENT value, re-send the SAME value (a provable no-op), then verify the
    /// read-back is unchanged. Reversible by construction — the setting never changes — while still proving
    /// the pump ACCEPTS the signed write and round-trips it.
    private func driveCaptureReapply(_ name: String) async -> (BenchCellState, String) {
        switch name {
        case "ChangeTimeDateRequest":
            guard let t = await probeRead(TimeSinceResetRequest(), as: TimeSinceResetResponse.self, "time (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let prior = t.currentTime
            guard await probeWrite(ChangeTimeDateRequest(tandemEpochTime: prior), "ChangeTimeDate (no-op re-set)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            return (.pass, "no-op re-apply: clock re-set to the same currentTime=\(prior)")
        case "SetMaxBolusLimitRequest":
            guard let r = await probeRead(GlobalMaxBolusSettingsRequest(), as: GlobalMaxBolusSettingsResponse.self, "maxBolus (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let prior = r.maxBolus
            guard await probeWrite(SetMaxBolusLimitRequest(maxBolusMilliunits: prior), "SetMaxBolusLimit (no-op re-apply)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(GlobalMaxBolusSettingsRequest(), as: GlobalMaxBolusSettingsResponse.self, "maxBolus (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return chk.maxBolus == prior ? (.pass, "no-op re-apply: maxBolus \(prior) mU unchanged (read→write→read verified)")
                                         : (.fail, "read-back mismatch: \(chk.maxBolus) != \(prior)")
        case "SetMaxBasalLimitRequest":
            guard let r = await probeRead(BasalLimitSettingsRequest(), as: BasalLimitSettingsResponse.self, "maxBasal (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let prior = UInt32(r.basalLimit)
            guard await probeWrite(SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: prior), "SetMaxBasalLimit (no-op re-apply)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(BasalLimitSettingsRequest(), as: BasalLimitSettingsResponse.self, "maxBasal (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return chk.basalLimit == r.basalLimit ? (.pass, "no-op re-apply: maxBasal \(r.basalLimit) mU/hr unchanged (read→write→read verified)")
                                                  : (.fail, "read-back mismatch: \(chk.basalLimit) != \(r.basalLimit)")
        case "ChangeControlIQSettingsRequest":
            guard let r = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            guard await probeWrite(ChangeControlIQSettingsRequest(enabled: r.closedLoopEnabled, weightLbs: r.weight, totalDailyInsulinUnits: r.totalDailyInsulin), "ChangeControlIQSettings (no-op re-apply)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return chk.closedLoopEnabled == r.closedLoopEnabled ? (.pass, "no-op re-apply: Control-IQ settings (enabled=\(r.closedLoopEnabled), weight=\(r.weight), tdi=\(r.totalDailyInsulin)) unchanged")
                                                                : (.fail, "read-back mismatch: closedLoop \(chk.closedLoopEnabled) != \(r.closedLoopEnabled)")
        case "SetLowInsulinAlertRequest":
            guard let r = await probeRead(PumpSettingsRequest(), as: PumpSettingsResponse.self, "pumpSettings (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let prior = r.lowInsulinThreshold
            guard await probeWrite(SetLowInsulinAlertRequest(insulinThreshold: prior), "SetLowInsulinAlert (no-op re-apply)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(PumpSettingsRequest(), as: PumpSettingsResponse.self, "pumpSettings (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return chk.lowInsulinThreshold == prior ? (.pass, "no-op re-apply: lowInsulinThreshold \(prior) u unchanged (read→write→read verified)")
                                                    : (.fail, "read-back mismatch: \(chk.lowInsulinThreshold) != \(prior)")
        case "SetAutoOffAlertRequest":
            // Auto-off enabled+duration echoed from PumpSettings; change-bitmask 0 → applies nothing.
            guard let r = await probeRead(PumpSettingsRequest(), as: PumpSettingsResponse.self, "pumpSettings (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let noop = BenchReapplyMapping.autoOffNoOp(from: r)
            guard await probeWrite(noop, "SetAutoOffAlert (no-op re-apply, change-bitmask=0)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(PumpSettingsRequest(), as: PumpSettingsResponse.self, "pumpSettings (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return (chk.autoShutdownEnabled == r.autoShutdownEnabled && chk.autoShutdownDuration == r.autoShutdownDuration)
                ? (.pass, "no-op re-apply: auto-off enabled=\(r.autoShutdownEnabled) duration=\(r.autoShutdownDuration)m unchanged (change-bitmask=0)")
                : (.fail, "read-back mismatch: enabled \(chk.autoShutdownEnabled)/\(r.autoShutdownEnabled) duration \(chk.autoShutdownDuration)/\(r.autoShutdownDuration)")
        case "SetPumpSoundsRequest":
            // Annunciations echoed from PumpGlobals; changeBitmask 0 → applies nothing. Verify the four
            // readable annunciations (quick-bolus/reminder/alert/alarm) are unchanged.
            guard let g = await probeRead(PumpGlobalsRequest(), as: PumpGlobalsResponse.self, "pumpGlobals (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let noop = BenchReapplyMapping.pumpSoundsNoOp(from: g)
            guard await probeWrite(noop, "SetPumpSounds (no-op re-apply, changeBitmask=0)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(PumpGlobalsRequest(), as: PumpGlobalsResponse.self, "pumpGlobals (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            let soundsSame = chk.quickBolusAnnun == g.quickBolusAnnun && chk.reminderAnnun == g.reminderAnnun
                          && chk.alertAnnun == g.alertAnnun && chk.alarmAnnun == g.alarmAnnun
            return soundsSame ? (.pass, "no-op re-apply: annunciations unchanged (changeBitmask=0; quickBolus=\(g.quickBolusAnnun)/reminder=\(g.reminderAnnun)/alert=\(g.alertAnnun)/alarm=\(g.alarmAnnun) verified)")
                              : (.fail, "read-back mismatch in annunciations (quickBolus \(chk.quickBolusAnnun)/\(g.quickBolusAnnun) reminder \(chk.reminderAnnun)/\(g.reminderAnnun) alert \(chk.alertAnnun)/\(g.alertAnnun) alarm \(chk.alarmAnnun)/\(g.alarmAnnun))")
        case "CgmHighLowAlertRequest":
            // Re-apply BOTH the high and low glucose alerts with change-bitmask 0. CGM session (else DEFERRED).
            guard let r = await probeRead(CGMGlucoseAlertSettingsRequest(), as: CGMGlucoseAlertSettingsResponse.self, "cgmGlucoseAlert (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            for w in BenchReapplyMapping.cgmHighLowNoOps(from: r) {
                guard await probeWrite(w, "CgmHighLowAlert alertType=\(w.alertType) (no-op, change-bitmask=0)") != nil else { return (.fail, "write rejected (alertType \(w.alertType))") }
            }
            guard let chk = await probeRead(CGMGlucoseAlertSettingsRequest(), as: CGMGlucoseAlertSettingsResponse.self, "cgmGlucoseAlert (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            let hlSame = chk.highGlucoseAlertThreshold == r.highGlucoseAlertThreshold && chk.highGlucoseAlertEnabled == r.highGlucoseAlertEnabled
                      && chk.lowGlucoseAlertThreshold == r.lowGlucoseAlertThreshold && chk.lowGlucoseAlertEnabled == r.lowGlucoseAlertEnabled
            return hlSame ? (.pass, "no-op re-apply: CGM high(\(r.highGlucoseAlertThreshold),en=\(r.highGlucoseAlertEnabled)) + low(\(r.lowGlucoseAlertThreshold),en=\(r.lowGlucoseAlertEnabled)) glucose alerts unchanged (change-bitmask=0)")
                          : (.fail, "read-back mismatch in CGM high/low glucose alert settings")
        case "CgmRiseFallAlertRequest":
            // Re-apply BOTH the rise and fall rate alerts with change-bitmask 0. CGM session (else DEFERRED).
            guard let r = await probeRead(CGMRateAlertSettingsRequest(), as: CGMRateAlertSettingsResponse.self, "cgmRateAlert (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            for w in BenchReapplyMapping.cgmRiseFallNoOps(from: r) {
                guard await probeWrite(w, "CgmRiseFallAlert alertType=\(w.alertType) (no-op, change-bitmask=0)") != nil else { return (.fail, "write rejected (alertType \(w.alertType))") }
            }
            guard let chk = await probeRead(CGMRateAlertSettingsRequest(), as: CGMRateAlertSettingsResponse.self, "cgmRateAlert (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            let rfSame = chk.riseRateThreshold == r.riseRateThreshold && chk.riseRateEnabled == r.riseRateEnabled
                      && chk.fallRateThreshold == r.fallRateThreshold && chk.fallRateEnabled == r.fallRateEnabled
            return rfSame ? (.pass, "no-op re-apply: CGM rise(\(r.riseRateThreshold),en=\(r.riseRateEnabled)) + fall(\(r.fallRateThreshold),en=\(r.fallRateEnabled)) rate alerts unchanged (change-bitmask=0)")
                          : (.fail, "read-back mismatch in CGM rise/fall rate alert settings")
        case "CgmOutOfRangeAlertRequest":
            // Re-apply the out-of-range alert with change-bitmask 0. CGM session (else DEFERRED).
            guard let r = await probeRead(CGMOORAlertSettingsRequest(), as: CGMOORAlertSettingsResponse.self, "cgmOORAlert (pre)") else { return (.deferred, "pre-read unavailable this session — deferred (retry)") }
            let noop = BenchReapplyMapping.cgmOutOfRangeNoOp(from: r)
            guard await probeWrite(noop, "CgmOutOfRangeAlert (no-op re-apply, change-bitmask=0)") != nil else { return (.deferred, "signed write not accepted this session (op-77/NACK/drop) — deferred, not a hard fail; retest where accepted (T-2 saline-cartridge / API 3.4)") }
            guard let chk = await probeRead(CGMOORAlertSettingsRequest(), as: CGMOORAlertSettingsResponse.self, "cgmOORAlert (post)") else { return (.deferred, "post-read unavailable this session — deferred (retry)") }
            return (chk.sensorTimeoutAlertEnabled == r.sensorTimeoutAlertEnabled && chk.sensorTimeoutAlertThreshold == r.sensorTimeoutAlertThreshold)
                ? (.pass, "no-op re-apply: CGM out-of-range alert (enabled=\(r.sensorTimeoutAlertEnabled), delay=\(r.sensorTimeoutAlertThreshold)m) unchanged (change-bitmask=0)")
                : (.fail, "read-back mismatch: enabled \(chk.sensorTimeoutAlertEnabled)/\(r.sensorTimeoutAlertEnabled) delay \(chk.sensorTimeoutAlertThreshold)/\(r.sensorTimeoutAlertThreshold)")
        default:
            return (.gap, "no capture-reapply driver for \(name)")
        }
    }

    // MARK: - Lane-B delivery affordances (reversible; gated behind PUMPX2_DELIVER_SALINE)
    //
    // ⚠️⚠️  UNVALIDATED — NEEDS A PHYSICAL SALINE PUMP.  ⚠️⚠️  Every driver below is reached ONLY when the pure
    // plan opened the SINGLE saline gate (cartridge + PUMP_SALINE_ATTESTED + PUMPX2_DELIVER_SALINE). Each
    // drives its command reversibly (deliver-oracle / reversible pair / capture→set→restore / throwaway
    // create→delete) and ALWAYS attempts its restore, even on a mid-sequence failure. The Mobi-only ones
    // cannot run until a Mobi bench; they are wired best-effort with LOUD restore-failure warnings.

    /// Dispatch a delivery-class command to its reversible affordance. A restore-partner (StopTempRate /
    /// ResumePumping / DeleteIDP) is covered when its primary's pair runs — its result is read from
    /// `deliveryPairResults` (driving the primary first if needed).
    private func coverageDriveDelivery(_ name: String, cfg: BenchSessionConfig) async -> (BenchCellState, String) {
        guard let aff = BenchAffordanceCatalog.affordance(for: name) else {
            return (.gap, "no delivery affordance classified")
        }
        if aff.role == .restorePartner {
            if let r = deliveryPairResults[name] { return r }
            if let primary = aff.partner { _ = await coverageDriveDelivery(primary, cfg: cfg) }
            return deliveryPairResults[name] ?? (.gap, "restore-partner not exercised (primary \(aff.partner ?? "?") did not run)")
        }
        switch name {
        case "InitiateBolusRequest":            return (await coverageDeliverBolusOracle(), "history-log read-back oracle (delivered ≈ requested)")
        case "AdditionalBolusRequest":          return await driveAdditionalBolus()
        case "SuspendPumpingRequest":           return await driveSuspendResume()
        case "SetTempRateRequest":              return await driveTempRatePair()
        case "EnterChangeCartridgeModeRequest": return await driveCartridgeModePair()
        case "EnterFillTubingModeRequest":      return await driveFillTubingPair()
        case "CreateIDPRequest":                return await driveCreateDeleteIdp()
        case "SetModesRequest":                 return await driveSetModes()
        case "SetActiveIDPRequest":             return await driveSetActiveIdp()
        case "FillCannulaRequest":              return await driveFillCannula()
        case "RenameIDPRequest":                return await driveRenameIdp()
        default:                                return (.gap, aff.note)
        }
    }

    /// AdditionalBolus (extended-bolus continuation): permission → establish a minimal 0.40 u EXTENDED
    /// saline bolus → extend it via AdditionalBolus(bolusID) → confirm the pump knows the bolus → CANCEL to
    /// clean up (so no 30-min extended dose is left running). Oracle = CurrentBolusStatus / LastBolusStatusV2.
    private func driveAdditionalBolus() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        guard let permFrame = await probeWrite(BolusPermissionRequest(), "add-bolus permission"),
              let perm = try? ResponseParser.parse(frame: permFrame, characteristic: .control).message as? BolusPermissionResponse,
              perm.granted else { return (.fail, "permission not granted") }
        do {
            // Smallest valid extended bolus: total 0 + 0.40 u extended over 30 min, FOOD2 + EXTENDED.
            let mask = InitiateBolusRequest.bitFood2 | InitiateBolusRequest.bitExtended
            let req = try InitiateBolusRequest(validating: 0, bolusID: perm.bolusId, bolusTypeBitmask: mask,
                                               extendedVolume: 400, extendedSeconds: 1800)
            _ = try await client.withWritePolicy(.allowDelivery) {
                try await self.client.sendAwaitingResponse(req, authenticationKey: self.authKey,
                    pumpTimeSinceReset: self.signingTimestamp, allowInsulinDelivery: true, deadline: 10, serialized: true)
            }
        } catch { return (.fail, "extended-bolus setup rejected: \(error)") }
        let extended = await probeWrite(AdditionalBolusRequest(bolusID: perm.bolusId), "AdditionalBolus") != nil
        // ALWAYS cancel the extended bolus so nothing keeps delivering.
        _ = await probeWrite(CancelBolusRequest(bolusId: perm.bolusId), "CancelBolus (cleanup extended)")
        guard extended else { return (.fail, "AdditionalBolus not accepted (extended-bolus context) — cancelled cleanup") }
        return (.pass, "extended saline bolus extended via AdditionalBolus, then cancelled to restore")
    }

    /// Suspend↔Resume: read basal → suspend → confirm basal stopped → ALWAYS resume to restore.
    private func driveSuspendResume() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let suspended = await probeWrite(SuspendPumpingRequest(), "SuspendPumping") != nil
        let mid = suspended ? await probeRead(CurrentBasalStatusRequest(), as: CurrentBasalStatusResponse.self, "basal (suspended)") : nil
        let resumed = await probeWrite(ResumePumpingRequest(), "ResumePumping (restore)") != nil
        deliveryPairResults["ResumePumpingRequest"] = resumed
            ? (.pass, "resumed pumping (restore half of Suspend↔Resume)")
            : (.fail, "resume NACKed — ⚠️ VERIFY pumping is resumed on the pump")
        guard suspended else { return (.fail, "SuspendPumping not accepted") }
        let midNote = mid.map { "basal-while-suspended=\($0.currentBasalRate) mU/hr" } ?? "basal read-back inconclusive"
        return (.pass, "suspend accepted (\(midNote)); resumed to restore\(resumed ? "" : " — ⚠️ resume FAILED")")
    }

    /// SetTempRate↔StopTempRate: set 80%/30m → confirm TempRateStatus.active → ALWAYS stop to restore.
    private func driveTempRatePair() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let ciq = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "CIQ (pre temp-rate)")
        let setOK = await probeWrite(SetTempRateRequest(minutes: 30, percent: 80), "SetTempRate 80%/30m") != nil
        let mid = setOK ? await probeRead(TempRateStatusRequest(), as: TempRateStatusResponse.self, "temp-rate (mid)") : nil
        let stopped = await probeWrite(StopTempRateRequest(), "StopTempRate (restore)") != nil
        deliveryPairResults["StopTempRateRequest"] = stopped
            ? (.pass, "stopped temp rate (restore half of SetTempRate↔StopTempRate)")
            : (.fail, "StopTempRate NACKed — ⚠️ VERIFY no temp rate is left active")
        guard setOK else {
            let hint = (ciq?.closedLoopEnabled == true) ? " — Control-IQ is ON; temp rate needs it OFF (use the `probe` subcommand's CIQ-off path)" : ""
            return (.fail, "SetTempRate rejected\(hint)")
        }
        let activeNote = (mid?.active == true) ? "TempRateStatus.active confirmed" : "active not confirmed via read-back"
        return (.pass, "temp rate 80%/30m accepted (\(activeNote)); stopped to restore\(stopped ? "" : " — ⚠️ stop FAILED")")
    }

    /// EnterChangeCartridgeMode↔Exit: enter → confirm LoadStatus → ALWAYS exit to restore.
    private func driveCartridgeModePair() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let entered = await probeWrite(EnterChangeCartridgeModeRequest(), "EnterChangeCartridgeMode") != nil
        let mid = entered ? await probeRead(LoadStatusRequest(), as: LoadStatusResponse.self, "loadStatus (in mode)") : nil
        let exited = await probeWrite(ExitChangeCartridgeModeRequest(), "ExitChangeCartridgeMode (restore)") != nil
        deliveryPairResults["ExitChangeCartridgeModeRequest"] = exited
            ? (.pass, "exited cartridge-change mode (restore half of the pair)")
            : (.fail, "ExitChangeCartridgeMode NACKed — ⚠️ VERIFY the pump left cartridge-change mode")
        guard entered else { return (.fail, "EnterChangeCartridgeMode not accepted") }
        let midNote = mid.map { "loadState=\($0.loadStateId)" } ?? "LoadStatus inconclusive"
        return (.pass, "entered cartridge-change mode (\(midNote)); exited to restore\(exited ? "" : " — ⚠️ exit FAILED")")
    }

    /// EnterFillTubingMode↔Exit: enter (primes tubing on saline) → confirm LoadStatus → suspend the active
    /// prime (PrimeTubingSuspend context step) → ALWAYS exit to restore.
    private func driveFillTubingPair() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let entered = await probeWrite(EnterFillTubingModeRequest(), "EnterFillTubingMode") != nil
        let mid = entered ? await probeRead(LoadStatusRequest(), as: LoadStatusResponse.self, "loadStatus (fill-tubing)") : nil
        // Context step: PrimeTubingSuspend is only meaningful WHILE a fill-tubing prime is active, so fire it
        // here (never standalone). Exiting fill-tubing mode below restores state regardless of the outcome.
        var primeSuspendNote = ""
        if entered {
            let suspended = await probeWrite(PrimeTubingSuspendRequest(), "PrimeTubingSuspend (context: suspend the active prime)") != nil
            deliveryPairResults["PrimeTubingSuspendRequest"] = suspended
                ? (.pass, "suspended the active fill-tubing prime (context step inside EnterFillTubingMode↔Exit)")
                : (.fail, "PrimeTubingSuspend NACKed inside the fill-tubing prime — exit still restores")
            primeSuspendNote = suspended ? "; prime suspended" : "; prime-suspend NACKed"
        }
        let exited = await probeWrite(ExitFillTubingModeRequest(), "ExitFillTubingMode (restore)") != nil
        deliveryPairResults["ExitFillTubingModeRequest"] = exited
            ? (.pass, "exited fill-tubing mode (restore half of the pair)")
            : (.fail, "ExitFillTubingMode NACKed — ⚠️ VERIFY the pump left fill-tubing mode")
        guard entered else { return (.fail, "EnterFillTubingMode not accepted") }
        let midNote = mid.map { "primeStatus=\($0.primeStatusId)" } ?? "LoadStatus inconclusive"
        return (.pass, "entered fill-tubing mode (\(midNote))\(primeSuspendNote); exited to restore\(exited ? "" : " — ⚠️ exit FAILED")")
    }

    /// CreateIDP→DeleteIDP: capture profile count → create a throwaway IDP → confirm it appeared → DELETE it.
    /// LOUD warning if the delete fails (a throwaway profile would be left on the pump).
    private func driveCreateDeleteIdp() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let before = await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profiles (pre)")
        // A conservative throwaway profile (values echo a sane basal profile; deleted immediately).
        let create = CreateIDPRequest(name: "BENCH_TMP", firstSegmentProfileCarbRatio: 10000,
                                      firstSegmentProfileStartTime: 0, firstSegmentProfileBasalRate: 500,
                                      firstSegmentProfileTargetBG: 110, firstSegmentProfileISF: 50,
                                      profileInsulinDuration: 300, timeSegmentBitmask: 1, bolusSettingsBitmask: 0,
                                      carbEntry: 1, idpSourceId: 0)
        guard let f = await probeWrite(create, "CreateIDP (throwaway)"),
              let resp = try? ResponseParser.parse(frame: f, characteristic: .control).message as? CreateIDPResponse else {
            return (.fail, "CreateIDP not accepted")
        }
        let newId = resp.newIdpId
        let mid = await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profiles (post-create)")
        // Delete the throwaway by its new id (slot index = old count).
        let profileIndex = before?.numberOfProfiles ?? 0
        let deleted = await probeWrite(DeleteIDPRequest(idpId: newId, profileIndex: profileIndex), "DeleteIDP (throwaway restore)") != nil
        deliveryPairResults["DeleteIDPRequest"] = deleted
            ? (.pass, "deleted the throwaway IDP id \(newId) (restore half of CreateIDP→DeleteIDP)")
            : (.fail, "DeleteIDP NACKed — ⚠️ VERIFY the throwaway IDP id \(newId) is removed on the pump")
        let grew = (before != nil && mid != nil) ? "count \(before!.numberOfProfiles)→\(mid!.numberOfProfiles)" : "count read inconclusive"
        return (.pass, "created throwaway IDP id \(newId) (\(grew)); deleted to restore\(deleted ? "" : " — ⚠️ delete FAILED")")
    }

    /// SetModes: capture the current user mode → set sleepModeOn → confirm changed → RESTORE sleepModeOff.
    /// Needs Control-IQ ON (noted if OFF). Best-effort — the mode read-back semantics are firmware-specific.
    private func driveSetModes() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        let pre = await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "modes (pre)")
        let onOK = await probeWrite(SetModesRequest(mode: .sleepModeOn), "SetModes sleepOn") != nil
        let mid = onOK ? await probeRead(ControlIQInfoV1Request(), as: ControlIQInfoV1Response.self, "modes (mid)") : nil
        // ALWAYS restore sleep OFF (the assumed default; a bench pump is not on a schedule).
        let offOK = await probeWrite(SetModesRequest(mode: .sleepModeOff), "SetModes sleepOff (restore)") != nil
        guard onOK else {
            let hint = (pre?.closedLoopEnabled == false) ? " — Control-IQ is OFF; SetModes needs it ON" : ""
            return (.fail, "SetModes(sleepOn) rejected\(hint)")
        }
        let changed = (pre != nil && mid != nil && pre!.currentUserModeType != mid!.currentUserModeType) ? "mode changed \(pre!.currentUserModeType)→\(mid!.currentUserModeType)" : "mode-change read inconclusive"
        return (.pass, "SetModes(sleepOn) accepted (\(changed)); restored sleepOff\(offOK ? "" : " — ⚠️ restore FAILED, VERIFY sleep mode on the pump")")
    }

    /// SetActiveIDP: capture the active profile → switch to another present profile → confirm → RESTORE.
    /// Needs ≥2 profiles; records a clear note if only one exists.
    private func driveSetActiveIdp() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        guard let pre = await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profiles (pre)") else { return (.fail, "profile read failed") }
        let present = pre.presentIdpIds
        let original = pre.activeIdpId
        guard present.count >= 2, let other = present.first(where: { $0 != original }) else {
            return (.fail, "needs ≥2 IDPs to switch the active profile (present: \(present.count))")
        }
        let switchOK = await probeWrite(SetActiveIDPRequest(idpId: other), "SetActiveIDP → \(other)") != nil
        let mid = switchOK ? await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profiles (mid)") : nil
        // ALWAYS restore the original active profile.
        let restoreOK = await probeWrite(SetActiveIDPRequest(idpId: original), "SetActiveIDP → \(original) (restore)") != nil
        guard switchOK else { return (.fail, "SetActiveIDP not accepted") }
        let confirmed = (mid?.activeIdpId == other) ? "active switched to \(other)" : "switch not confirmed via read-back"
        return (.pass, "SetActiveIDP accepted (\(confirmed)); restored active IDP \(original)\(restoreOK ? "" : " — ⚠️ restore FAILED")")
    }

    /// FillCannula: dispense a small saline cannula prime, confirm accepted + LoadStatus. One-way (records,
    /// no reverse — a prime cannot be un-dispensed; safe on saline).
    private func driveFillCannula() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        guard await probeWrite(FillCannulaRequest(primeSize: 30), "FillCannula (30 mU prime)") != nil else { return (.fail, "FillCannula not accepted") }
        let mid = await probeRead(LoadStatusRequest(), as: LoadStatusResponse.self, "loadStatus (post-fill)")
        let midNote = mid.map { "primeStatus=\($0.primeStatusId)" } ?? "LoadStatus inconclusive"
        return (.pass, "cannula prime (30 mU saline) accepted (\(midNote)); one-way — nothing to restore")
    }

    /// RenameIDP: capture the active profile's name → rename to a temp → confirm → RESTORE the prior name.
    private func driveRenameIdp() async -> (BenchCellState, String) {
        guard await awaitPaired() else { return (.fail, "not paired") }
        guard let prof = await probeRead(ProfileStatusRequest(), as: ProfileStatusResponse.self, "profiles (pre)") else { return (.fail, "profile read failed") }
        let idpId = prof.activeIdpId
        guard idpId >= 0 else { return (.fail, "no active IDP to rename") }
        guard let settings = await probeRead(IDPSettingsRequest(idpId: idpId), as: IDPSettingsResponse.self, "idp settings (pre)") else { return (.fail, "IDP settings read failed") }
        let originalName = settings.name
        let renameOK = await probeWrite(RenameIDPRequest(idpId: idpId, profileIndex: 0, profileName: "BENCH_TMP"), "RenameIDP → BENCH_TMP") != nil
        let mid = renameOK ? await probeRead(IDPSettingsRequest(idpId: idpId), as: IDPSettingsResponse.self, "idp settings (mid)") : nil
        // ALWAYS restore the original name.
        let restoreOK = await probeWrite(RenameIDPRequest(idpId: idpId, profileIndex: 0, profileName: originalName), "RenameIDP → \"\(originalName)\" (restore)") != nil
        guard renameOK else { return (.fail, "RenameIDP not accepted") }
        let confirmed = (mid?.name == "BENCH_TMP") ? "rename confirmed via read-back" : "rename not confirmed via read-back"
        return (.pass, "RenameIDP accepted (\(confirmed)); restored name \"\(originalName)\"\(restoreOK ? "" : " — ⚠️ restore FAILED, VERIFY the IDP name on the pump")")
    }

    /// Lane B delivery oracle: deliver a small SALINE bolus (0.10 u) and PASS only when the pump's OWN
    /// history-log read-back (`LastBolusStatusV2`) reports the requested amount. Reached ONLY when the pure
    /// plan opened the saline gate. UNVALIDATED — bench hardware only.
    private func coverageDeliverBolusOracle() async -> BenchCellState {
        let requestedMU: UInt32 = 100
        let requestedUnits = Double(requestedMU) / 1000.0
        guard await awaitPaired() else { return .fail }
        guard let permFrame = await probeWrite(BolusPermissionRequest(), "coverage-deliver BolusPermission"),
              let perm = try? ResponseParser.parse(frame: permFrame, characteristic: .control).message as? BolusPermissionResponse,
              perm.granted else { return .fail }
        do {
            let mask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)
            // BENCH-CONFIRM (dose path, opcode-158): log the EMITTED type mask so the operator can compare it
            // against the pump's own BolusDeliveryHistoryLog bolus-type. Pre-#120 labels FOOD1(1)/CORRECTION(2)/
            // EXTENDED(4)/FOOD2(8); this units-only bolus emits FOOD2. See docs/BENCH-COVERAGE.md → BENCH-CONFIRM.
            print("  🔬 BENCH-CONFIRM (opcode-158 type bits): units-only bolus emits bolusTypeBitmask=0x"
                + "\(String(mask, radix: 16)) (FOOD2) — compare vs the pump's recorded BolusDeliveryHistoryLog type")
            let req = try InitiateBolusRequest(validating: requestedMU, bolusID: perm.bolusId, bolusTypeBitmask: mask)
            let frame = try await client.withWritePolicy(.allowDelivery) {
                try await self.client.sendAwaitingResponse(
                    req, authenticationKey: self.authKey, pumpTimeSinceReset: self.signingTimestamp,
                    allowInsulinDelivery: true, deadline: 10, serialized: true)
            }
            guard let resp = try? ResponseParser.parse(frame: frame, characteristic: .control).message as? InitiateBolusResponse,
                  resp.accepted else { return .fail }
        } catch { return .fail }
        // Oracle: poll the pump's own last-bolus record until it reflects the requested units.
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let f = try? await client.withWritePolicy(.readOnly, { try await self.client.sendAwaitingResponse(LastBolusStatusV2Request(), deadline: 10) }),
               let last = try? ResponseParser.parse(frame: f, characteristic: .currentStatus).message as? LastBolusStatusV2Response,
               abs(last.deliveredUnits - requestedUnits) <= 0.05 {
                print("  ✅ delivery oracle: pump recorded \(last.deliveredUnits) u ≈ requested \(requestedUnits) u")
                return .pass
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
        print("  ❌ delivery oracle: pump history did not reflect the requested \(requestedUnits) u within 30s")
        return .fail
    }

    /// Affordance (a): read `CurrentActiveIdpValues` and log the RAW cargo hex + the byte-4 vs byte-5
    /// targetBg decode (BENCH-SESSION-PLAN Obj 4 / D-07 — confirm byte-4 carries the pump-set target on
    /// THIS pump family + firmware before trusting the typed decode).
    private func logCurrentTargetBgRaw() async {
        guard let r = await probeRead(CurrentActiveIdpValuesRequest(), as: CurrentActiveIdpValuesResponse.self, "activeIDP raw") else {
            print("  ⏭️  currentTargetBg raw: activeIDP read rejected on this pump"); return
        }
        let raw = r.cargo
        let b4 = raw.count >= 6 ? (Int(raw[4]) | (Int(raw[5]) << 8)) : -1
        let b5 = raw.count >= 7 ? (Int(raw[5]) | (Int(raw[6]) << 8)) : -1
        print("  🔬 currentTargetBg RAW cargo=\(Hex.encode(raw))")
        print("     decoded targetBg: byte4(LE)=\(b4)  byte5(LE)=\(b5)  typed=\(r.currentTargetBg)  "
            + "(D-07: byte-4 must equal the pump-set target; capture per pump-family+firmware)")
    }

    /// Affordance (c): OPT-IN no-cartridge bolus-rejection probe. Drives a 0.10 u bolus through BOTH
    /// software walls with NO cartridge loaded and RECORDS the pump's rejection — it can never dispense
    /// (no cartridge). Recorded under a distinct synthetic command so it does not mark the real delivery
    /// oracle covered.
    private func runNoCartridgeBolusProbe(cfg: BenchSessionConfig, ts: String) async -> [BenchCoverageCell] {
        print("\n--- No-cartridge bolus-rejection probe (PUMPX2_NO_CARTRIDGE_BOLUS_PROBE) ---")
        print("  Driving a 0.10 u bolus through BOTH walls with NO cartridge; recording the REJECTION.")
        var passed = false, note = ""
        if let f = await probeWrite(BolusPermissionRequest(), "no-cart BolusPermission"),
           let perm = try? ResponseParser.parse(frame: f, characteristic: .control).message as? BolusPermissionResponse {
            if !perm.granted {
                passed = true; note = "pump refused permission without a cartridge (expected)"
            } else {
                do {
                    let mask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)
                    let req = try InitiateBolusRequest(validating: 100, bolusID: perm.bolusId, bolusTypeBitmask: mask)
                    let frame = try await client.withWritePolicy(.allowDelivery) {
                        try await self.client.sendAwaitingResponse(
                            req, authenticationKey: self.authKey, pumpTimeSinceReset: self.signingTimestamp,
                            allowInsulinDelivery: true, deadline: 10, serialized: true)
                    }
                    if let resp = try? ResponseParser.parse(frame: frame, characteristic: .control).message as? InitiateBolusResponse {
                        passed = !resp.accepted
                        note = resp.accepted
                            ? "⚠️ pump ACCEPTED a no-cartridge initiate — verify NO delivery recorded on the pump"
                            : "pump rejected the no-cartridge initiate (expected; status \(resp.status))"
                    }
                } catch { passed = true; note = "no-cartridge initiate threw/failed (expected rejection)" }
            }
        } else { note = "permission exchange produced no response" }
        print("  → no-cartridge probe: \(passed ? "PASS (rejected as expected)" : "REVIEW") — \(note)")
        let cell = BenchCoverageCell(
            model: cfg.modelName, firmware: cfg.firmwareLabel, cartridge: false, cgm: cfg.cgmPresent,
            command: "InitiateBolusRequest·no-cartridge-reject", lane: .delivery,
            state: passed ? .pass : .fail, note: note, session: cfg.label, timestamp: ts)
        return [cell]
    }

    /// Affordance (d): OPT-IN observational probe of CGM-family READS with NO sensor present
    /// (PUMPX2_PROBE_DEFERRED_READS). A read never mutates pump state, so it is always bench-safe; sending
    /// each CGM read without a sensor reveals HOW the pump answers (a typed no-sensor status vs an op-77
    /// reject) — real app-design intel for the no-CGM path. READS ONLY — never a CGM control/session write.
    /// Recorded under a distinct `·no-cgm-probe` synthetic command so it never marks the real (sensor-verified)
    /// CGM coverage covered; the console line is the primary intel.
    private func runNoCgmReadProbe(cfg: BenchSessionConfig, ts: String) async -> [BenchCoverageCell] {
        print("\n--- No-CGM read probe (PUMPX2_PROBE_DEFERRED_READS): how the pump answers CGM reads w/ no sensor ---")
        var cells: [BenchCoverageCell] = []
        let cgmReads = BenchCommandCatalog.all
            .filter { $0.lane == .read && $0.requiresCGM }
            .sorted { $0.name < $1.name }
        for cmd in cgmReads {
            // A future/unparseable API floor is not a "no-sensor" question — skip (sending a known-unparseable
            // op yields no app-design signal, only churn).
            if let floor = cmd.minApi, cfg.apiVersion < floor {
                print("  ⏭️  \(cmd.name): needs API ≥ \(floor.major).\(floor.minor) — not a no-sensor question, skipped")
                continue
            }
            guard let inst = BenchCommandCatalog.makeReadInstance(cmd.name) else { continue }
            let (st, note) = await coverageRead(inst, cmd.name)
            let answered = (st == .pass)
            let obs = answered
                ? "no-CGM probe: pump ANSWERED (typed response parsed) — command works without a sensor (returns a no-sensor state)"
                : "no-CGM probe: \(note)"
            print("  [\(answered ? "answered" : "rejected")] \(cmd.name) — \(obs)")
            cells.append(BenchCoverageCell(
                model: cfg.modelName, firmware: cfg.firmwareLabel, cartridge: cfg.cartridgePresent, cgm: false,
                command: "\(cmd.name)·no-cgm-probe", lane: .read,
                state: answered ? .pass : .deferred, note: obs, session: cfg.label, timestamp: ts))
        }
        return cells
    }

    private func printCoverageRemaining(_ matrix: BenchCoverageMatrix) {
        let rem = matrix.remaining()
        print("\n--- Coverage remaining: \(rem.count) command(s) not yet PASS in any config ---")
        guard !rem.isEmpty else {
            print("  ✅ every applicable command has a PASS in at least one recorded config"); return
        }
        var byNote: [String: [String]] = [:]
        for r in rem { byNote[r.note, default: []].append("\(r.command) [\(r.model)/\(r.firmware) · \(r.best.rawValue)]") }
        for note in byNote.keys.sorted() {
            print("  • \(note)")
            for item in byNote[note]!.sorted() { print("      - \(item)") }
        }
    }

    func pumpClient(_ c: PumpBLEClient, didReceiveFrame frame: [UInt8], on ch: Characteristic) {
        if ch == .authorization {
            coordinator?.handle(frame: frame)
        } else if let parsed = try? ResponseParser.parse(frame: frame, characteristic: ch) {
            switch parsed.message {
            case let m as ApiVersionResponse:
                print("ℹ️ [hardware] pump firmware profile — API \(m.majorVersion).\(m.minorVersion) "
                    + "\(m.isMobi ? "(Mobi)" : "(t:slim X2 family)") · pairing=\(pairingScheme.rawValue)")
            case let m as PumpVersionResponse:
                print("ℹ️ [hardware] pump version — pumpSW=\(m.pumpRev) armSW=\(m.armSwVer) model=\(m.modelNum)")
            case let m as PumpFeaturesV1Response:
                print("ℹ️ [hardware] capability bitmask = 0x\(String(m.featureBitmask, radix: 16)) "
                    + "· controlIQSupported(bit1024)=\(m.controlIQSupported)")
            case let m as ErrorResponse:
                // P1a (Addendum G): during the op-77 NACK sub-probe, capture the pump's ECHOED txId so the
                // sub-probe can assert it equals the failing request's sent txId. `parsed.txId` == frame[1].
                if nackProbeActive { nackProbeEchoedTxId = parsed.txId }
                // Attribute the error to the read that triggered it via the echoed txId (this legacy
                // pump zeroes requestCodeId, so the cargo alone can't name the read).
                let who = pollTxMap[parsed.txId] ?? "unknown"
                // VA-04: also dump the RAW op-77 cargo bytes so `reqCodeId=0 errorCode=0` can be confirmed as
                // genuine legacy-firmware behavior vs a decode-offset bug — the decoded fields alone can't tell.
                let rawHex = m.cargo.map { String(format: "%02x", $0) }.joined()
                print("⚠️ [error-response] pump REJECTED \(who) read (txId=\(parsed.txId)) "
                    + "— reqCodeId=\(m.requestCodeId) errorCode=\(m.errorCodeId) (op-77) rawCargo=\(rawHex.isEmpty ? "∅" : rawHex)")
            case let m as ControlIQIOBResponse:
                // iobUnits uses swan6hrIOB (matches the pump display, verified on hardware).
                print("[status] IOB = \(m.iobUnits) u")
                if isCarbMode { iobMilliunits = m.swan6hrIOB; maybeComputeCarbBolus() }
            case let m as InsulinStatusResponse: print("[status] insulin remaining = \(m.currentInsulinAmount) u")
            case let m as CurrentBatteryV2Response: print("[status] battery = \(m.batteryPercent)%")
            case let m as CurrentEgvGuiDataV2Response:
                print("[status] glucose = \(m.hasValidReading ? "\(m.cgmReading)" : "--") mg/dL \(m.trendArrow) (status=\(m.egvStatusId) trendRate=\(m.trendRate))")
            case let m as CurrentBasalStatusResponse:
                print("[status] basal = \(m.currentBasalUnitsPerHour) u/hr")
            case let m as LastBolusStatusV2Response:
                print("[status] last bolus = \(m.deliveredUnits) u (id \(m.bolusId))")
            case let m as BolusCalcDataSnapshotResponse:
                print("[status] calc — carbRatio raw=\(m.carbRatio) (~\(m.carbRatioGramsPerUnit) g/u) "
                    + "isf/correctionFactor=\(m.isf) mg/dL/u targetBG=\(m.targetBg) mg/dL "
                    + "carbEntryEnabled=\(m.carbEntryEnabled) maxBolus=\(Double(m.maxBolusAmount)/1000.0)u")
                if isCarbMode { calc = m; maybeComputeCarbBolus() }
            case let m as TimeSinceResetResponse:
                signingTimestamp = m.signingTimestamp
                print("[time] currentTime=\(m.currentTime) pumpTimeSinceReset=\(m.pumpTimeSinceReset) → signing with \(signingTimestamp)")
                if isCarbMode {
                    haveTime = true; maybeComputeCarbBolus()
                } else if (mode == .permissionTest || isBolusMode) && !permissionSent {
                    sendSignedPermission()
                }
            case let m as BolusPermissionResponse:
                print("[permission] status=\(m.status) granted=\(m.granted) bolusId=\(m.bolusId) nackReason=\(m.nackReasonId)")
                guard m.granted else { print("[permission] ❌ not granted — check signature/timestamp or pump state"); break }
                if case let .deliverBolus(mu) = mode {
                    print("[permission] ✅ granted — proceeding to SALINE delivery")
                    initiateBolus(milliunits: mu, bolusId: m.bolusId)
                } else if isCarbMode {
                    print("[permission] ✅ granted — proceeding to carb-bolus SALINE delivery")
                    initiateCarbBolus(bolusId: m.bolusId)
                } else {
                    print("[permission] ✅ pump ACCEPTED the signature and granted permission (no insulin delivered)")
                    releasePermission(bolusId: m.bolusId)
                }
            case let m as InitiateBolusResponse:
                print("[bolus] initiate response — status=\(m.status) accepted=\(m.accepted) bolusId=\(m.bolusId) statusType=\(m.statusTypeId)")
                if m.accepted {
                    print("[bolus] ✅ pump accepted the bolus — delivering SALINE. Weigh the container; Ctrl-C cancels.")
                    startBolusStatusPolling()
                } else {
                    print("[bolus] ❌ initiate not accepted")
                }
            default: print("[status] opcode \(parsed.opCode)")
            }
        } else {
            print("[frame] \(ch.name) hex=\(Hex.encode(frame))")
        }
    }

    func pumpClient(_ c: PumpBLEClient, didError error: Error) { print("[error] \(error)") }
}

switch args.first {
case nil, "":
    serializationSelfCheck()
case "coverage-selftest":
    // OFFLINE (no Bluetooth): plan the representative bench sessions and write the coverage artifacts.
    // Verifies the classification→persistence→render pipeline and seeds bench-coverage/ with the honest
    // pre-bench PLAN (nothing PASS without a real pump). Safe to run anywhere.
    BenchCoverageSelfTest.run()
case "scan":
    let m = Monitor(mode: .scan); _ = m
    print("Scanning for pumps — Ctrl-C to stop.")
    RunLoop.main.run()
case "monitor":
    let m = Monitor(mode: .monitor); _ = m
    print("READ-ONLY monitor — connect, JPAKE pair, poll status. No writes that change pump state. Ctrl-C to stop.")
    RunLoop.main.run()
case "probe":
    // Comprehensive no-cartridge/no-CGM validation: fuller read sweep + txId-match (B7) + signed-write
    // acceptance (BolusPermission, NO delivery) + the "Mobi-only" write probes (time-set / temp-basal /
    // SetModes — state-mutating, no dispense). Both delivery walls stay armed; PUMPX2_DELIVER_SALINE is
    // never set. Intended for the SPARE bench pump only.
    let m = Monitor(mode: .probe); _ = m
    print("PROBE — reads + signed writes (NO insulin delivery). Pairs, runs the sequence, then idles.")
    print("Bench/spare pump only. Ctrl-C to stop.")
    RunLoop.main.run()
case "coverage":
    // Resumable, comprehensive command-coverage sweep. Pairs, detects this session's config
    // {model, firmware, cartridge, CGM} (from the pump's ApiVersion + PUMP_CARTRIDGE_LOADED /
    // PUMP_CGM_PRESENT / PUMP_SALINE_ATTESTED / PUMPX2_DELIVER_SALINE env axes), enumerates every
    // harness-drivable command, exercises the ones this config can (reads + curated signed writes;
    // delivery ONLY behind the saline gate, verified by the pump's own history log), and accumulates a
    // PERSISTENT matrix under bench-coverage/. Prints what remains and which config would cover it.
    // Both delivery walls stay armed throughout. Bench/spare pump only.
    let m = Monitor(mode: .coverage); _ = m
    print("COVERAGE — resumable command-coverage sweep. Pairs, exercises this session's coverable")
    print("commands, accumulates bench-coverage/COVERAGE-MATRIX.{json,md}, prints what's left. Ctrl-C to stop.")
    RunLoop.main.run()
case "permission-test":
    // Signed-write validation that delivers NO insulin: pair → sign a BolusPermissionRequest
    // → release. Delivery (InitiateBolus) is still hard-blocked (writePolicy .allowNonDelivery).
    let m = Monitor(mode: .permissionTest); _ = m
    print("SIGNATURE TEST — pair, then send a SIGNED bolus-permission (NO insulin delivered) to")
    print("prove the pump accepts our HMAC. Delivery is hard-blocked. Ctrl-C to stop.")
    RunLoop.main.run()
case "bolus":
    // PHASE B — ACTUALLY DELIVERS. Bench saline only. Guarded so it can't run by accident.
    guard args.count >= 2, let mu = UInt32(args[1]) else {
        print("usage: bolus <milliunits>   e.g. 'bolus 100' = 0.10 u"); exit(2)
    }
    guard ProcessInfo.processInfo.environment["PUMPX2_DELIVER_SALINE"] == "1" else {
        print("REFUSED. This mode delivers a real bolus. Set PUMPX2_DELIVER_SALINE=1 to confirm")
        print("the pump has a SALINE cartridge dispensing into a container on a scale — never on a body.")
        exit(2)
    }
    guard mu >= 50 && mu <= 2000 else {
        print("REFUSED. Bench limit is 50–2000 milliunits (0.05–2.0 u). Got \(mu)."); exit(2)
    }
    let monitor = Monitor(mode: .deliverBolus(milliunits: mu)); _ = monitor
    // Ctrl-C cancels the in-progress bolus, then exits shortly after.
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        MainActor.assumeIsolated { monitor.cancelBolus() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }
    sigint.resume()
    print("⚠️  SALINE BOLUS \(Double(mu)/1000.0) u — bench only. Pump must dispense saline into a")
    print("container on a scale. Weigh before/after. Ctrl-C cancels mid-delivery.")
    RunLoop.main.run()
case "carb-bolus":
    // Carbs → units using the pump's carb ratio / ISF / target + IOB, then deliver. SALINE ONLY.
    guard args.count >= 2, let carbs = Double(args[1]) else {
        print("usage: carb-bolus <grams> [bg]   e.g. 'carb-bolus 30' or 'carb-bolus 30 160'"); exit(2)
    }
    let bg = args.count >= 3 ? Int(args[2]) : nil
    guard ProcessInfo.processInfo.environment["PUMPX2_DELIVER_SALINE"] == "1" else {
        print("REFUSED. Delivers a real bolus. Set PUMPX2_DELIVER_SALINE=1 to confirm SALINE on a scale.")
        exit(2)
    }
    guard carbs > 0 && carbs <= 200 else { print("REFUSED. Enter 1–200 g."); exit(2) }
    let monitor = Monitor(mode: .carbBolus(carbs: carbs, bg: bg))
    monitor.carbGrams = carbs; monitor.carbBg = bg
    signal(SIGINT, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigint.setEventHandler {
        MainActor.assumeIsolated { monitor.cancelBolus() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { exit(0) }
    }
    sigint.resume()
    print("⚠️  CARB BOLUS \(carbs) g\(bg.map { ", BG \($0)" } ?? "") — computes units from the pump's")
    print("carb ratio/ISF/target, then delivers SALINE (bench, on a scale, capped 2.0 u). Ctrl-C cancels.")
    RunLoop.main.run()
default:
    print("unknown command: \(args[0])")
    print("commands: (none)=self-check, scan, monitor, probe, coverage, permission-test, bolus <milliunits>, carb-bolus <grams> [bg]")
    exit(2)
}
