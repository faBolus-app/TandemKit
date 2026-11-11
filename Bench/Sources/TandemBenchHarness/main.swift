import Foundation
import TandemBench
import TandemLink
import TandemMessages

// TandemBenchHarness: the bench CLI against a real pump, on the same `PumpConnection` the app uses.
//
// SAFETY: experimental software in development; not FDA-cleared. Bench pumps only.
//
// Nothing here writes insulin. Every command but `dismiss` sends reads only; `dismiss` sends one
// DismissNotification, allowed for that one call. Every request goes through the link's gates (the
// support matrix, careful probing, the seven allowed signed writes), and each run writes a transcript:
// every line printed, plus every packet in both directions (authorization frames redacted unless
// PUMP_RECORD_PAIRING=1).

setbuf(stdout, nil)  // live output when piped to `tee`

let usage = """
    TandemBenchHarness <command>  (no command: serialization self-check, no Bluetooth)

      scan                      list pumps in pairing range
      api                       the API version and the pump's software versions
      features [all|legacy|N..] the feature sets: main (0), control (2) and Dexcom (4) by default;
                                `all` adds 5, 6, 3 and 1; N reads only those indices; `legacy` also
                                reads PumpFeaturesV1 (always read below API 2.5)
      history [status|anchor|oldest|cap..]
                                the log's oldest and newest SNs, which end of a page startLog names
                                (anchor, oldest), and whether a page of 251-255 is cut at 250 (cap).
                                Default: status anchor oldest
      snapshot [samples] [seconds]
                                the bolus-calculator snapshot byte by byte (bytes 0, 13, 24, 25, 37), and
                                where the CGM reading and its timestamp sit in it; default 1 sample, 300 s
      cgm [minutes]             the home-screen icons (CGM alert, basal, bolus, Control-IQ state), the EGV
                                status and the CGM session, once a minute (0 = once)
      lastbolus                 LastBolusStatus forms C (0xBA), B and A
      statusreads               InsulinStatus, HomeScreenMirror and CurrentBatteryV2, once each
      monitor [--poll S|off] [--battery S] [--minutes M]
                                hold the link (the 24 h hold check, range edge, battery); reads the app's
                                status set every S seconds (default 60), or with `off` only the battery
                                every --battery seconds (default 1800); logs every drop and reconnect
      notices [minutes]         hold the link with no status reads and log every pump notice (bit 19);
                                same as monitor --poll off; default 60 minutes
      dismiss [--chunk 18] <reminder|alert|alarm|cgm> <id>
                                dismiss one pump notification; --chunk re-cuts the control write's
                                packets at that size (the chunk-size check)

      --retest                  (any command) forget this pump's recorded result for each command
                                before sending it, so it is probed again

    Not built yet (each changes the write grants or touches the dose path): UserInteractionRequest,
    setting the pump clock, remote alert clearing with a history check, and the bolus items.

    Environment: PUMP_PAIRING_CODE (required to connect), PUMP_PERIPHERAL_ID, PUMP_SUPPORT_MATRIX
    (default ~/.tandemkit-bench/support-matrix.json), PUMP_TRANSCRIPT_DIR (default
    ~/.tandemkit-bench/transcripts), PUMP_PACKETS=1 (print packets too, not only in the transcript),
    PUMP_RECORD_PAIRING=1 (keep the pairing exchange in the transcript; see the README before sharing it).
    Type a line and Enter during a run to stamp a note into the transcript.
    """

var args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment
let retestFlag = args.contains("--retest")
args.removeAll { $0 == "--retest" }

func serializationSelfCheck() {
    print("TandemBenchHarness — serialization self-check (no Bluetooth)")
    if let packets = try? Packetize.packetize(ApiVersionRequest(), txId: 0) {
        print("  ApiVersionRequest(txId=0): \(packets.map { Hex.encode($0.build()) })")
    }
}

func fail(_ message: String) -> Never {
    print(message)
    print(usage)
    exit(2)
}

func notificationKind(_ name: String) -> NotificationKind? {
    switch name {
    case "reminder": return .reminder
    case "alert": return .alert
    case "alarm": return .alarm
    case "cgm": return .cgmAlert
    default: return nil
    }
}

