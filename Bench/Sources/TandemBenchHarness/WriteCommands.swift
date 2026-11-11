import Foundation
import TandemBench
import TandemLink
import TandemMessages

/// Lines typed during a run: a prompt waiting for one takes it; otherwise it's stamped as a NOTE.
@MainActor
final class LineInbox {
    private var waiting: CheckedContinuation<String, Never>?

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
        return await withCheckedContinuation { waiting = $0 }
    }
}

/// The bench bolus log, kept next to the support matrix.
enum BolusLogFile {
    static var url: URL {
        if let path = env["PUMP_BOLUS_LOG"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tandemkit-bench/bench-boluses.json")
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
    let typed = await s.inbox.prompt("type this pump's serial number (the `ready` line above) to send UserInteraction")
    if let why = BenchSafetyGate.writeRefusal(
        environment: env, typed: typed, pumpSerial: s.identity?.unit.map { Int($0.serialNumber) })
    {
        return say("RESULT not sent: \(why)")
    }
    let result = await s.request(UserInteractionRequest(), allowing: UserInteractionRequest().operationRisk, deadline: 60)
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
    let typed = await s.inbox.prompt("type this pump's serial number to set its clock")
    if let why = BenchSafetyGate.writeRefusal(
        environment: env, typed: typed, pumpSerial: s.identity?.unit.map { Int($0.serialNumber) })
    {
        return say("RESULT not sent: \(why)")
    }
    let before = s.reply(await s.request(HistoryLogStatusRequest()), as: HistoryLogStatusResponse.self)
    var results: [String] = []
    // A no-op first: the pump's own time, moved on by the seconds since it was read. Then +5 min and back.
    let steps: [(String, Int)] = plusFive ? [("same time", 0), ("+5 min", 300), ("back", -300)] : [("same time", 0)]
    for (label, offset) in steps {
        guard let clock = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self) else {
            results.append("\(label): no clock read, stopped")
            break
        }
        let readAt = s.link.now
        let target = BenchClock.target(pumpTime: clock.currentTime, readAt: readAt, now: s.link.now, offset: offset)
        let request = ChangeTimeDateRequest(tandemEpochTime: target)
        let result = await s.request(request, "ChangeTimeDate(\(label): \(target))", allowing: request.operationRisk)
        if let r = s.reply(result, as: ChangeTimeDateResponse.self) { say("  status \(r.status) accepted \(r.accepted)") }
        let after = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self)
        say("  pump time after: \(after.map { String($0.currentTime) } ?? "unread") (asked \(target))")
        results.append("\(label): \(verdictText(result))")
        guard case .reply = result else { break }
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
func bolus(_ s: BenchSession, kind: BenchBolusKind, carbs: Int, bg: Int, noCartridge: Bool) async {
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
        "  \(kind.rawValue): 0.05 U, mask \(kind.mask), \(kind.source)"
            + (noCartridge ? "; no cartridge, so the pump should refuse it" : "; saline only, on no one"))
    let serial = s.identity?.unit.map { Int($0.serialNumber) }
    let typed = await s.inbox.prompt("type this pump's serial number to send one 0.05 U bench bolus")
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

    let pumpTime = clock?.pumpTimeSinceReset ?? 0
    if kind == .carb {
        let r = await s.request(
            RemoteCarbEntryRequest(carbs: carbs, pumpTimeSecondsSinceBoot: pumpTime, bolusId: id), allowing: .benign)
        guard s.reply(r, as: RemoteCarbEntryResponse.self)?.status == 0 else {
            await release("the carb entry wasn't accepted")
            return say("RESULT not sent: RemoteCarbEntry \(verdictText(r))")
        }
    }
    if kind == .correction {
        // Never a calibration: that would shift the CGM.
        let entry = RemoteBgEntryRequest(
            bg: bg, useForCgmCalibration: false, isAutopopBg: false, pumpTimeSecondsSinceBoot: pumpTime, bolusId: id)
        let r = await s.request(entry, allowing: .benign)
        guard s.reply(r, as: RemoteBgEntryResponse.self)?.status == 0 else {
            await release("the BG entry wasn't accepted")
            return say("RESULT not sent: RemoteBgEntry \(verdictText(r))")
        }
    }

    let request: InitiateBolusRequest
    do {
        request = try kind.request(bolusId: id, carbs: carbs, bg: bg)
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
    let initiate = await s.request(request, "InitiateBolus(\(kind.rawValue))", allowing: .delivery, deadline: 60)
    say(String(format: "  reply after %.2f s", s.link.now - sentAt))
    var outcome: String?
    switch initiate {
    case .reply(let reply):
        let r = reply.message as? InitiateBolusResponse
        say("  status \(r?.status ?? -1) id \(r?.bolusId ?? -1) statusType \(r?.statusTypeId ?? -1)")
        if r?.status != 0 {
            outcome = "refused: status \(r?.status ?? -1)"
            await release("the pump refused the bolus")
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
        let c = await s.request(CancelBolusRequest(bolusId: id), allowing: CancelBolusRequest().operationRisk)
        if let r = s.reply(c, as: CancelBolusResponse.self) {
            say("  cancel status \(r.statusId) id \(r.bolusId) reason \(r.reasonId)")
        }
    }
    if outcome == nil, case .reply = initiate { outcome = await follow(s, id: id) }
    await lastBolus(s)
    if let history, let page = await newHistory(s, since: history.lastSequenceNum) { say("  history since: \(page)") }
    if let outcome {
        _ = log.settleLast(outcome)
        _ = BolusLogFile.save(log)
        say("RESULT bolus \(id) \(kind.rawValue): \(outcome)")
    } else {
        say("RESULT bolus \(id) \(kind.rawValue): outcome not settled; check the pump, then `bolus settle`")
    }
}

/// Follows the bolus every 2 s until the pump no longer reports it, up to two minutes. The outcome is
/// what the pump's status said; nil when it was still active at the end.
@MainActor
func follow(_ s: BenchSession, id: Int) async -> String? {
    var last = -1
    let end = s.link.now + 120
    while s.link.now < end {
        guard let status = s.reply(await s.request(CurrentBolusStatusRequest()), as: CurrentBolusStatusResponse.self)
        else {
            await s.pause(2)
            continue
        }
        if status.statusId != last {
            last = status.statusId
            say("  CurrentBolusStatus: status \(status.statusId) id \(status.bolusId) requested \(status.requestedVolume) mU")
        }
        if !status.isActive { return "ended (status \(status.statusId)); see LastBolusStatus and history below" }
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

func verdictText(_ r: RequestResult) -> String {
    switch r {
    case .reply: return "answered"
    case .pumpError(let e): return "op-77 error \(e.errorCodeId)"
    case .notSent(let why): return "not sent (\(why))"
    case .unknown(let why): return "unknown (\(why))"
    }
}
