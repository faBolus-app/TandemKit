import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// The four reconnect transitions, the ladder, Bluetooth power and the app's foreground state.
@Suite struct ReconnectTests {
    static let id = LinkHarness.pumpID
    let drop = BluetoothError(domain: "CBErrorDomain", code: 7)

    func connects(_ h: LinkHarness) -> Int { h.allCommands.filter { $0 == .connect(Self.id) }.count }

    // MARK: held drop

    @Test func dropAfterHeldLinkReconnectsAtOnceOffTheLadder() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        // The pending connect is issued in the same step, so it completes even while suspended.
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 0)
        let span = h.state.telemetry.spans.last
        #expect(span?.held == true && span?.authenticated == true)
        #expect(span?.reason == .linkLost(drop))
    }

    @Test func outOfRangeAndBackRecoversThroughThePendingConnect() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 60)
        h.apply(.appActive(false))
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.sleep(for: 300)  // out of range for 5 minutes, app suspended
        #expect(h.phase == .connecting)
        h.connectAndAuthenticate()
        h.answerHandshake()
        #expect(h.phase == .ready)
        #expect(h.state.telemetry.lastReconnectDuration == 300)
    }

    // MARK: flaps

    @Test func dropBeforeHoldIsAFlapThatBacksOffInTheForeground() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 2)  // P1 drops about 2 s after pairing
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 1)
        #expect(h.phase == .backingOff)
        #expect(!h.commands.contains(.connect(Self.id)))
        #expect(h.timers[.backoff] == h.now + 5)
        h.advance(by: 5)
        #expect(h.phase == .connecting)
        #expect(connects(h) == 2)
    }

    /// Synthetic: a pump that accepts and drops every connection climbs the ladder (5, 10, 20, 30 s)
    /// and stops after `maxFlaps`, raising the alert; it never loops.
    @Test func flappingPeerIsThrottledThenExhausted() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        var delays: [Double] = []
        for _ in 0..<8 {
            h.connectAndAuthenticate()
            h.answerHandshake()
            h.advance(by: 2)
            h.apply(.disconnected(peripheralID: Self.id, drop))
            if let due = h.timers[.backoff] { delays.append(due - h.now) }
            h.advance(by: 60)
        }
        #expect(delays == [5, 10, 20, 30, 30, 30, 30])
        #expect(h.phase == .exhausted)
        #expect(h.allEvents.contains(.connectionUnstable(flaps: 3)))
        #expect(
            h.allEvents.filter { if case .connectionUnstable = $0 { return true } else { return false } }.count == 1)
        #expect(connects(h) == 8)
        h.advance(by: 3600)
        #expect(connects(h) == 8)
    }

    @Test func exhaustedLadderCancelsThePendingConnectAndIgnoresLateCompletions() {
        var h = LinkHarness(
            config: {
                var c = LinkConfiguration()
                c.maxFlaps = 1
                return c
            }())
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.phase == .exhausted)
        #expect(h.commands.contains(.cancelConnection(Self.id)))
        h.apply(.connected(peripheralID: Self.id, name: "tslim X2 ***693"))
        #expect(h.commands == [.cancelConnection(Self.id)])
        #expect(h.phase == .exhausted)
    }

    @Test func ladderResetsOnlyAfterAnAuthenticatedHold() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.advance(by: 5)
        h.connectAndAuthenticate()
        h.answerHandshake()
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 2)  // reaching ready did not reset it
        h.advance(by: 10)
        h.connectAndAuthenticate()
        h.answerHandshake()
        h.advance(by: 10)
        #expect(h.state.ladder.flaps == 0)
    }

    @Test func connectionRestoredFollowsUnstableOnceTheLinkHolds() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        for _ in 0..<3 {
            h.apply(.connectFailed(peripheralID: Self.id, drop))
            h.advance(by: 30)
        }
        #expect(h.allEvents.contains(.connectionUnstable(flaps: 3)))
        h.connectAndAuthenticate()
        h.answerHandshake()
        h.advance(by: 10)
        #expect(h.allEvents.last == .connectionRestored)
    }

    @Test func rescanNeverResetsTheLadder() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.advance(by: 5)
        h.apply(.peripheralUnavailable(Self.id))
        h.apply(.discovered(peripheralID: Self.id, name: "tslim X2 ***693", rssi: -40))
        #expect(h.state.ladder.flaps == 1)
    }

    // MARK: background

    @Test func backgroundFlapIssuesThePendingConnectAtOnceAndCounts() {
        // Owner, 2026-10-31.
        var h = LinkHarness()
        h.makeReady()
        h.apply(.appActive(false))
        h.advance(by: 2)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.commands.contains(.connect(Self.id)))
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 1)
    }

    @Test func backgroundFlapsStillExhaust() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.appActive(false))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        for _ in 0..<8 { h.apply(.connectFailed(peripheralID: Self.id, drop)) }
        #expect(h.phase == .exhausted)
        #expect(connects(h) == 8)
    }

    @Test func goingToTheBackgroundDuringBackoffIssuesThePendingConnect() {
        // The backoff timer can't fire while suspended; waiting on it would strand the link.
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.phase == .backingOff)
        h.apply(.appActive(false))
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.timers[.backoff] == nil)
        #expect(h.state.ladder.flaps == 1)
    }

    @Test func foregroundRestartsAnExhaustedLadderOnce() {
        // Owner, 2026-10-31.
        var h = LinkHarness(
            config: {
                var c = LinkConfiguration()
                c.maxFlaps = 2
                return c
            }())
        h.apply(.power(.poweredOn))
        h.apply(.appActive(false))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.phase == .exhausted)
        h.apply(.appActive(true))
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 0)
        h.apply(.appActive(false))
        h.apply(.appActive(true))  // already reconnecting: the pending connect is reissued, not the ladder
        #expect(connects(h) == 4)
        #expect(h.state.ladder.flaps == 0)
    }

    // MARK: Bluetooth power

    @Test func bluetoothOffClosesTheLinkAndOnReconnectsWithoutClimbing() {
        var h = LinkHarness()
        h.makeReady()
        let id = h.submit(CurrentBatteryV1Request())
        h.apply(.power(.poweredOff))
        #expect(h.phase == .waitingForBluetooth)
        #expect(h.results[id] == .unknown(.connectionLost))
        #expect(h.state.telemetry.spans.last?.reason == .bluetoothUnavailable(.poweredOff))
        // didDisconnect may still arrive after the power-off: ignored.
        h.apply(.disconnected(peripheralID: Self.id, nil))
        #expect(h.state.telemetry.disconnects == 1)
        h.apply(.power(.poweredOn))
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.state.ladder.flaps == 0)
    }

    @Test func bluetoothOffDuringBackoffResumesOnPowerOn() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.apply(.power(.resetting))
        #expect(h.timers[.backoff] == nil)
        h.apply(.power(.poweredOn))
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 1)
    }

    // MARK: restoration

    @Test func relaunchAdoptsTheRestoredConnectionAndAuthenticatesAgain() {
        var h = LinkHarness()
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: true, name: "tslim X2 ***693")]))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        #expect(h.phase == .waitingForBluetooth)
        h.apply(.power(.poweredOn))
        #expect(h.phase == .discovering)
        #expect(h.commands == [.discover, .readDeviceInformation])
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        for c in ServiceUUID.notificationCharacteristics { h.apply(.subscription(c, isNotifying: true, failed: false)) }
        #expect(h.phase == .authenticating)
    }

    @Test func relaunchWithAPendingConnectReissuesIt() {
        var h = LinkHarness()
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(
            .restored([
                RestoredPeripheral(peripheralID: Self.id, isConnected: false, name: nil),
                RestoredPeripheral(
                    peripheralID: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, isConnected: true,
                    name: nil)
            ]))
        h.apply(.power(.poweredOn))
        #expect(h.commands.contains(.connect(Self.id)))
        #expect(h.commands.contains(.cancelConnection(UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!)))
        #expect(h.phase == .connecting)
    }

    // MARK: subscriptions

    @Test func droppedSubscriptionIsRestoredWithoutTouchingTheLink() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.subscription(.currentStatus, isNotifying: false, failed: false))
        #expect(h.commands == [.subscribe(.currentStatus)])
        let id = h.submit(CurrentBatteryV1Request())
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 0)  // its reply channel is down
        h.apply(.subscription(.currentStatus, isNotifying: true, failed: false))
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 1)
        #expect(h.timers[.resubscribe] == nil)
        #expect(h.results[id] == nil)
    }

    @Test func subscriptionThatDoesNotComeBackEndsTheConnection() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.subscription(.control, isNotifying: false, failed: false))
        h.advance(by: 30)
        #expect(h.allCommands.contains(.cancelConnection(Self.id)))
        #expect(h.state.telemetry.spans.last?.reason == .subscriptionLost(.control))
        #expect(h.phase == .connecting)  // it had held: reconnect at once
    }

    // MARK: telemetry

    @Test func everyConnectPairsWithItsDisconnectAndUptimeSumsClosedSpans() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 100)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.connectAndAuthenticate()
        h.answerHandshake()
        h.advance(by: 2)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        let t = h.state.telemetry
        #expect(t.connects == 2 && t.disconnects == 2 && t.spans.count == 2)
        #expect(t.closedUptime == 102)
        #expect(t.spans.map(\.held) == [true, false])
        #expect(t.spans.map(\.flapsAfter) == [0, 1])
    }
}
