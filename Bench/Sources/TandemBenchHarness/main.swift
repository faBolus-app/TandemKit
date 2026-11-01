import Foundation
import TandemAuth
import TandemBLE
import TandemLink
import TandemMessages

// TandemBenchHarness: the bench CLI against a real pump, on the same `PumpConnection` the app uses.
//
// SAFETY: experimental software in development; not FDA-cleared. Bench pumps only.
//
// Commands:
//   (none)          serialization self-check, no Bluetooth
//   scan            list pumps in pairing range
//   monitor         pair, hold the link, read status every minute, report every drop with its reason
//                   and the telemetry every 10 minutes (the 24 h hold check)
//   dismiss <kind> <id>
//                   after the link holds, dismiss one pump notification (kind: reminder, alert, alarm,
//                   cgm) and report whether the pump accepted it or doesn't support it
//
// Environment:
//   PUMP_PAIRING_CODE   16-character legacy code or 6-digit JPAKE code (required to connect)
//   PUMP_PERIPHERAL_ID  the pump's CoreBluetooth identifier; without it the first t:slim X2 found is used
//   PUMP_SUPPORT_MATRIX where the support matrix is kept between runs
//                       (default ~/.tandemkit-bench/support-matrix.json)
//
// Nothing here writes insulin: the only signed write this tool sends is DismissNotification, allowed
// for that one call. Every request goes through the link's gates (support matrix, probing, the six
// allowed signed writes).

setbuf(stdout, nil)  // live output when piped to `tee`

let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment

func stamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

func say(_ line: String) { print("[\(stamp())] \(line)") }

func serializationSelfCheck() {
    print("TandemBenchHarness — serialization self-check (no Bluetooth)")
    if let packets = try? Packetize.packetize(ApiVersionRequest(), txId: 0) {
        print("  ApiVersionRequest(txId=0): \(packets.map { Hex.encode($0.build()) })")
    }
}

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

    static func save(_ matrix: SupportMatrix) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(matrix).write(to: url)
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

@MainActor
final class Bench {
    enum Job {
        case scan
        case monitor
        case dismiss(NotificationKind, Int)
    }

    let job: Job
    let link = PumpConnection(restoreIdentifier: nil)
    var target: PumpTarget?
    var pollTask: Task<Void, Never>?
    var reportTask: Task<Void, Never>?
    var jobStarted = false

    init(job: Job) {
        self.job = job
    }

    func start() {
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
        switch event {
        case .phase(let phase):
            say("link: \(phase)")
            if phase == .ready { scheduleJob() }
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
            say(
                "ready: model=\(identity.model.map { "\($0)" } ?? "?") api=\(identity.apiVersion.map { "\($0.major).\($0.minor)" } ?? "?") "
                    + "unit=\(identity.unit.map { "sn \($0.serialNumber) arm \($0.armSoftwareVersion) msp \($0.mspSoftwareVersion)" } ?? "?") "
                    + "dis=\(identity.modelNumber ?? "-")")
        case .disconnected(let reason, let span):
            say(
                "closed: \(reason) after \(String(format: "%.1f", span.duration)) s, held=\(span.held), flaps=\(span.flapsAfter)"
            )
            pollTask?.cancel()
        case .connectionUnstable(let flaps):
            say("connection unstable after \(flaps) flaps")
        case .connectionRestored:
            say("connection restored")
        case .supportMatrixChanged(let matrix):
            MatrixFile.save(matrix)
            say("support matrix saved to \(MatrixFile.url.path)")
        case .qualifyingEvents(let events):
            say("qualifying events: 0x\(String(events.rawValue, radix: 16))")
        case .unsolicited(let reply):
            say("unsolicited \(type(of: reply.message)) on \(reply.characteristic.name)")
        }
    }

    func scheduleJob() {
        switch job {
        case .scan:
            break
        case .monitor:
            pollTask?.cancel()
            pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    await self?.poll()
                    try? await Task.sleep(for: .seconds(60))
                }
            }
            if reportTask == nil {
                reportTask = Task { @MainActor [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(600))
                        self?.report()
                    }
                }
            }
        case .dismiss(let kind, let id):
            guard !jobStarted else { return }
            jobStarted = true
            Task { @MainActor in
                // The link waits for its hold before an untested signed write goes out.
                let request = DismissNotificationRequest(kind: kind, notificationId: id)
                let result = await link.send(request, allowing: .benign, deadline: 30)
                say("DismissNotification(\(kind), \(id)) → \(describe(result))")
                report()
                exit(0)
            }
        }
    }

    /// Reads the app shows, through the link's gates: an untested one is probed after the hold.
    func poll() async {
        let reads: [any Message] = [
            TimeSinceResetRequest(), CurrentBatteryV1Request(), InsulinStatusRequest(), CurrentBasalStatusRequest(),
            ControlIQIOBRequest(), CurrentEGVGuiDataRequest(), AlertStatusRequest()
        ]
        for read in reads {
            let result = await link.send(read)
            say("\(type(of: read)) → \(describe(result))")
        }
    }

    func describe(_ result: RequestResult) -> String {
        switch result {
        case .reply(let reply): return "\(type(of: reply.message)) \(Hex.encode(reply.message.cargo))"
        case .pumpError(let error): return "op-77 request=\(error.requestCodeId) error=\(error.errorCodeId)"
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
}

func kind(_ name: String) -> NotificationKind? {
    switch name {
    case "reminder": return .reminder
    case "alert": return .alert
    case "alarm": return .alarm
    case "cgm": return .cgmAlert
    default: return nil
    }
}

guard let command = args.first else {
    serializationSelfCheck()
    exit(0)
}

let job: Bench.Job
switch command {
case "scan": job = .scan
case "monitor": job = .monitor
case "dismiss":
    guard args.count == 3, let k = kind(args[1]), let id = Int(args[2]) else {
        print("usage: dismiss <reminder|alert|alarm|cgm> <notification id>")
        exit(2)
    }
    job = .dismiss(k, id)
default:
    print("unknown command: \(command)")
    print("commands: (none)=self-check, scan, monitor, dismiss <kind> <id>")
    exit(2)
}

let bench = MainActor.assumeIsolated { Bench(job: job) }
MainActor.assumeIsolated { bench.start() }
RunLoop.main.run()
