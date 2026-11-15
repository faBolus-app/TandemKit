import Foundation
import TandemBench
import TandemLink
import TandemMessages

/// The serial to check a write against: `PUMP_BENCH_SERIAL` if set, otherwise typed at the prompt.
@MainActor
func serialToCheck(_ s: BenchSession, _ prompt: String) async -> String {
    if let preset = BenchSafetyGate.presetSerial(environment: env) {
        say("  serial \(preset) from PUMP_BENCH_SERIAL; checked against the pump this link reached")
        return preset
    }
    return await s.inbox.prompt(prompt)
}

/// Lines typed during a run: a prompt waiting for one takes it; otherwise it's stamped as a NOTE.
@MainActor
final class LineInbox {
    private var waiting: CheckedContinuation<String, Never>?
    /// Standard input ended (a pipe, no terminal): a prompt gets an empty answer, which refuses.
    private var closed = false

    func close() {
        closed = true
        waiting?.resume(returning: "")
        waiting = nil
    }

    func deliver(_ line: String) {
        if let waiting {
            self.waiting = nil
            transcript.line("typed: \(line)")
            waiting.resume(returning: line)
        } else if !line.isEmpty {
            transcript.line("NOTE: \(line)")
        }
    }

    func prompt(_ text: String) async -> String {
        say("? \(text)")
        if closed {
            say("  standard input is closed, so nothing can be typed: refused")
            return ""
        }
        return await withCheckedContinuation { waiting = $0 }
    }
}

/// The bench bolus log, kept next to the support matrix.
enum BolusLogFile {
    static var url: URL {
        if let path = env["PUMP_BOLUS_LOG"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".tandemkit-bench/bench-boluses.json")
    }

    static func load() -> BenchBolusLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let log = try? decoder.decode(BenchBolusLog.self, from: data)
        else { return BenchBolusLog() }
        return log
    }

    /// Fails loudly: a bolus is never sent unless its entry was written first.
    static func save(_ log: BenchBolusLog) -> Bool {
        let log = log.merging(load())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(log).write(to: url, options: .atomic)
            return true
        } catch {
            say("couldn't write the bench bolus log at \(url.path): \(error)")
            return false
        }
    }
}

// MARK: UserInteraction

@MainActor
func userInteraction(_ s: BenchSession) async {
    guard await s.whenReady() else { return say("RESULT not sent: the link wasn't ready") }
    if let api = s.identity?.apiVersion, api < .v3 {
        return say("RESULT not sent: API \(s.apiText(api)) is below 3.0 (P1 rejected it with an op-77 and a drop)")
    }
    let typed = await serialToCheck(
        s, "type this pump's serial number (the `ready` line above) to send UserInteraction")
    if let why = BenchSafetyGate.writeRefusal(
        environment: env, typed: typed, pumpSerial: s.identity?.unit.map { Int($0.serialNumber) })
    {
        return say("RESULT not sent: \(why)")
    }
    let result = await s.request(
        UserInteractionRequest(), allowing: UserInteractionRequest().operationRisk, deadline: 60)
    if let r = s.reply(result, as: UserInteractionResponse.self) { say("  status \(r.status)") }
    say("  60 s of notices follow")
    await s.pause(60)
    say("RESULT UserInteraction: \(verdictText(result))")
}

// MARK: Pump clock

