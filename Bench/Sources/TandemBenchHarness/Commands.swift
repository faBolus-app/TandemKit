import Foundation
import TandemBench
import TandemLink
import TandemMessages

enum HistoryStep: String, CaseIterable {
    case status, anchor, oldest, cap
}

enum Job {
    case scan
    /// Hold the link. `poll` nil sends no status reads (the notice log); `battery` reads the battery
    /// that often when not polling; `minutes` nil runs until Ctrl-C.
    case monitor(poll: Double?, battery: Double, minutes: Double?)
    case dismiss(NotificationKind, Int, chunk: Int?)
    case features(sets: [BenchFeatureSet], legacy: Bool)
    case history([HistoryStep])
    case snapshot(samples: Int, interval: Double)
    case cgm(minutes: Double)
    case lastBolus
    case api
    case statusReads
}

/// Runs the job once the link is first ready. Every request goes through the link's gates.
@MainActor
func runJob(_ s: BenchSession) async {
    switch s.job {
    case .scan:
        return
    case .monitor(let poll, let battery, let minutes):
        await monitor(s, poll: poll, battery: battery, minutes: minutes)
    case .dismiss(let kind, let id, _):
        // The link waits for its hold before an untested signed write goes out.
        let request = DismissNotificationRequest(kind: kind, notificationId: id)
        let result = await s.request(request, "DismissNotification(\(kind), \(id))", allowing: .benign, deadline: 30)
        if let r = s.reply(result, as: DismissNotificationResponse.self) {
            say("dismiss status \(r.status) (\(r.status == 0 ? "accepted" : "not accepted"))")
        }
    case .features(let sets, let legacy):
        await features(s, sets: sets, legacy: legacy)
    case .history(let steps):
        await history(s, steps: steps)
    case .snapshot(let samples, let interval):
        await snapshot(s, samples: samples, interval: interval)
    case .cgm(let minutes):
        await cgm(s, minutes: minutes)
    case .lastBolus:
        await lastBolus(s)
    case .api:
        await api(s)
    case .statusReads:
        await statusReads(s)
    }
}

// MARK: features

@MainActor
func features(_ s: BenchSession, sets: [BenchFeatureSet], legacy: Bool) async {
    let apiResult = await s.request(ApiVersionRequest())
    var api = s.identity?.apiVersion
    if let r = s.reply(apiResult, as: ApiVersionResponse.self) {
        api = ApiVersion(major: r.majorVersion, minor: r.minorVersion)
        say("API \(r.majorVersion).\(r.minorVersion)")
    }
    var main: BenchFeatureReport?
    let v2 = api.map { $0 >= .v2_5 } ?? false
    if v2 {
        for set in sets {
            let result = await s.request(
                PumpFeaturesV2Request(input: set.rawValue), "PumpFeaturesV2(\(set.rawValue) \(set.name))")
            guard let decoded = s.reply(result, as: PumpFeaturesV2Response.self) else { continue }
            let index = decoded.supportedFeatureIndexId
            say(
                "  status \(decoded.status), index echoed \(index), "
                    + "bitmask 0x\(String(decoded.pumpFeaturesBitmask, radix: 16))")
            if index != set.rawValue { say("  ! the pump answered index \(index), not \(set.rawValue)") }
            guard let report = BenchFeatureReport(decoded) else {
                say("  index \(index) has no pumpX2 name; bits by position:")
                for line in BenchFeatureReport.positionLines(UInt64(decoded.pumpFeaturesBitmask)) {
                    say("    \(line)")
                }
                continue
            }
            for line in report.lines + report.callouts { say("    \(line)") }
            if report.set == .main { main = report }
        }
    } else {
        say("API \(s.apiText(api)) is below 2.5 (or unknown): reading the legacy PumpFeaturesV1 only")
    }
    if !v2 || legacy {
        let result = await s.request(PumpFeaturesV1Request())
        if let r = s.reply(result, as: PumpFeaturesV1Response.self) {
            let report = BenchFeatureReport(set: .main, bitmask: r.featureBitmask)
            say("  PumpFeaturesV1 bitmask 0x\(String(r.featureBitmask, radix: 16)) (main-set bit names)")
            for line in report.lines + report.callouts { say("    \(line)") }
            if main == nil { main = report }
        }
    }
    if let main {
        say("RESULT " + main.callouts.joined(separator: "; "))
    } else {
        say("RESULT the main feature set wasn't read")
    }
}

