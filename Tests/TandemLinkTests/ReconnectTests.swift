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

    @Test func dropAfterHeldLinkWaitsTheBaseCooldown() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        // As t:connect waits after a connection error, a held drop included.
        #expect(h.phase == .backingOff)
        #expect(!h.commands.contains(.connect(Self.id)))
        #expect(h.timers[.backoff] == h.now + 1)
        #expect(h.state.ladder.flaps == 1)
        let span = h.state.telemetry.spans.last
        #expect(span?.held == true && span?.authenticated == true)
        #expect(span?.reason == .linkLost(drop))
        h.advance(by: 1)
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
    }

    @Test func supervisionTimeoutWaitsThreeSeconds() {
        // The drop at the edge of range: t:connect's base for a link-layer timeout.
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 60)
        h.apply(.disconnected(peripheralID: Self.id, BluetoothError(domain: "CBErrorDomain", code: 6)))
        #expect(h.timers[.backoff] == h.now + 3)
    }

    @Test func failedConnectWaitsTenSeconds() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.timers[.backoff] == h.now + 10)
        h.advance(by: 10)
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.timers[.backoff] == h.now + 20)
        h.advance(by: 20)
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.timers[.backoff] == h.now + 30, "capped")
    }

    @Test func outOfRangeAndBackRecoversThroughThePendingConnect() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 60)
        h.apply(.appActive(false))
        h.apply(.disconnected(peripheralID: Self.id, drop))
        // No background time held the cooldown: the pending connect goes out now, with the cooldown's
        // 1 s as its start delay.
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.delayedConnect(Self.id, startDelay: 1)])
        h.sleep(for: 300)  // out of range for 5 minutes, app suspended
        #expect(h.phase == .connecting)
        h.connectAndAuthenticate()
        h.answerHandshake()
        #expect(h.phase == .ready)
        #expect(h.state.telemetry.lastReconnectDuration == 300)
    }

    // MARK: flaps

    @Test func dropBeforeHoldIsAFlapThatBacksOff() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 2)  // P1 drops about 2 s after pairing
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 1)
        #expect(h.phase == .backingOff)
        #expect(!h.commands.contains(.connect(Self.id)))
        #expect(h.timers[.backoff] == h.now + 1)
        h.advance(by: 1)
        #expect(h.phase == .connecting)
        #expect(connects(h) == 2)
    }

    /// Synthetic: a pump that accepts and drops every connection is retried forever, the wait doubling
    /// from 1 s to the 30 s cap, and the unstable alert is raised once.
    @Test func flappingPeerIsRetriedForeverDoublingToTheCap() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        var delays: [Double] = []
        for _ in 0..<20 {
            h.connectAndAuthenticate()
            h.answerHandshake()
            h.advance(by: 2)
            h.apply(.disconnected(peripheralID: Self.id, drop))
            if let due = h.timers[.backoff] { delays.append(due - h.now) }
            h.advance(by: 30)
            #expect(h.phase == .connecting)
        }
        #expect(delays == [1, 2, 4, 8, 16] + Array(repeating: 30, count: 15))
        #expect(
            h.allEvents.filter { if case .connectionUnstable = $0 { return true } else { return false } }.count == 1)
        #expect(connects(h) == 21)
    }

    @Test func lateCompletionAfterStopIsCancelled() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.stop)
        h.apply(.connected(peripheralID: Self.id, name: "tslim X2 ***693"))
        #expect(h.commands == [.cancelConnection(Self.id)])
        #expect(h.phase == .idle)
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
        h.advance(by: 10)
        h.apply(.peripheralUnavailable(Self.id))
        #expect(h.phase == .scanning(forPairing: false))
        h.apply(.discovered(peripheralID: Self.id, name: "tslim X2 ***693", rssi: -40))
        #expect(h.state.ladder.flaps == 1)
    }

    // MARK: background

    @Test func backgroundFlapCarriesTheRestOfTheCooldownAsAStartDelay() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.appActive(false))
        h.advance(by: 2)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.phase == .backingOff)
        #expect(h.state.ladder.flaps == 1)
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.delayedConnect(Self.id, startDelay: 1)])
        #expect(h.timers[.backoff] == nil)
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 1, "still counted")
    }

    @Test func theStartDelayIsWholeSecondsAndAtLeastOne() {
        // CoreBluetooth fails a fractional start delay with invalidParameters.
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // 10 s
        h.sleep(for: 0.7)
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.delayedConnect(Self.id, startDelay: 10)], "9.3 s left, rounded up")
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // 20 s
        h.sleep(for: 19.8)
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.delayedConnect(Self.id, startDelay: 1)], "0.2 s left, at least 1 s")
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // 30 s
        h.sleep(for: 31)
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.connect(Self.id)], "the cooldown already passed")
    }

    @Test func aForegroundCooldownNeverUsesAStartDelay() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)  // a late callback: the timer runs in the foreground
        #expect(h.commands.isEmpty)
        #expect(h.phase == .backingOff)
        h.advance(by: 1)
        #expect(h.commands == [.connect(Self.id)])
        #expect(!h.allCommands.contains { if case .delayedConnect = $0 { return true } else { return false } })
    }

    @Test func aDelayedConnectThatFailsIsAFlap() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 2)
        #expect(h.state.telemetry.failedConnects == 2)
        #expect(h.phase == .backingOff)
        #expect(h.timers[.backoff] == h.now + 20)
    }

    @Test func aDelayedConnectThatCompletesConnects() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.sleep(for: 10)
        h.connectAndAuthenticate()
        h.answerHandshake()
        #expect(h.phase == .ready)
        #expect(h.state.backoffUntil == nil && !h.state.pendingConnectDelayed)
    }

    @Test func invalidParametersFallsBackToAPlainConnectAndIsRemembered() {
        let invalidParameters = BluetoothError(domain: "CBErrorDomain", code: 1)
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.delayedConnect(Self.id, startDelay: 10)])
        h.apply(.connectFailed(peripheralID: Self.id, invalidParameters))
        #expect(h.commands == [.connect(Self.id)], "the option is unsupported: connect plain, at once")
        #expect(h.phase == .connecting)
        #expect(h.state.ladder.flaps == 1, "not a flap")
        #expect(h.state.telemetry.failedConnects == 1)
        #expect(h.timers[.backoff] == nil, "no cooldown")
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        #expect(h.commands == [.connect(Self.id)], "no start delay is tried again")
    }

    @Test func invalidParametersOnAPlainConnectIsAFailure() {
        // Only a delayed connect's invalidParameters means the option; otherwise a connect failing at once
        // could loop with no cooldown.
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, BluetoothError(domain: "CBErrorDomain", code: 1)))
        #expect(h.state.ladder.flaps == 1)
        #expect(h.phase == .backingOff)
    }

    @Test func stopCancelsADelayedConnect() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.apply(.stop)
        #expect(h.commands == [.cancelConnection(Self.id)])
        #expect(h.phase == .idle)
        #expect(!h.state.pendingConnectDelayed && h.state.backoffUntil == nil)
    }

    @Test func aFailureAnsweringTheLinksOwnCancelIsNotCounted() {
        var h = backgroundTarget()
        h.apply(.stop)  // cancels the pending connect
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // the cancelled connect's answer
        #expect(h.state.ladder.flaps == 0)
        #expect(h.commands == [.connect(Self.id)], "issued again, in case it was the new connect's")
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 1, "only the first one after the cancel is taken as its answer")
    }

    @Test func bluetoothOffCancelsADelayedConnect() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.apply(.power(.poweredOff))
        #expect(h.commands == [.cancelPendingConnect(Self.id)])
        #expect(h.phase == .waitingForBluetooth)
        h.apply(.power(.poweredOn))
        #expect(h.commands == [.connect(Self.id)], "back on, it connects afresh")
    }

    @Test func comingToTheForegroundCancelsTheDelayAndRunsTheTimerForTheRest() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // 10 s
        h.apply(.backgroundTimeEnding)
        h.sleep(for: 4)
        h.apply(.appActive(true))
        #expect(h.commands == [.cancelPendingConnect(Self.id)])
        #expect(h.phase == .backingOff)
        #expect(h.timers[.backoff] == h.now + 6)
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // answering the cancel, while backing off
        #expect(h.state.ladder.flaps == 1)
        h.advance(by: 6)
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
    }

    @Test func comingToTheForegroundAfterTheDelayRanOutReissuesThePendingConnect() {
        // The delay is over, so the connect is pending like any other: reissued, not cancelled, so a
        // cancel and a connect never cross.
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.sleep(for: 60)  // the pump is out of range; the delayed connect is pending
        h.apply(.appActive(true))
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
        #expect(!h.state.pendingConnectDelayed)
    }

    @Test func aCancelsAnswerWhileBackingOffDoesntHideALaterFailure() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.sleep(for: 4)
        h.apply(.appActive(true))
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // the cancel's answer, while backing off
        h.advance(by: 6)
        #expect(h.commands == [.connect(Self.id)])
        h.apply(.connectFailed(peripheralID: Self.id, drop))  // the new connect really failing
        #expect(h.state.ladder.flaps == 2)
        #expect(h.phase == .backingOff)
    }

    @Test func aCancelNeverAnsweredDoesntHideALaterFailure() {
        var h = backgroundTarget()
        h.apply(.stop)
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.sleep(for: 60)
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 1, "long after the cancel, a failure is the pump's")
    }

    @Test func aConnectCompletingAsTheDelayIsCancelledIsKept() {
        var h = backgroundTarget()
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        h.apply(.backgroundTimeEnding)
        h.sleep(for: 4)
        h.apply(.appActive(true))
        #expect(h.phase == .backingOff)
        h.connectAndAuthenticate()  // its didConnect was already queued
        h.answerHandshake()
        #expect(h.phase == .ready)
        #expect(h.timers[.backoff] == nil)
    }

    @Test func aRestoredSetupThatDropsReconnectsAtOnceInTheBackground() {
        var h = LinkHarness()
        h.apply(.appActive(false))
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: true, name: "tslim X2 ***693")]))
        h.apply(.power(.poweredOn))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        #expect(h.phase == .discovering)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.commands.contains(.connect(Self.id)))
        #expect(h.phase == .connecting)
    }

    /// A pump that won't connect, the app in the background.
    func backgroundTarget() -> LinkHarness {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.appActive(false))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        return h
    }

    @Test func backgroundTimeEndingOutsideACooldownDoesNothing() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.backgroundTimeEnding)
        #expect(h.phase == .ready)
        #expect(h.commands.isEmpty)
    }

    @Test func backgroundFlapsNeverStop() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.appActive(false))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        var delays: [Int] = []
        for _ in 0..<20 {
            h.apply(.connectFailed(peripheralID: Self.id, drop))
            h.apply(.backgroundTimeEnding)
            if case .delayedConnect(Self.id, let delay) = h.commands.last { delays.append(delay) }
        }
        #expect(h.phase == .connecting)
        #expect(connects(h) == 1)
        // Each connect waits out its cooldown in the system, doubling to the cap, as in the foreground.
        #expect(delays == [10, 20] + Array(repeating: 30, count: 18))
    }

    @Test func goingToTheBackgroundDuringBackoffKeepsTheCooldown() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.phase == .backingOff)
        h.apply(.appActive(false))
        #expect(h.commands.isEmpty)
        #expect(h.timers[.backoff] != nil)
        h.advance(by: 1)
        #expect(h.phase == .connecting)
    }

    @Test func comingToTheForegroundReissuesAPendingConnect() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.appActive(false))
        h.apply(
            .connect(
                PumpTarget(peripheralID: Self.id, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode)),
                SupportMatrix()))
        h.apply(.appActive(true))
        #expect(h.commands == [.connect(Self.id)])
        #expect(connects(h) == 2)
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
        #expect(h.commands == [.discover(LinkHarness.pumpID), .readDeviceInformation])
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
        #expect(h.phase == .backingOff)  // the base cooldown, held or not
        h.advance(by: 1)
        #expect(h.phase == .connecting)
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
        #expect(t.spans.map(\.flapsAfter) == [1, 2], "a held drop counts toward the cooldown too")
    }
}