@MainActor
func setTime(_ s: BenchSession, plusFive: Bool) async {
    guard await s.whenReady() else { return say("RESULT not sent: the link wasn't ready") }
    if let bolus = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self),
        bolus.isActive
    {
        return say("RESULT not sent: a bolus is active on the pump")
    }
    say("  Control-IQ should be off for this run: a clock jump moves its schedule")
    let typed = await serialToCheck(s, "type this pump's serial number to set its clock")
    if let why = BenchSafetyGate.writeRefusal(
        environment: env, typed: typed, pumpSerial: s.identity?.unit.map { Int($0.serialNumber) })
    {
        return say("RESULT not sent: \(why)")
    }
    let before = s.reply(await s.request(HistoryLogStatusRequest()), as: HistoryLogStatusResponse.self)
    // Unverified: that ChangeTimeDate's seconds count from the same epoch, in the same zone, as
    // TimeSinceReset's currentTime. The no-op step checks it: its read-back has to match within seconds.
    say("  unverified: ChangeTimeDate is sent in TimeSinceReset's currentTime units; the no-op step checks that")
    guard let base = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self) else {
        return say("RESULT not sent: no clock read")
    }
    let baseAt = s.link.now
    var results: [String] = []
    // Every target is the one base reading moved on by the time since, so "back" restores the pump's
    // own time whatever the +5 min step did (answered, refused, or applied with a reply the link
    // couldn't trust).
    let steps: [(String, Int)] = plusFive ? [("same time", 0), ("+5 min", 300), ("back", 0)] : [("same time", 0)]
    var moved = false
    var restored = true
    for (label, offset) in steps {
        let target = BenchClock.target(pumpTime: base.currentTime, readAt: baseAt, now: s.link.now, offset: offset)
        let request = ChangeTimeDateRequest(tandemEpochTime: target)
        let result = await s.request(request, "ChangeTimeDate(\(label): \(target))", allowing: request.operationRisk)
        if let r = s.reply(result, as: ChangeTimeDateResponse.self) {
            say("  status \(r.status) accepted \(r.accepted)")
        }
        let after = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self)
        say("  pump time after: \(after.map { String($0.currentTime) } ?? "unread") (asked \(target))")
        results.append("\(label): \(verdictText(result))")
        let answered: Bool
        if case .reply = result { answered = true } else { answered = false }
        let sent: Bool
        if case .notSent = result { sent = false } else { sent = true }
        if offset != 0, sent {
            moved = true
            restored = false
        }
        if label == "back", answered { restored = true }
        // Stop after the no-op if it didn't answer; never stop between +5 min and back.
        if label == "same time", !answered { break }
    }
    if moved, !restored {
        say("  !!! the pump clock may still be 5 minutes fast: check it on the pump and set it back by hand")
    }
    if let before, let page = await newHistory(s, since: before.lastSequenceNum) {
        results.append("history records since: \(page)")
    }
    say("RESULT " + results.joined(separator: "; "))
}

// MARK: Remote clearing with a history check

@MainActor
func clearCheck(_ s: BenchSession, kind: NotificationKind, id: Int) async {
    func bitmap() async -> UInt64? {
        switch kind {
        case .alert: return s.reply(await s.request(AlertStatusRequest()), as: AlertStatusResponse.self)?.bitmap
        case .alarm: return s.reply(await s.request(AlarmStatusRequest()), as: AlarmStatusResponse.self)?.bitmap
        case .reminder:
            return s.reply(await s.request(ReminderStatusRequest()), as: ReminderStatusResponse.self)?.bitmap
        case .cgmAlert:
            return s.reply(await s.request(CGMAlertStatusRequest()), as: CGMAlertStatusResponse.self)?.bitmap
        }
    }
    func has(_ map: UInt64?) -> String { map.map { ($0 >> UInt64(id)) & 1 == 1 ? "set" : "clear" } ?? "unread" }
    let start = await bitmap()
    say("  before: bit \(id) \(has(start))")
    let before = s.reply(await s.request(HistoryLogStatusRequest()), as: HistoryLogStatusResponse.self)
    let result = await s.request(
        DismissNotificationRequest(kind: kind, notificationId: id), "DismissNotification(\(kind), \(id))",
        allowing: .benign, deadline: 30)
    if let r = s.reply(result, as: DismissNotificationResponse.self) { say("  dismiss status \(r.status)") }
    var seen: [String] = []
    var waited = 0.0
    for at in [2.0, 30, 120] {
        await s.pause(at - waited)
        waited = at
        let line = "\(Int(at)) s: bit \(id) \(has(await bitmap()))"
        say("  " + line)
        seen.append(line)
    }
    let history = before.map { $0.lastSequenceNum }
    let page = history != nil ? await newHistory(s, since: history!) : nil
    say(
        "RESULT dismiss \(verdictText(result)); before \(has(start)); " + seen.joined(separator: ", ")
            + "; history since: \(page ?? "unread")")
}

// MARK: Bolus