// MARK: history

/// Sends one HistoryLogRequest and collects its stream frames: until `count` records came, or 3 s
/// passed with no frame, or 30 s in all.
@MainActor
func historyPage(_ s: BenchSession, start: UInt32, count: Int) async -> BenchHistoryProbe? {
    s.historyFrames = []
    let result = await s.request(
        HistoryLogRequest(startLog: start, numberOfLogs: count), "HistoryLog(start \(start), count \(count))")
    guard case .reply(let reply) = result else { return nil }
    if let ack = reply.message as? HistoryLogResponse { say("  ack status \(ack.status) stream \(ack.streamId)") }
    // The windows run from the ack, not the send: the request may have waited in the queue or for the
    // hold, and the stream follows the pump's answer.
    let acked = s.link.now
    while true {
        let got = s.historyFrames.reduce(0) { $0 + $1.frame.records.count }
        let last = max(s.historyFrames.last?.time ?? acked, acked)
        if got >= count || s.link.now - last > 3 || s.link.now - acked > 30 { break }
        try? await Task.sleep(for: .milliseconds(100))
    }
    var seqs: [UInt32] = []
    for (_, frame) in s.historyFrames {
        if !frame.isValid { say("  ! a stream frame failed its length check: \(Hex.encode(frame.cargo))") }
        for record in frame.records {
            let seq = Bytes.readUint32(record, 6)
            seqs.append(seq)
            transcript.detail(
                "record SN \(seq) type \(Bytes.readShort(record, 0) & 0x0FFF) time \(Bytes.readUint32(record, 2)): \(Hex.encode(record))"
            )
        }
    }
    let probe = BenchHistoryProbe(start: start, count: count, received: seqs)
    say("  " + probe.summary)
    say("  timing: " + BenchFrameTiming(arrivals: s.historyFrames.map(\.time)).summary)
    return probe
}

@MainActor
func history(_ s: BenchSession, steps: [HistoryStep]) async {
    let statusResult = await s.request(HistoryLogStatusRequest())
    guard let status = s.reply(statusResult, as: HistoryLogStatusResponse.self) else {
        say("RESULT no HistoryLogStatus, so no history steps")
        return
    }
    let first = status.firstSequenceNum
    let last = status.lastSequenceNum
    say(
        "  entries \(status.numEntries), first (oldest) SN \(first), last (newest) SN \(last), "
            + "span \(last >= first ? Int(last - first) + 1 : -1)")
    var results: [String] = ["oldest SN \(first), newest SN \(last), entries \(status.numEntries)"]
    var anchoring: BenchHistoryProbe.Anchoring?
    if steps.contains(.anchor) {
        if last >= first + 30 {
            if let p = await historyPage(s, start: last - 20, count: 5) {
                results.append("start=last-20 count=5: \(p.anchoring.rawValue)")
                anchoring = p.anchoring
            }
            if let p = await historyPage(s, start: last, count: 5) {
                results.append("start=last count=5: \(p.anchoring.rawValue)")
            }
        } else {
            say("  anchor: fewer than 31 records in the log, skipped")
        }
    }
    if steps.contains(.oldest) {
        if last >= first + 4, let p = await historyPage(s, start: first + 4, count: 5) {
            results.append("start=first+4 count=5: \(p.anchoring.rawValue)")
        }
        if let p = await historyPage(s, start: first, count: 1) {
            results.append(
                "start=first count=1: \(p.received.first.map { $0 == first ? "the oldest record came back" : "SN \($0) came back" } ?? "nothing")"
            )
        }
    }
    if steps.contains(.cap) {
        // A page can be full only if the log holds that many records. The page asks for the newest
        // `count` records under the reading of startLog the anchor step found: start=last when it is
        // the top, start=last-count+1 when it is the low end.
        let low = anchoring == .low
        if let anchoring, anchoring != .top, !low {
            say("  cap: the anchor step gave \(anchoring.rawValue), so a short page can't be read as a cap")
        } else if anchoring == nil {
            say("  cap: no anchor result in this run; asking start=last (the top reading)")
        }
        let span = last >= first ? Int(last - first) + 1 : 0
        for count in [250, 255] {
            if span < count {
                say("  cap: the log holds \(span) record(s), fewer than \(count); a short page would say nothing")
                results.append("count \(count): not tested, the log holds \(span) record(s)")
                continue
            }
            let start = low ? last - UInt32(count - 1) : last
            guard let p = await historyPage(s, start: start, count: count) else {
                results.append("count \(count): no page")
                continue
            }
            results.append(
                BenchHistoryProbe.capVerdict(asked: count, got: p.received.count) + " (\(p.anchoring.rawValue))")
        }
    }
    for r in results { say("RESULT \(r)") }
}

