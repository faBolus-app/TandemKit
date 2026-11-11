import Foundation
import TandemAuth
import TandemBLE
import TandemBench
import TandemLink
import TandemMessages

/// The support matrix, kept between runs like the app keeps it with the pairing.
enum MatrixFile {
    static var url: URL {
        if let path = env["PUMP_SUPPORT_MATRIX"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tandemkit-bench/support-matrix.json")
    }

    static func load() -> SupportMatrix {
        guard let data = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(SupportMatrix.self, from: data)
        else { return SupportMatrix() }
        return m
    }

    /// Writes the matrix without losing what another run saved meanwhile (P1 and P2 in two terminals):
    /// this pump's entries come from `matrix`, which holds its forgets as well as its new results; every
    /// other pump's are what the file holds, merged with this run's copy of them.
    static func save(_ matrix: SupportMatrix, unit: PumpUnit?) {
        var merged = load()
        if let unit {
            for key in merged.recorded[unit]?.keys.map({ $0 }) ?? [] { merged.forget(key, on: unit) }
        }
        merged = merged.merging(matrix)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(merged).write(to: url, options: .atomic)
        } catch {
            say("couldn't save the support matrix: \(error)")
        }
    }
}

func credentials(_ code: String) throws -> PairingCredentials {
    switch PairingAuth.detectType(code) {
    case .long16Char: return .legacy(code: try PairingAuth.processPairingCode(code, type: .long16Char))
    case .short6Char: return .jpake(code: try PairingAuth.processPairingCode(code, type: .short6Char))
    }
}

/// One harness run: the link, its events, and the helpers the commands are written with.
@MainActor
final class BenchSession {
    let job: Job
    let transport: RecordingTransport
    let link: PumpConnection
    var target: PumpTarget?
    var jobStarted = false
    /// Forget this pump's recorded result for each command before sending it, so it is probed again.
    var retest = false
    /// The commands already retested this run: each is forgotten once, before its first send, so a
    /// repeated read isn't a fresh probe every time.
    var retested = Set<MessageKey>()

    // What the commands read back.
    var drops = 0
    var identity: PumpIdentity?
    var historyFrames: [(time: Double, frame: HistoryLogStreamResponse)] = []
    var noticeHandler: ((UInt32) -> Void)?
    var reconnects = BenchReconnectLog()
    var commsSuspended = BenchCommsSuspendedLog()
    var requests: BenchRequestRate
    var onFinish: (() -> Void)?
    let inbox = LineInbox()

    init(job: Job) {
        self.job = job
        transport = RecordingTransport(transcript: transcript)
        link = PumpConnection(transport: transport, clock: ContinuousLinkClock())
        requests = BenchRequestRate(since: 0)
        transport.onRequestWritten = { [weak self] in self?.requests.wrote() }
        if case .dismiss(_, _, let chunk) = job { transport.controlChunk = chunk }
        if case .bolus(_, _, _, _, let chunk) = job { transport.controlChunk = chunk }
        transport.recordPairing = env["PUMP_RECORD_PAIRING"] == "1"
    }

    func start() {
        requests = BenchRequestRate(since: link.now)
        link.setAppActive(true)  // a command-line tool's timers always run, as in an app's foreground
        Task { @MainActor in
            for await event in link.events { handle(event) }
        }
        if case .scan = job {
            link.scanForPairing()
            return
        }
        let code = env["PUMP_PAIRING_CODE"] ?? ""
        let creds: PairingCredentials
        do {
            creds = try credentials(code)
        } catch {
            say("PUMP_PAIRING_CODE must be a 16-character legacy code or a 6-digit JPAKE code")
            exit(2)
        }
        if let raw = env["PUMP_PERIPHERAL_ID"], let id = UUID(uuidString: raw) {
            connect(PumpTarget(peripheralID: id, model: .tslim, credentials: creds))
        } else {
            target = PumpTarget(peripheralID: UUID(), model: nil, credentials: creds)  // chosen on discovery
            link.scanForPairing()
        }
    }

    func connect(_ target: PumpTarget) {
        self.target = target
        say("connecting to \(target.peripheralID)")
        link.connect(to: target, support: MatrixFile.load())
    }