@MainActor
func bolus(_ s: BenchSession, kind: BenchBolusKind, _ o: BolusOptions) async {
    let carbs = o.carbs
    let bg = o.bg
    let noCartridge = o.noCartridge
    let overlap = o.overlap
    let units = String(format: "%.2f U", Double(o.milliunits) / 1000)
    guard await s.whenReady() else { return say("RESULT not sent: the link wasn't ready") }
    var log = BolusLogFile.load()
    if let why = log.refusal(now: Date()) { return say("RESULT not sent: \(why)") }
    if kind == .correction, bg <= 0 { return say("RESULT not sent: a correction needs --bg") }
    let reservoir = s.reply(await s.request(InsulinStatusRequest()), as: InsulinStatusResponse.self)
    say("  reservoir: \(reservoir.map { "\($0.currentInsulinAmount) U" } ?? "unread")")
    if let active = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self),
        active.isActive
    {
        return say("RESULT not sent: a bolus is active on the pump")
    }
    say(
        "  \(kind.rawValue): \(units), mask \(kind.mask), \(kind.source)"
            + (o.drop.map { "; the bench drops the link once the bolus is \($0.rawValue)" } ?? "")
            + (noCartridge ? "; no cartridge, so the pump should refuse it" : "; saline only, on no one"))
    let serial = s.identity?.unit.map { Int($0.serialNumber) }
    let typed = await serialToCheck(s, "type this pump's serial number to send one \(units) bench bolus")
    if let why = BenchSafetyGate.bolusRefusal(
        environment: env, typed: typed, pumpSerial: serial, noCartridge: noCartridge,
        reservoirUnits: reservoir?.currentInsulinAmount)
    {
        return say("RESULT not sent: \(why)")
    }
    let history = s.reply(await s.request(HistoryLogStatusRequest()), as: HistoryLogStatusResponse.self)
    let clock = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self)

    let permitResult = await s.request(
        BolusPermissionRequest(), allowing: BolusPermissionRequest().operationRisk, deadline: 60)
    guard let permit = s.reply(permitResult, as: BolusPermissionResponse.self), permit.granted else {
        let why = s.reply(permitResult, as: BolusPermissionResponse.self).map { "nack reason \($0.nackReasonId)" }
        return say("RESULT permission not granted: \(why ?? verdictText(permitResult))")
    }
    let id = permit.bolusId
    say("  permission granted, bolus id \(id)")

    func release(_ why: String) async {
        let r = await s.request(
            BolusPermissionReleaseRequest(bolusID: id), allowing: BolusPermissionReleaseRequest().operationRisk)
        say("  released the permission (\(why)): \(verdictText(r))")
    }

    // The entries as the app sends them (PumpSession's BolusCommands): the BG first, then the carbs, with
    // the bytes every pumpX2 capture has (a BG from source REMOTE, 1; the carb entry's third byte 1).
    let pumpTime = clock?.pumpTimeSinceReset ?? 0
    if kind == .correction || (kind == .carb && bg > 0) {
        // Never a calibration: that would shift the CGM.
        let entry = RemoteBgEntryRequest(
            bg: bg, useForCgmCalibration: false, entryTypeId: 0, sourceId: 1, pumpTimeSecondsSinceBoot: pumpTime,
            bolusId: id)
        let r = await s.request(entry, allowing: .benign)
        guard s.reply(r, as: RemoteBgEntryResponse.self)?.status == 0 else {
            await release("the BG entry wasn't accepted")
            return say("RESULT not sent: RemoteBgEntry \(verdictText(r))")
        }
    }
    if kind == .carb {
        let r = await s.request(
            RemoteCarbEntryRequest(carbs: carbs, unknown: 1, pumpTimeSecondsSinceBoot: pumpTime, bolusId: id),
            allowing: .benign)
        guard s.reply(r, as: RemoteCarbEntryResponse.self)?.status == 0 else {
            await release("the carb entry wasn't accepted")
            return say("RESULT not sent: RemoteCarbEntry \(verdictText(r))")
        }
    }

    let request: InitiateBolusRequest
    do {
        request = try kind.request(bolusId: id, carbs: carbs, bg: bg, milliunits: o.milliunits)
    } catch {
        await release("the request couldn't be built")
        return say("RESULT not sent: \(error)")
    }
    // The entry is written before the bolus goes out, so a crash or restart can't send another.
    log.entries.append(BenchBolusLog.Entry(date: Date(), serial: serial ?? 0, kind: kind.rawValue, bolusId: id))
    guard BolusLogFile.save(log) else {
        await release("the bolus log couldn't be written")
        return say("RESULT not sent: the bolus log couldn't be written")
    }
    say("  InitiateBolus cargo \(Hex.encode(request.cargo))")
    let sentAt = s.link.now
    let dropsAtSend = s.drops
    if o.drop == .sent { s.transport.dropAfterNextControlWrite = true }
    let initiate = await s.request(request, "InitiateBolus(\(kind.rawValue))", allowing: .delivery, deadline: 60)
    // Never left armed for a later write: a refusal before the write went out leaves it set.
    s.transport.dropAfterNextControlWrite = false
    say(String(format: "  reply after %.2f s", s.link.now - sentAt))
    var outcome: String?
    // A `sent` drop happens once the write is out: the reply then never comes, or came first.
    var dropping = false
    if o.drop == .sent {
        switch initiate {
        case .reply, .unknown: dropping = true
        case .pumpError, .notSent: break
        }
    }
    switch initiate {
    case .reply(let reply):
        let r = reply.message as? InitiateBolusResponse
        say("  status \(r?.status ?? -1) id \(r?.bolusId ?? -1) statusType \(r?.statusTypeId ?? -1)")
        if r?.status != 0 {
            outcome = "refused: status \(r?.status ?? -1)"
            await release("the pump refused the bolus")
        } else if o.drop == .accepted {
            s.transport.dropNow()
            dropping = true
        }
    case .pumpError(let e):
        outcome = "op-77 error \(e.errorCodeId)"
        await release("op-77")
    case .notSent(let why):
        outcome = "not sent: \(why)"
        await release("not sent")
    case .unknown(let why):
        say("  !!! outcome unknown (\(why)): check the pump's screen and history before anything else")
    }
    if outcome == nil, kind == .cancel {
        if o.onceDelivering { await waitUntilDelivering(s, id: id) }
        let drops = s.drops
        if overlap { await holdAStatusRead(s) }
        let c = await s.request(CancelBolusRequest(bolusId: id), allowing: CancelBolusRequest().operationRisk)
        if let r = s.reply(c, as: CancelBolusResponse.self) {
            say("  cancel status \(r.statusId) id \(r.bolusId) reason \(r.reasonId)")
        }
        if overlap { await reportOverlap(s, cancel: c, dropsBefore: drops) }
    }
    if dropping {
        // The link can still read as ready for a moment after the cancel; wait until it has seen the drop.
        let until = s.link.now + 10
        while s.drops == dropsAtSend, s.link.now < until { await s.pause(0.25) }
        if s.drops == dropsAtSend { say("  the link didn't drop within 10 s of the cancel") }
        let back = await s.whenReady(timeout: 180)
        say(back ? "  the link is back after the drop" : "  the link didn't come back within 180 s")
    }
    let followFor: Double = o.milliunits > BenchBolusKind.milliunits ? 300 : 120
    if outcome == nil, case .reply = initiate {
        outcome = await follow(s, id: id, limit: followFor)
    } else if outcome == nil, dropping, case .unknown = initiate {
        // Shown, never settled from: an unknown outcome is settled by hand, from the pump's history.
        let seen = await follow(s, id: id, limit: followFor)
        say("  after the drop the pump's status says: \(seen ?? "nothing that settles bolus \(id)")")
    }
    await lastBolus(s)
    if let history, let page = await newHistory(s, since: history.lastSequenceNum) { say("  history since: \(page)") }
    // The pump's own record settles it, as in the app: a bolus cancelled before it starts never shows as
    // active, and LastBolusStatus keeps naming the bolus before it, but its BolusCompleted record is there.
    if outcome == nil, let ended = completedInHistory(s, id: id) {
        say("  settled from the pump's history: \(ended)")
        outcome = ended
    }
    if let outcome {
        _ = log.settleLast(outcome)
        _ = BolusLogFile.save(log)
        say("RESULT bolus \(id) \(kind.rawValue): \(outcome)")
    } else {
        say("RESULT bolus \(id) \(kind.rawValue): outcome not settled; check the pump, then `bolus settle`")
    }
}