// MARK: snapshot

@MainActor
func snapshot(_ s: BenchSession, samples: Int, interval: Double) async {
    var readingAt: [[Int]] = []
    var timestampAt: [[Int]] = []
    var readings = Set<Int>()
    for i in 0..<max(samples, 1) {
        if i > 0 { await s.pause(interval) }
        say("sample \(i + 1) of \(max(samples, 1))")
        let clock = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self)
        let egv = s.reply(await s.request(CurrentEGVGuiDataRequest()), as: CurrentEGVGuiDataResponse.self)
        let snap = s.reply(await s.request(BolusCalcDataSnapshotRequest()), as: BolusCalcDataSnapshotResponse.self)
        let mirror = s.reply(await s.request(HomeScreenMirrorRequest()), as: HomeScreenMirrorResponse.self)
        if let egv {
            let age = clock.map { " age \(Int($0.currentTime) - egv.bgReadingTimestampSeconds) s" } ?? ""
            say(
                "  EGV \(egv.cgmReading) mg/dL status \(BenchCgmNames.egvStatus(egv.egvStatusId)) "
                    + "timestamp \(egv.bgReadingTimestampSeconds)\(age)")
        }
        if let mirror {
            say("  mirror CGM alert icon \(mirror.cgmAlertIconId) \(BenchCgmNames.alertIcon(mirror.cgmAlertIconId))")
        }
        guard let snap else { continue }
        for line in BenchSnapshot.lines(snap.cargo) { say("  \(line)") }
        let key = BenchSnapshot.keyOffsets.map { "byte \($0)=\(snap.cargo.count > $0 ? String(snap.cargo[$0]) : "-")" }
        say("RESULT sample \(i + 1): " + key.joined(separator: ", "))
        if let egv, egv.cgmReading > 0 {
            let found = BenchSnapshot.locate(
                reading: egv.cgmReading, timestamp: UInt32(egv.bgReadingTimestampSeconds), in: snap.cargo)
            readingAt.append(found.reading)
            timestampAt.append(found.timestamp)
            readings.insert(egv.cgmReading)
            say(
                "  the EGV reading appears at \(found.reading), its timestamp at \(found.timestamp) (undecoded bytes only)"
            )
        }
    }
    if !readingAt.isEmpty {
        say(
            "RESULT reading candidates in every sample: \(BenchSnapshot.consistent(readingAt)); "
                + "timestamp candidates: \(BenchSnapshot.consistent(timestampAt)); "
                + "\(readings.count) distinct reading(s) over \(readingAt.count) sample(s)"
                + (readings.count < 2 ? " (one value: a candidate isn't confirmed until the reading changes)" : ""))
    } else {
        say("RESULT no EGV reading to locate (no CGM, or no reading yet)")
    }
}

// MARK: cgm

@MainActor
func cgm(_ s: BenchSession, minutes: Double) async {
    let end = s.link.now + minutes * 60
    var shownDespiteIcon = 0
    var samples = 0
    var icons: [String: Int] = [:]
    repeat {
        if samples > 0 { await s.pause(60) }
        samples += 1
        let mirror = s.reply(await s.request(HomeScreenMirrorRequest()), as: HomeScreenMirrorResponse.self)
        let egv = s.reply(await s.request(CurrentEGVGuiDataRequest()), as: CurrentEGVGuiDataResponse.self)
        let status = s.reply(await s.request(CGMStatusRequest()), as: CGMStatusResponse.self)
        if let mirror {
            let icon = BenchCgmNames.alertIcon(mirror.cgmAlertIconId)
            icons[icon, default: 0] += 1
            for line in BenchMirror.lines(mirror.cargo) { say("  mirror \(line)") }
        }
        if let egv {
            say(
                "  EGV: \(egv.cgmReading) mg/dL status \(egv.egvStatusId) \(BenchCgmNames.egvStatus(egv.egvStatusId)) "
                    + "timestamp \(egv.bgReadingTimestampSeconds) trendRate \(egv.trendRate)")
        }
        if let status {
            say(
                "  CGMStatus: session \(status.sessionStateId) \(BenchCgmNames.sessionState(status.sessionStateId)), "
                    + "transmitter battery \(status.transmitterBatteryStatusId)")
        }
        if let mirror, let egv,
            BenchCgmNames.readingDespiteIcon(alertIcon: mirror.cgmAlertIconId, egvStatus: egv.egvStatusId)
        {
            shownDespiteIcon += 1
            say("  ! the EGV read has a reading while the icon is \(BenchCgmNames.alertIcon(mirror.cgmAlertIconId))")
        }
    } while s.link.now < end
    let seen = icons.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
    say(
        "RESULT \(samples) sample(s); icons seen: \(seen.isEmpty ? "none" : seen); reading-while-icon-not-NO_ERROR: \(shownDespiteIcon)"
    )
}

