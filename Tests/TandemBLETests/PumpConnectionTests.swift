import Foundation
import Testing
import TandemLink
import TandemMessages
@testable import TandemBLE

/// The driver over a scripted CoreBluetooth stand-in: suspension, a kill and relaunch with state
/// restoration, Bluetooth off and on, and the pump out of range and back. Each must come back to ready
/// with nothing from the user.
@MainActor
@Suite struct PumpConnectionTests {
    let target = PumpTarget(peripheralID: ScriptedPump.id, model: .tslim, credentials: .legacy(code: ScriptedPump.code))

    struct Rig {
        let pump: ScriptedPump
        let clock: ManualClock
        let transport: ScriptedTransport
        let connection: PumpConnection
        var events: [LinkEvent] { log.events }
        let log: EventLog
    }

    final class EventLog {
        var events: [LinkEvent] = []
    }

    func rig(pump: ScriptedPump = ScriptedPump(), clock: ManualClock = ManualClock(), restoring: Bool = false) -> Rig {
        let transport = ScriptedTransport(pump: pump, clock: clock)
        let connection = PumpConnection(transport: transport, clock: clock)
        let log = EventLog()
        connection.observer = { log.events.append($0) }
        transport.start(restoring: restoring)
        return Rig(pump: pump, clock: clock, transport: transport, connection: connection, log: log)
    }

    @Test func pairsAuthenticatesAndAnswersARead() async {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        #expect(r.connection.state.phase == .ready)
        #expect(r.pump.writes.map(\.1) == [16, 18, 32, 84, 54])  // legacy pairing, then the three handshake reads
        let result = await r.connection.send(CurrentBatteryV1Request())
        guard case .reply(let reply) = result else {
            Issue.record("expected a reply, got \(result)")
            return
        }
        #expect((reply.message as? CurrentBatteryV1Response)?.currentBatteryAbc == 80)
    }

    @Test func signedWriteGoesOutOnceAndIsVerified() async {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        let result = await r.connection.send(BolusPermissionRequest(), allowing: .delivery)
        guard case .reply(let reply) = result else {
            Issue.record("expected a verified reply, got \(result)")
            return
        }
        #expect(reply.signedPumpTime != nil)
        #expect(r.pump.writes.filter { $0.1 == BolusPermissionRequest.props.opCode }.count == 1)
        let refused = await r.connection.send(BolusPermissionRequest())  // nothing granted this call
        #expect(refused == .notSent(.writeBlocked(BolusPermissionRequest().operationRisk)))
    }

    @Test func recoversInTheBackgroundWithNoTimerFiring() {
        // Suspended, a held link drops when the pump walks away; the pending connect completes when it
        // comes back, and authentication and the handshake run on the wake-ups alone.
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        r.clock.advance(by: 10)  // held
        r.connection.setAppActive(false)
        r.clock.suspended = true
        r.transport.pumpWalksAway()
        #expect(r.connection.state.phase == .connecting)
        r.clock.advance(by: 300)
        r.transport.pumpComesBack()
        #expect(r.connection.state.phase == .ready)
        #expect(r.connection.state.telemetry.lastReconnectDuration == 300)
    }

    @Test func flapWhileSuspendedStillReconnectsAndIsCounted() {
        let pump = ScriptedPump()
        let r = rig(pump: pump)
        r.connection.setAppActive(false)
        r.clock.suspended = true
        r.connection.connect(to: target, support: SupportMatrix())
        r.transport.drop()  // before the hold: a flap
        #expect(r.connection.state.ladder.flaps == 1)
        #expect(r.connection.state.phase == .ready)  // the pending connect completed at once
    }

    @Test func killAndRelaunchPicksUpTheRestoredLink() async {
        let pump = ScriptedPump()
        let clock = ManualClock()
        var first: Rig? = rig(pump: pump, clock: clock)
        first?.connection.connect(to: target, support: SupportMatrix())
        #expect(first?.connection.state.phase == .ready)
        first = nil  // iOS terminates the app; it keeps the link

        let relaunched = rig(pump: pump, clock: clock, restoring: true)
        relaunched.connection.connect(to: target, support: SupportMatrix())
        #expect(relaunched.connection.state.phase == .ready)
        // The restored link is adopted, not reconnected: no new connect was issued.
        #expect(!relaunched.transport.commands.contains(.connect(ScriptedPump.id)))
        let result = await relaunched.connection.send(CurrentBatteryV1Request())
        guard case .reply = result else {
            Issue.record("expected a reply, got \(result)")
            return
        }
    }