/// Waits, at most 40 s, for the pump to report bolus `id` delivering (status 1), so a cancel lands after
/// insulin has started to move. The cancel goes either way: a bolus never seen delivering is still stopped.
@MainActor
func waitUntilDelivering(_ s: BenchSession, id: Int) async {
    let start = s.link.now
    while s.link.now - start < 40 {
        if let status = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self) {
            if status.bolusId == id, status.statusId == 1 {
                return say(String(format: "  delivering after %.1f s; cancelling now", s.link.now - start))
            }
            // Right after the accept the pump may not list the bolus yet; after 3 s, not listing it means it ended.
            if !status.isActive, status.bolusId != id, s.link.now - start > 3 {
                return say("  the pump no longer reports bolus \(id); cancelling anyway")
            }
        }
        await s.pause(0.5)
    }
    say("  bolus \(id) wasn't reported delivering within 40 s; cancelling anyway")
}

/// The cancel-overlap check (bench step 15): a CurrentBolusStatus read whose write the transport holds
/// back. The link gives up on it after 2 s and sends the cancel; the held read goes out just before the
/// cancel's write, so the pump has it outstanding when the cancel arrives, as when Mobi writes a cancel.
@MainActor
func holdAStatusRead(_ s: BenchSession) async {
    s.transport.hold.hold(next: .currentStatus)
    _ = await s.request(CurrentBolusStatusRequest(), "CurrentBolusStatus (held back)", deadline: 2)
    if s.transport.hold.heldTxId == nil {
        s.transport.hold.clear()
        say("  OVERLAP not tried: the status read's write wasn't seen; the cancel goes on its own")
    }
}