// MARK: last bolus

@MainActor
func lastBolus(_ s: BenchSession) async {
    // C first: it's the read in question, and on a pump that lacks it the op-77 ends probing for this
    // connection, which A and B (answered before on P1) don't need.
    let c = await s.request(BenchLastBolusStatusV3Request(), "LastBolusStatusV3 (C, 0xBA)")
    if let r = s.reply(c, as: LastBolusStatusV3Response.self) {
        say(
            "  C: typeMask \(r.lastBolusTypeBitmask); standard status \(r.standardBolusStatusId) id \(r.standardBolusId) "
                + "time \(r.standardBolusTimestamp) delivered \(r.standardBolusDeliveredVolume) mU requested "
                + "\(r.standardBolusRequestedVolume) mU endReason \(r.standardBolusEndReasonId) source "
                + "\(r.standardBolusSourceId) mask \(r.standardBolusTypeBitmask); extended status \(r.extendedBolusStatusId) "
                + "id \(r.extendedBolusId)")
    }
    let b = await s.request(LastBolusStatusV2Request(), "LastBolusStatusV2 (B, 164)")
    if let r = s.reply(b, as: LastBolusStatusV2Response.self) {
        say(
            "  B: status \(r.status) id \(r.bolusId) time \(r.timestamp) delivered \(r.deliveredVolume) mU "
                + "requested \(r.requestedVolume) mU")
    }
    let a = await s.request(LastBolusStatusRequest(), "LastBolusStatus (A, 48)")
    if let r = s.reply(a, as: LastBolusStatusResponse.self) {
        say(
            "  A: status \(r.status) id \(r.bolusId) time \(r.timestamp) delivered \(r.deliveredVolume) mU "
                + "statusId \(r.bolusStatusId) source \(r.bolusSourceId) mask \(r.bolusTypeBitmask)")
    }
    func verdict(_ r: RequestResult) -> String {
        switch r {
        case .reply: return "answered"
        case .pumpError(let e): return "op-77 error \(e.errorCodeId)"
        case .notSent(let why): return "not sent (\(why))"
        case .unknown(let why): return "unknown (\(why))"
        }
    }
    say("RESULT C \(verdict(c)); B \(verdict(b)); A \(verdict(a))")
}

// MARK: api

@MainActor
func api(_ s: BenchSession) async {
    let a = s.reply(await s.request(ApiVersionRequest()), as: ApiVersionResponse.self)
    let v = s.reply(await s.request(PumpVersionRequest()), as: PumpVersionResponse.self)
    if let v {
        say(
            "  arm \(v.armSwVer) msp \(v.mspSwVer) serial \(v.serialNum) part \(v.partNum) rev \(v.pumpRev) model \(v.modelNum)"
        )
    }
    // Byte 0 is the glucose unit; pumpX2 decodes it as a number without naming the values.
    let l = s.reply(await s.request(LocalizationRequest()), as: LocalizationResponse.self)
    if let l {
        say(
            "  localization: glucose unit byte \(l.glucoseUOM) (compare with the pump's mg/dL or mmol/L setting), "
                + "language \(l.languageSelected), region \(l.regionSetting)")
    }
    say(
        "RESULT API \(a.map { "\($0.majorVersion).\($0.minorVersion)" } ?? "unread"), family "
            + "\(a.map { "\($0.family)" } ?? "?"), DIS model \(s.identity?.modelNumber ?? "-"), "
            + "glucose unit byte \(l.map { String($0.glucoseUOM) } ?? "unread")")
}