    func handle(_ event: LinkEvent) {
        let now = link.now
        switch event {
        case .phase(let phase):
            say("link: \(phase)")
            if phase == .connecting { reconnects.connecting(at: now) }
            if phase == .exhausted {
                say("  reconnecting stopped after the flap limit; this run won't reconnect again (Ctrl-C to end it)")
            }
            if phase == .ready {
                if let line = reconnects.ready(at: now) { say(line) }
                startJobOnce()
            }
        case .discovered(let id, let name, let model, let rssi):
            say("found \(name ?? "?") model=\(model.map { "\($0)" } ?? "?") rssi=\(rssi) id=\(id)")
            if case .scan = job { return }
            if let target, target.model == nil, model == .tslim {
                connect(PumpTarget(peripheralID: id, model: .tslim, credentials: target.credentials))
            }
        case .paired(let creds):
            target?.credentials = creds
            say("paired (JPAKE); later connections in this run resume from the derived secret")
        case .ready(let identity):
            self.identity = identity
            say(
                "ready: model=\(identity.model.map { "\($0)" } ?? "?") api=\(apiText(identity.apiVersion)) "
                    + "unit=\(identity.unit.map { "sn \($0.serialNumber) arm \($0.armSoftwareVersion) msp \($0.mspSoftwareVersion)" } ?? "?") "
                    + "dis=\(identity.modelNumber ?? "-")")
        case .disconnected(let reason, let span):
            drops += 1
            reconnects.dropped(at: now, upFor: span.duration, held: span.held, reason: "\(reason)")
            say(
                "closed: \(reason) after \(String(format: "%.1f", span.duration)) s, held=\(span.held), flaps=\(span.flapsAfter)"
            )
        case .connectionUnstable(let flaps):
            say("connection unstable after \(flaps) flaps")
        case .connectionRestored:
            say("connection restored")
        case .supportMatrixChanged(let matrix):
            MatrixFile.save(matrix, unit: identity?.unit ?? link.state.connection?.identity.unit)
            say("support matrix saved to \(MatrixFile.url.path)")
        case .qualifyingEvents(let events):
            say("notice: \(BenchNoticeBits.describe(events.rawValue))")
            if let line = commsSuspended.record(events.rawValue, at: now) { say("  \(line)") }
            noticeHandler?(events.rawValue)
        case .unsolicited(let reply):
            if let frame = reply.message as? HistoryLogStreamResponse {
                historyFrames.append((now, frame))
                transcript.detail("history frame: \(frame.records.count) record(s), stream \(frame.streamId)")
            } else {
                say(
                    "unsolicited \(type(of: reply.message)) on \(reply.characteristic.name): \(Hex.encode(reply.message.cargo))"
                )
            }
        case .cancelledRequestAnswered(let id, let result):
            say("request \(id), cancelled earlier, was answered: \(describe(result))")
        }
    }

    func startJobOnce() {
        guard !jobStarted else { return }
        jobStarted = true
        Task { @MainActor in
            await runJob(self)
            finish(code: 0)
        }
    }

    /// The final summary, then exit. Ctrl-C comes here too.
    func finish(code: Int32) {
        onFinish?()
        say(reconnects.summary.joined(separator: "\n  "))
        say(commsSuspended.summary.joined(separator: "\n  "))
        if let rate = requests.perHour(at: link.now) {
            say(String(format: "requests written: %d (%.0f an hour)", requests.writes, rate))
        }
        report()
        if let url = transcript.url { say("transcript: \(url.path)") }
        link.stop()
        transcript.close()
        exit(code)
    }

    // MARK: Helpers the commands use

    func apiText(_ api: ApiVersion?) -> String { api.map { "\($0.major).\($0.minor)" } ?? "?" }

    /// Waits until the link is ready, up to `timeout` seconds.
    func whenReady(timeout: Double = 120) async -> Bool {
        let until = link.now + timeout
        while link.state.phase != .ready {
            // Neither comes back by itself in a command-line run: `failed` is final, and `exhausted`
            // waits for an app to come to the foreground.
            switch link.state.phase {
            case .failed, .exhausted: return false
            default: break
            }
            if link.now > until { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }

    /// Sends one request through the link's gates and prints its reply cargo, raw. Returns the result
    /// for the command to decode.
    @discardableResult
    func request(
        _ message: any Message, _ label: String? = nil, allowing: OperationRisk = .read, deadline: Double = 10
    ) async -> RequestResult {
        let name = label ?? "\(type(of: message))"
        guard await whenReady() else {
            say("\(name): the link wasn't ready within 120 s; not sent")
            return .notSent(.notReady)
        }
        if retest, retested.insert(MessageKey(message)).inserted { link.retest(MessageKey(message)) }
        let before = drops
        transcript.detail("send \(name) cargo [\(message.cargo.count)] \(Hex.encode(message.cargo))")
        let result = await link.send(message, allowing: allowing, deadline: deadline)
        say("\(name) -> \(describe(result))")
        if drops != before { say("  the link dropped while \(name) was out") }
        if case .pumpError(let error) = result, error.errorCodeId == 6 {
            // One opcode is one matrix entry: every PumpFeaturesV2 index and every history count share it.
            say(
                "  the link now records this command as unsupported on this pump, for every argument and "
                    + "every later run; add --retest to send it again")
        }
        return result
    }

    /// The reply's message, or nil (the line above already said why).
    func reply<T: Message>(_ result: RequestResult, as: T.Type) -> T? {
        guard case .reply(let reply) = result else { return nil }
        return reply.message as? T
    }

    func describe(_ result: RequestResult) -> String {
        switch result {
        case .reply(let reply):
            return "\(type(of: reply.message)) [\(reply.message.cargo.count)] \(Hex.encode(reply.message.cargo))"
        case .pumpError(let error):
            let name = error.errorCodeId == 6 ? " (BAD_OPCODE)" : ""
            return "op-77 request=\(error.requestCodeId) error=\(error.errorCodeId)\(name)"
        case .notSent(let reason): return "not sent: \(reason)"
        case .unknown(let reason): return "unknown: \(reason)"
        }
    }

    func report() {
        let t = link.state.telemetry
        let open = link.state.connection?.connectedAt
        let up = t.uptime(openSince: open, now: link.now)
        say(
            "telemetry: connects=\(t.connects) disconnects=\(t.disconnects) uptime=\(Int(up)) s "
                + "open=\(open == nil ? "no" : "yes") last-reconnect=\(t.lastReconnectDuration.map { "\(Int($0)) s" } ?? "-") "
                + "flaps=\(link.state.ladder.flaps)")
        for span in t.spans.suffix(5) {
            say("  span \(String(format: "%.1f", span.duration)) s held=\(span.held) reason=\(span.reason)")
        }
    }

    /// Waits between steps; the link's events are handled meanwhile.
    func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