/// What the pump did with the overlap: whether it answered the held read and the cancel, and kept the link.
@MainActor
func reportOverlap(_ s: BenchSession, cancel: RequestResult, dropsBefore: Int) async {
    guard let txId = s.transport.hold.heldTxId, let sent = s.transport.heldSentAt else { return }
    await s.pause(3)
    let dropped = s.drops != dropsBefore
    let replied = s.transport.heldAnswerOpCode == CurrentBolusStatusRequest.props.responseOpCode
    let answered = s.transport.heldAnsweredAt.map {
        String(format: "answered after %.2f s", $0.timeIntervalSince(sent))
            + (replied ? "" : ", but not with its reply (opcode \(s.transport.heldAnswerOpCode ?? 0))")
    }
    say("  OVERLAP held status read (txId \(txId)): \(answered ?? "not answered within 3 s")")
    say("  OVERLAP cancel: \(verdictText(cancel)); link \(dropped ? "DROPPED" : "held")")
    let passed = replied && s.reply(cancel, as: CancelBolusResponse.self) != nil && !dropped
    say(
        "  OVERLAP "
            + (passed
                ? "PASSED: both answered and the link held (step 2 can be built)"
                : "FAILED: the cancel waits for the request ahead on a t:slim (kept for Mobi)"))
    s.transport.hold.clear()
}

/// Follows the bolus every 2 s until the pump no longer reports it, up to `limit` seconds. The outcome is
/// what the pump's status said; nil when it was still active at the end.
@MainActor
func follow(_ s: BenchSession, id: Int, limit: Double = 120) async -> String? {
    var last = -1
    var seen = false
    let start = s.link.now
    let end = start + limit
    while s.link.now < end {
        guard let status = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self)
        else {
            await s.pause(2)
            continue
        }
        if status.statusId != last {
            last = status.statusId
            say(
                "  CurrentBolusStatus: status \(status.statusId) id \(status.bolusId) requested \(status.requestedVolume) mU"
            )
        }
        // Ended only once the pump has shown this bolus: active, or by its id. A status that names
        // neither (the bolus not started yet) isn't an end; after 20 s of that it stays unsettled.
        if status.isActive || status.bolusId == id { seen = true }
        if !status.isActive, seen {
            return "ended (status \(status.statusId)); see LastBolusStatus and history below"
        }
        if !seen, s.link.now - start > 20 {
            say("  the pump never showed bolus \(id) as active; its outcome stays unsettled")
            return nil
        }
        await s.pause(2)
    }
    return nil
}