// MARK: status reads

/// The three status reads the library lists as rejected on P2 from the old app, which recorded a
/// rejection after any error. Each goes out once; on a pump with no answer of its own recorded, a
/// class rejection makes it a careful probe, and the first op-77 ends probing for the connection, so a
/// read after it reports `probeStopped` (run the command again for the rest).
@MainActor
func statusReads(_ s: BenchSession) async {
    var verdicts: [String] = []
    func verdict(_ name: String, _ r: RequestResult) {
        switch r {
        case .reply: verdicts.append("\(name) answered")
        case .pumpError(let e): verdicts.append("\(name) op-77 error \(e.errorCodeId)")
        case .notSent(let why): verdicts.append("\(name) not sent (\(why))")
        case .unknown(let why): verdicts.append("\(name) unknown (\(why))")
        }
    }
    let insulin = await s.request(InsulinStatusRequest())
    if let r = s.reply(insulin, as: InsulinStatusResponse.self) {
        say("  insulin \(r.currentInsulinAmount) U, estimate \(r.isEstimate), low threshold \(r.insulinLowAmount) U")
    }
    verdict("InsulinStatus", insulin)
    let mirror = await s.request(HomeScreenMirrorRequest())
    if let r = s.reply(mirror, as: HomeScreenMirrorResponse.self) {
        for line in BenchMirror.lines(r.cargo) { say("  mirror \(line)") }
    }
    verdict("HomeScreenMirror", mirror)
    let battery = await s.request(CurrentBatteryV2Request())
    if let r = s.reply(battery, as: CurrentBatteryV2Response.self) {
        say("  battery \(r.currentBatteryIbc)%, abc \(r.currentBatteryAbc), charging status \(r.chargingStatus)")
    }
    verdict("CurrentBatteryV2", battery)
    say("RESULT " + verdicts.joined(separator: "; "))
}

// MARK: monitor and notices

/// Holds the link. With `poll`, reads what the app shows every `poll` seconds (the hold check, and
/// the app-cadence half of the battery question); without, reads only the battery every `battery`
/// seconds and logs the pump's notices (bit 19, the idle-link half). Reports every 10 minutes.
@MainActor
func monitor(_ s: BenchSession, poll: Double?, battery: Double, minutes: Double?) async {
    var trend = BenchBatteryTrend()
    let started = s.link.now
    s.onFinish = { say(trend.summary) }
    var lastReport = started
    var lastBattery = -Double.infinity
    var clockChanged = false
    s.noticeHandler = { raw in
        if raw & QualifyingEvent.timeChange.rawValue != 0 { clockChanged = true }
    }
    while minutes.map({ s.link.now - started < $0 * 60 }) ?? true {
        let now = s.link.now
        if clockChanged {
            // What the pump's clock says right after it raised a time-change notice.
            clockChanged = false
            if let t = s.reply(await s.request(TimeSinceResetRequest()), as: TimeSinceResetResponse.self) {
                say("  after the time-change notice: pump time \(t.currentTime), since reset \(t.pumpTimeSinceReset) s")
            }
        }
        if let poll {
            let reads: [any Message] = [
                TimeSinceResetRequest(), CurrentBatteryV1Request(), InsulinStatusRequest(),
                CurrentBasalStatusRequest(), ControlIQIOBRequest(), CurrentEGVGuiDataRequest(), AlertStatusRequest()
            ]
            for read in reads {
                let result = await s.request(read)
                if let b = s.reply(result, as: CurrentBatteryV1Response.self) {
                    trend.add(b.batteryPercent, at: s.link.now)
                }
            }
            await s.pause(poll)
        } else {
            if now - lastBattery >= battery {
                lastBattery = now
                if let b = s.reply(await s.request(CurrentBatteryV1Request()), as: CurrentBatteryV1Response.self) {
                    trend.add(b.batteryPercent, at: s.link.now)
                    say("  battery \(b.batteryPercent)%")
                }
            }
            await s.pause(5)
        }
        if s.link.now - lastReport >= 600 {
            lastReport = s.link.now
            s.report()
            say(trend.summary)
            if let rate = s.requests.perHour(at: s.link.now) {
                say(String(format: "requests written: %d (%.0f an hour)", s.requests.writes, rate))
            }
            for line in s.reconnects.summary + s.commsSuspended.summary { say(line) }
        }
    }
}
