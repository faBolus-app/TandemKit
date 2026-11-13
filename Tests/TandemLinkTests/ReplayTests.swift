import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// Replays the two app BLE logs from P1's reconnect loop (scrubbed copies in `Fixtures/`) through the
/// state machine: what the pump and CoreBluetooth did becomes inputs at the logged times, and the test
/// asserts the events the new link emits.
///
/// In both logs P1 drops the link about 2 s after every legacy pairing (CoreBluetooth error 7)
/// while the old app's 10+ read burst runs. The new link sends only the three handshake reads,
/// counts each 2 s drop as a flap (it never held) and backs off, never stopping. The logged connects are
/// the old app's, so they arrive at the old app's times, whatever the new cooldown would have waited.
@Suite struct ReplayTests {
    struct Line {
        let time: Double
        let message: String
    }

    static func load(_ name: String) throws -> [Line] {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "log", subdirectory: "Fixtures"))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        var lines: [Line] = []
        var origin: Date?
        for raw in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") where !raw.hasPrefix("#") {
            let stamp = String(raw.prefix(23))
            guard let date = formatter.date(from: stamp) else { continue }
            origin = origin ?? date
            lines.append(Line(time: date.timeIntervalSince(origin!), message: String(raw.dropFirst(24))))
        }
        return lines
    }

    /// Feeds a log to the reducer and returns the link's trace, one string per event that matters.
    static func replay(_ name: String) throws -> (trace: [String], harnesses: [LinkHarness]) {
        var harnesses: [LinkHarness] = []
        var h = LinkHarness()
        var trace: [String] = []
        let target = PumpTarget(
            peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode))

        func record(_ h: inout LinkHarness) {
            for effect in h.last {
                switch effect {
                case .emit(.ready): trace.append("ready")
                case .emit(.disconnected(let reason, let span)):
                    trace.append("closed \(describe(reason)) held=\(span.held) flaps=\(span.flapsAfter)")
                case .emit(.connectionUnstable(let flaps)): trace.append("unstable \(flaps)")
                case .emit(.connectionRestored): trace.append("restored")
                case .transport(.cancelConnection): trace.append("cancel")
                default: break
                }
            }
            h.last = []
        }

        for line in try load(name) {
            if line.message == "launch" {
                if h.state.target != nil { harnesses.append(h) }
                h = LinkHarness()
                h.now = line.time
                trace.append("launch")
                h.apply(.power(.poweredOn))
                h.apply(.connect(target, SupportMatrix()))
                continue
            }
            h.advance(by: line.time - h.now)
            record(&h)
            let m = line.message
            if m.hasPrefix("bg session armed (scenePhaseBackground)") {
                h.apply(.appActive(false))
            } else if m == "BLE state → discovering" {
                h.apply(.connected(peripheralID: LinkHarness.pumpID, name: nil))
            } else if m == "BLE state → ready", h.phase == .discovering {
                h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
                record(&h)
                for c in ServiceUUID.notificationCharacteristics {
                    h.apply(.subscription(c, isNotifying: true, failed: false))
                    record(&h)
                }
            } else if m.hasPrefix("pairing send → CentralChallengeRequest") {
                h.apply(
                    .authenticationRequest(
                        CentralChallengeRequest(appInstanceId: 0, centralChallenge: [UInt8](repeating: 0, count: 8))))
            } else if m == "pairing outcome → paired" {
                h.apply(.authenticated(key: LinkHarness.key, derivedSecret: nil))
            } else if m.hasPrefix("read recv ← opcode="), let op = UInt8(m.dropFirst(19).prefix { $0.isNumber }),
                let reply = handshakeReply(to: h, opCode: op)
            {
                h.reply(reply)
            } else if m.hasPrefix("disconnect domain=CBErrorDomain code="),
                let code = Int(m.dropFirst(37).prefix { $0.isNumber })
            {
                h.apply(
                    .disconnected(peripheralID: LinkHarness.pumpID, BluetoothError(domain: "CBErrorDomain", code: code))
                )
            }
            record(&h)
        }
        harnesses.append(h)
        return (trace, harnesses)
    }

    /// The pump's answer to the handshake read on the wire, if `opCode` is its reply.
    static func handshakeReply(to h: LinkHarness, opCode: UInt8) -> (any Message)? {
        guard h.phase == .handshaking, let wire = h.lastWrite, wire.characteristic == .currentStatus else { return nil }
        switch (wire.opCode, opCode) {
        case (ApiVersionRequest.props.opCode, ApiVersionResponse.props.opCode):
            return ApiVersionResponse(cargo: le16(2) + le16(5))
        case (PumpVersionRequest.props.opCode, PumpVersionResponse.props.opCode):
            return PumpVersionResponse(cargo: pumpVersionCargo(LinkHarness.p1Unit))
        case (TimeSinceResetRequest.props.opCode, TimeSinceResetResponse.props.opCode):
            return TimeSinceResetResponse(cargo: le32(586_961_779) + le32(1_000))
        default:
            return nil
        }
    }

    static func describe(_ reason: DisconnectReason) -> String {
        switch reason {
        case .linkLost(let error): return "linkLost \(error.map { String($0.code) } ?? "-")"
        default: return String(describing: reason)
        }
    }

    static func cycle(_ flaps: Int) -> [String] { ["ready", "closed linkLost 7 held=false flaps=\(flaps)"] }

    @Test func firstLogFlapsAndNeverStops() throws {
        let (trace, harnesses) = try Self.replay("p1-reconnect-loop-1")
        // Two launches where the pump never connected, then the loop: all 18 of the 2 s flaps the old
        // app saw, the unstable report at the third, and every connection the pump completes is set up.
        var expected = ["launch", "launch", "launch"]
        for flaps in 1...18 {
            expected += Self.cycle(flaps)
            if flaps == 3 { expected.append("unstable 3") }
        }
        #expect(trace == expected)
        try Self.checkOnlyHandshakeReads(harnesses)
    }

    @Test func secondLogFlapsUntilTheLogEnds() throws {
        let (trace, harnesses) = try Self.replay("p1-reconnect-loop-2")
        var expected = ["launch"]
        for flaps in 1...7 {
            expected += Self.cycle(flaps)
            if flaps == 3 { expected.append("unstable 3") }
        }
        #expect(trace == expected)
        try Self.checkOnlyHandshakeReads(harnesses)
    }

    /// After pairing, nothing but ApiVersion, PumpVersion and TimeSinceReset ever went out, and
    /// every connect paired with a disconnect.
    static func checkOnlyHandshakeReads(_ harnesses: [LinkHarness]) throws {
        let handshake: Set<UInt8> = [32, 84, 54]
        for h in harnesses {
            let reads = h.writes.filter { $0.characteristic != .authorization }
            #expect(reads.allSatisfy { handshake.contains($0.opCode) })
            let t = h.state.telemetry
            #expect(t.connects == t.disconnects + (h.state.connection == nil ? 0 : 1))
        }
    }
}
