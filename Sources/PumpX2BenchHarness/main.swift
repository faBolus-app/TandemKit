import Foundation
import CoreBluetooth
import PumpX2Messages
import PumpX2Auth
import PumpX2BLE

// PumpX2BenchHarness — the oracle/test CLI (Milestone 1e).
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
    print("PumpX2BenchHarness — serialization self-check (no BLE)")
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
        case scan, monitor, permissionTest, probe
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
    /// op-77 NACK txId-echo sub-probe state (Addendum G / P1a). While `nackProbeActive`, the ErrorResponse
    /// delegate case records the pump's ECHOED txId (frame[1], surfaced as `parsed.txId`) so the sub-probe
    /// can assert it equals the failing request's SENT txId. UNVALIDATED until bench hardware (see the probe
    /// header block above `probeTxIdMatch`).
    var nackProbeActive = false
    var nackProbeEchoedTxId: UInt8?
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
        if state == .idle { c.startScan() }
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
                print("⚠️ [error-response] pump REJECTED \(who) read (txId=\(parsed.txId)) "
                    + "— reqCodeId=\(m.requestCodeId) errorCode=\(m.errorCodeId) (op-77)")
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
    print("commands: (none)=self-check, scan, monitor, probe, permission-test, bolus <milliunits>, carb-bolus <grams> [bg]")
    exit(2)
}