    @Test func forceQuitRelaunchReconnectsFromTheStoredTarget() {
        // A force quit isn't relaunched by iOS (TN3115) and drops the link; the user opens the app,
        // which connects from the stored pairing.
        let pump = ScriptedPump()
        let clock = ManualClock()
        var first: Rig? = rig(pump: pump, clock: clock)
        first?.connection.connect(to: target, support: SupportMatrix())
        first?.transport.drop()
        first = nil
        let relaunched = rig(pump: pump, clock: clock)
        relaunched.connection.connect(to: target, support: SupportMatrix())
        #expect(relaunched.connection.state.phase == .ready)
    }

    @Test func bluetoothOffAndOn() async {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        let pending = Task { await r.connection.send(CurrentBatteryV1Request(), deadline: 30) }
        await Task.yield()
        r.transport.bluetooth(on: false)
        #expect(r.connection.state.phase == .waitingForBluetooth)
        r.clock.advance(by: 120)
        r.transport.bluetooth(on: true)
        #expect(r.connection.state.phase == .ready)
        #expect(r.connection.state.ladder.flaps == 0)
        _ = await pending.value  // resumed, whatever the timing; never left hanging
    }

    @Test func outOfRangeForFiveMinutesAndBackInTheForeground() {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        r.clock.advance(by: 30)
        r.transport.pumpWalksAway()
        r.clock.advance(by: 300)
        #expect(r.connection.state.phase == .connecting)
        r.transport.pumpComesBack()
        #expect(r.connection.state.phase == .ready)
        let spans = r.connection.state.telemetry.spans
        #expect(
            spans.count == 1 && spans[0].held
                && spans[0].reason == .linkLost(BluetoothError(domain: "CBErrorDomain", code: 6)))
        #expect(r.events.contains { if case .disconnected = $0 { return true } else { return false } })
    }

    @Test func pumpThatDropsAfterEveryPairingIsThrottledThenStops() {
        let pump = ScriptedPump()
        pump.dropAfterPairing = 2  // as P1 does
        let r = rig(pump: pump)
        r.connection.connect(to: target, support: SupportMatrix())
        r.clock.advance(by: 3600)
        #expect(r.connection.state.phase == .exhausted)
        #expect(r.transport.commands.filter { $0 == .connect(ScriptedPump.id) }.count == 8)
        #expect(r.clock.pendingTimers == 0)
        // Coming to the foreground restarts it once (owner, 2026-10-31).
        r.connection.setAppActive(false)
        r.connection.setAppActive(true)
        #expect(r.transport.commands.filter { $0 == .connect(ScriptedPump.id) }.count == 9)
    }

    @Test func everyCallerIsResumedWhenTheLinkDrops() async {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        r.pump.silent = true
        let onTheWire = Task { await r.connection.send(CurrentBatteryV1Request(), deadline: 60) }
        let queued = Task { await r.connection.send(InsulinStatusRequest(), deadline: 60) }
        while r.pump.writes.last?.1 != CurrentBatteryV1Request.props.opCode { await Task.yield() }
        for _ in 0..<10 { await Task.yield() }
        r.transport.drop()
        #expect(await onTheWire.value == .unknown(.connectionLost))
        #expect(await queued.value == .notSent(.connectionLost))
    }

    @Test func cancelledCallerGetsAnAnswerAndTheLinkCarriesOn() async {
        let r = rig()
        r.connection.connect(to: target, support: SupportMatrix())
        let task = Task { await r.connection.send(CurrentBatteryV1Request()) }
        task.cancel()
        let result = await task.value
        #expect(result == .notSent(.cancelled) || { if case .reply = result { return true } else { return false } }())
        let next = await r.connection.send(CurrentBatteryV1Request())
        guard case .reply = next else {
            Issue.record("expected a reply, got \(next)")
            return
        }
    }
}