/// Every history record after `since`, by type, asked top-anchored (pumpX2's capture) and at most 30.
@MainActor
func newHistory(_ s: BenchSession, since: UInt32) async -> String? {
    guard let status = s.reply(await s.request(HistoryLogStatusRequest()), as: HistoryLogStatusResponse.self) else {
        return nil
    }
    let last = status.lastSequenceNum
    guard last > since else { return "none" }
    let count = Int(min(last - since, 30))
    guard let page = await historyPage(s, start: last, count: count) else { return nil }
    var types: [String] = []
    for (_, frame) in s.historyFrames {
        for event in frame.events { types.append("\(type(of: event))") }
    }
    return "\(page.received.count) record(s): " + types.joined(separator: ", ")
}

/// How bolus `id` ended by its BolusCompleted record in the history just read, or nil if it isn't there.
@MainActor
func completedInHistory(_ s: BenchSession, id: Int) -> String? {
    BenchBolusLog.outcomeFromHistory(bolusId: id, events: s.historyFrames.flatMap { $0.frame.events })
}

func verdictText(_ r: RequestResult) -> String {
    switch r {
    case .reply: return "answered"
    case .pumpError(let e): return "op-77 error \(e.errorCodeId)"
    case .notSent(let why): return "not sent (\(why))"
    case .unknown(let why): return "unknown (\(why))"
    }
}

// MARK: Bolus permission, held and released with no bolus

/// Guess 37: does the pump take back a granted permission (notice bit 31), when it lapses or when its own
/// bolus screen opens? This sends BolusPermission and BolusPermissionRelease and nothing else: no carb or
/// BG entry and no InitiateBolus, so nothing can be delivered, whatever is in the cartridge.
@MainActor
func permission(_ s: BenchSession, seconds: Double) async {
    guard await s.whenReady() else { return say("RESULT not sent: the link wasn't ready") }
    if let active = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self),
        active.isActive
    {
        return say("RESULT not sent: a bolus is active on the pump")
    }
    say("  one BolusPermission, held \(Int(seconds)) s, then released; no bolus is sent")
    let typed = await serialToCheck(s, "type this pump's serial number to ask for a bolus permission")
    if let why = BenchSafetyGate.writeRefusal(
        environment: env, typed: typed, pumpSerial: s.identity?.unit.map { Int($0.serialNumber) })
    {
        return say("RESULT not sent: \(why)")
    }
    var revokedAt: Double?
    let start = s.link.now
    s.noticeHandler = { raw in
        if raw & (1 << 31) != 0, revokedAt == nil { revokedAt = s.link.now }
    }
    defer { s.noticeHandler = nil }
    let permitResult = await s.request(
        BolusPermissionRequest(), allowing: BolusPermissionRequest().operationRisk, deadline: 60)
    if case .unknown = permitResult {
        return say(
            "RESULT permission outcome unknown: the pump may hold a permission until it lapses. Check the "
                + "pump's bolus screen opens before anything else")
    }
    guard let permit = s.reply(permitResult, as: BolusPermissionResponse.self), permit.granted else {
        let why = s.reply(permitResult, as: BolusPermissionResponse.self).map { "nack reason \($0.nackReasonId)" }
        return say("RESULT permission not granted: \(why ?? verdictText(permitResult))")
    }
    let dropsBefore = s.drops
    say("  permission granted, bolus id \(permit.bolusId). To test the pump's own bolus screen, open it now and")
    say("  type a NOTE when you do; otherwise leave the pump alone")
    let until = s.link.now + seconds
    while s.link.now < until, revokedAt == nil { await s.pause(1) }
    if let revokedAt { say(String(format: "  bit 31 arrived %.1f s after the request", revokedAt - start)) }
    let r = await s.request(
        BolusPermissionReleaseRequest(bolusID: permit.bolusId), allowing: BolusPermissionReleaseRequest().operationRisk)
    let releaseStatus = s.reply(r, as: BolusPermissionReleaseResponse.self).map { " status \($0.status)" } ?? ""
    say("  release: \(verdictText(r))\(releaseStatus)")
    await s.pause(5)
    say(
        "RESULT permission: "
            + (revokedAt.map { String(format: "revoked (bit 31) after %.1f s", $0 - start) }
                ?? "not revoked in \(Int(seconds)) s")
            + "; release \(verdictText(r))\(releaseStatus); link drops while held: \(s.drops - dropsBefore)")
}