/// `--name value` from `rest`, removed from it.
func option(_ name: String, in rest: inout [String]) -> String? {
    guard let i = rest.firstIndex(of: name) else { return nil }
    guard i + 1 < rest.count else { fail("\(name) needs a value") }
    let value = rest[i + 1]
    rest.removeSubrange(i...(i + 1))
    return value
}

func number(_ text: String, _ what: String) -> Double {
    guard let n = Double(text), n >= 0 else { fail("\(what) must be a number, not \(text)") }
    return n
}

func parseJob(_ command: String, _ rest: [String]) -> Job {
    var rest = rest
    switch command {
    case "scan":
        return .scan
    case "api":
        return .api
    case "lastbolus":
        return .lastBolus
    case "statusreads":
        return .statusReads
    case "features":
        var sets: [BenchFeatureSet] = []
        var legacy = false
        for a in rest {
            if a == "all" {
                sets += BenchFeatureSet.defaultOrder + BenchFeatureSet.extraOrder
            } else if a == "legacy" {
                legacy = true
            } else if let n = Int(a), let set = BenchFeatureSet(rawValue: n) {
                sets.append(set)
            } else {
                fail("features: unknown argument \(a)")
            }
        }
        if sets.isEmpty { sets = BenchFeatureSet.defaultOrder }
        var seen = Set<Int>()
        return .features(sets: sets.filter { seen.insert($0.rawValue).inserted }, legacy: legacy)
    case "history":
        let steps = rest.map { a -> HistoryStep in
            guard let step = HistoryStep(rawValue: a) else { fail("history: unknown step \(a)") }
            return step
        }
        return .history(steps.isEmpty ? [.status, .anchor, .oldest] : steps)
    case "snapshot":
        let samples = rest.first.map { Int(number($0, "samples")) } ?? 1
        let interval = rest.count > 1 ? number(rest[1], "seconds") : 300
        return .snapshot(samples: samples, interval: interval)
    case "cgm":
        return .cgm(minutes: rest.first.map { number($0, "minutes") } ?? 0)
    case "monitor":
        let pollText = option("--poll", in: &rest)
        let poll: Double? = pollText == "off" ? nil : pollText.map { number($0, "--poll") } ?? 60
        let battery = option("--battery", in: &rest).map { number($0, "--battery") } ?? 1800
        let minutes = option("--minutes", in: &rest).map { number($0, "--minutes") }
        if let extra = rest.first { fail("monitor: unknown argument \(extra)") }
        return .monitor(poll: poll, battery: battery, minutes: minutes)
    case "notices":
        return .monitor(poll: nil, battery: 1800, minutes: rest.first.map { number($0, "minutes") } ?? 60)
    case "dismiss":
        let chunk = option("--chunk", in: &rest).map { Int(number($0, "--chunk")) }
        guard rest.count == 2, let k = notificationKind(rest[0]), let id = Int(rest[1]) else {
            fail("usage: dismiss [--chunk 18] <reminder|alert|alarm|cgm> <notification id>")
        }
        if let chunk, !(1...40).contains(chunk) { fail("--chunk must be 1 to 40") }
        return .dismiss(k, id, chunk: chunk)
    default:
        fail("unknown command: \(command)")
    }
}

guard let command = args.first else {
    serializationSelfCheck()
    exit(0)
}
if command == "help" || command == "--help" {
    print(usage)
    exit(0)
}

let job = parseJob(command, Array(args.dropFirst()))
let transcript = Transcript(command: command, environment: env)

func say(_ line: String) { transcript.line(line) }

say("TandemBenchHarness \(CommandLine.arguments.dropFirst().joined(separator: " "))")
say("support matrix: \(MatrixFile.url.path); transcript: \(transcript.url?.path ?? "none")")

let bench = MainActor.assumeIsolated { BenchSession(job: job) }
MainActor.assumeIsolated {
    bench.retest = retestFlag
    bench.start()
}

// Ctrl-C ends the run with its summary and closes the transcript.
signal(SIGINT, SIG_IGN)
let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
interrupt.setEventHandler { MainActor.assumeIsolated { bench.finish(code: 0) } }
interrupt.resume()

// A line typed during a run is stamped into the transcript, to mark what was done at the pump.
Thread.detachNewThread {
    while let line = readLine() {
        let note = line.trimmingCharacters(in: .whitespaces)
        if !note.isEmpty { transcript.line("NOTE: \(note)") }
    }
}

RunLoop.main.run()
