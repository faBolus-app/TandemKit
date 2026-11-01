import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// Timers don't fire while iOS has the app suspended. What a timer would have decided (the link held,
/// a settle window passed) must still be decided by the time the next thing happens, as of when the
/// timer was due. Also the review fixes around the ladder, write failures and the request gates.
@Suite struct SuspensionTests {
    static let id = LinkHarness.pumpID
    let drop = BluetoothError(domain: "CBErrorDomain", code: 7)
    let target = PumpTarget(
        peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode))

    @Test func linkThatHeldWhileSuspendedIsAHeldDropNotAFlap() {
        var h = LinkHarness()
        h.apply(.appActive(false))
        for _ in 0..<12 {  // more drops than the ladder allows flaps
            h.makeReady()
            h.sleep(for: 3_600)  // suspended before the hold timer could fire
            h.apply(.disconnected(peripheralID: Self.id, drop))
            #expect(h.state.ladder.flaps == 0)
            #expect(h.state.telemetry.spans.last?.held == true)
            #expect(h.phase == .connecting)
        }
        #expect(!h.allEvents.contains { if case .connectionUnstable = $0 { return true } else { return false } })
    }

    @Test func dropLongAfterAnOp77IsNotTiedToIt() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.appActive(false))
        let probe = h.submit(LoadStatusRequest())
        h.replyError(code: 0)
        h.sleep(for: 1_200)  // suspended: the settle timer never ran
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.telemetry.spans.last?.reason == .linkLost(drop))
        let struck = h.allEvents.contains {
            if case .supportMatrixChanged(let m) = $0 {
                return m.recorded.values.contains {
                    $0.values.contains { $0.contains { $0.result == .droppedAfterError } }
                }
            }
            return false
        }
        #expect(!struck)
        #expect(h.results[probe] != nil)
    }

    @Test func secondFailureOfAMultiPacketWriteDoesNotHitTheNextRequest() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        let first = h.submit(BolusPermissionRequest(), allowing: .delivery)
        let firstTx = h.lastWrite!.txId
        let second = h.submit(CancelBolusRequest(bolusId: 1), allowing: .delivery)
        h.apply(.writeFailed(.control, txId: firstTx))
        #expect(h.results[first] == .unknown(.writeFailed))
        #expect(h.writes(of: CancelBolusRequest.self) == 1)
        h.apply(.writeFailed(.control, txId: firstTx))  // the same request's second packet
        #expect(h.results[second] == nil)
    }

    @Test func foregroundReissuesAPendingConnect() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.appActive(false))
        h.apply(.appActive(true))
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
    }

    @Test func connectingAgainDoesNotSkipTheBackoff() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        for _ in 0..<3 {
            h.apply(.connectFailed(peripheralID: Self.id, drop))
            h.apply(.connect(target, SupportMatrix()))
            #expect(h.phase == .backingOff)
            #expect(h.commands.isEmpty)
            h.advance(by: 60)
        }
        #expect(h.state.ladder.flaps == 3)
    }

    @Test func cancelledProbesOp77StillStopsProbing() {
        var h = LinkHarness()
        h.makeReady(api: (4, 0), unit: LinkHarness.p2Unit)
        h.advance(by: 10)
        let a = h.submit(CurrentBatteryV2Request())
        let b = h.submit(ControlIQIOBRequest())
        h.apply(.cancel(a))
        h.replyError(code: 0)
        h.advance(by: 1)
        #expect(h.results[b] == .notSent(.probeStopped))
    }

    @Test func backoffCarriesJitter() {
        var h = LinkHarness()
        h.jitter = 0.5
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.timers[.backoff] == h.now + 5 * 1.25)
    }

    @Test func emptyBackoffDoesNotTrap() {
        var config = LinkConfiguration()
        config.backoff = []
        var h = LinkHarness(config: config)
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.phase == .backingOff)
    }

    @Test func neverAllowedWriteIsReportedSoEvenWhenNotReady() {
        var h = LinkHarness()
        let id = h.submit(ChangeTimeDateRequest(tandemEpochTime: 0), allowing: .delivery)
        #expect(h.results[id] == .notSent(.signedWriteNotAllowed))
        let blocked = h.submit(CancelBolusRequest(bolusId: 1))
        #expect(h.results[blocked] == .notSent(.writeBlocked(CancelBolusRequest().operationRisk)))
    }

    @Test func retestWhileDisconnectedForgetsTheLastUnitsEvidence() {
        var h = LinkHarness()
        h.makeReady(api: (4, 0), unit: LinkHarness.p2Unit)
        h.advance(by: 10)
        _ = h.submit(LoadStatusRequest())
        h.replyError(code: 6)
        h.advance(by: 1)
        h.apply(.stop)
        h.apply(.retest(MessageKey(LoadStatusRequest.self)))
        #expect(h.state.support.recorded[LinkHarness.p2Unit]?[MessageKey(LoadStatusRequest.self)] == nil)
    }

    @Test func queuedCopyOfACommandJustRejectedIsNeverSent() {
        var h = LinkHarness()
        h.makeReady()
        let first = h.submit(LastBolusStatusV2Request())
        let second = h.submit(LastBolusStatusV2Request())
        h.replyError(code: 6)
        h.advance(by: 1)
        #expect(h.results[second] == .notSent(.unsupported))
        #expect(h.writes(of: LastBolusStatusV2Request.self) == 1)
        #expect(h.results[first] != nil)
    }

    @Test func connectingAgainKeepsTheMatrixTheLinkRecorded() {
        var h = LinkHarness()
        h.makeReady()
        _ = h.submit(LastBolusStatusV2Request())
        h.replyError(code: 6)
        h.advance(by: 1)
        h.apply(.connect(target, SupportMatrix()))  // the caller's older copy
        let id = h.submit(LastBolusStatusV2Request())
        #expect(h.results[id] == .notSent(.unsupported))
    }

    @Test func dropWhileSettingUpARestoredLinkIsNotAFlap() {
        var h = LinkHarness()
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: true, name: "tslim X2 ***693")]))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.power(.poweredOn))
        #expect(h.phase == .discovering)  // adopted, not reconnected
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 0)
        #expect(h.commands.contains(.connect(Self.id)))
    }

    @Test func resettingForgetsRestoredPeripherals() {
        // Below poweredOff every peripheral object is invalid, the restored link included.
        var h = LinkHarness()
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: true, name: nil)]))
        h.apply(.power(.resetting))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.power(.poweredOn))
        #expect(h.commands == [.connect(Self.id)])
    }

    @Test func restoredLinkThatDroppedBeforeTheTargetIsKnownIsReconnectedNotAdopted() {
        var h = LinkHarness()
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: true, name: nil)]))
        h.apply(.power(.poweredOn))
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.apply(.connect(target, SupportMatrix()))
        #expect(h.commands == [.connect(Self.id)])
        #expect(h.phase == .connecting)
    }

    @Test func restoredConnectThatCompletesBeforeTheTargetIsKnownIsAdopted() {
        var h = LinkHarness()
        h.apply(.restored([RestoredPeripheral(peripheralID: Self.id, isConnected: false, name: nil)]))
        h.apply(.power(.poweredOn))
        h.apply(.connected(peripheralID: Self.id, name: "tslim X2 ***693"))
        #expect(h.commands.isEmpty)  // not cancelled
        h.apply(.connect(target, SupportMatrix()))
        #expect(h.phase == .discovering)
    }

    @Test func linkStartsAssumingTheBackground() {
        // An app relaunched in the background may never be told it's in the background.
        var h = LinkHarness()
        h.state.appActive = LinkState().appActive
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connectFailed(peripheralID: Self.id, drop))
        #expect(h.commands.contains(.connect(Self.id)))
        #expect(h.phase == .connecting)
    }

    @Test func lateOp77DoesNotAnswerTheNextSignedWriteWhenTheModelIsUnknown() {
        var h = LinkHarness()
        h.makeReady(model: nil, name: nil)
        h.advance(by: 10)
        let first = h.submit(BolusPermissionRequest(), allowing: .delivery, deadline: 5)
        let firstTx = h.lastWrite!.txId
        h.advance(by: 5)
        #expect(h.results[first] == .unknown(.timedOut))
        let second = h.submit(BolusPermissionRequest(), allowing: .delivery)
        h.notify(ControlError(cargo: [0, 3]), txId: firstTx, signedAt: 586_961_779 + 15)
        h.advance(by: 1)
        #expect(h.results[second] == nil)
    }

    @Test func optionalCharacteristicThatWontSubscribeRefusesItsRequests() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: Self.id, name: "tslim X2 ***693"))
        h.apply(.characteristicsDiscovered(Set(Characteristic.allCases)))
        h.apply(.subscription(.control, isNotifying: false, failed: true))
        for c in ServiceUUID.notificationCharacteristics where c != .control {
            h.apply(.subscription(c, isNotifying: true, failed: false))
        }
        h.apply(.authenticated(key: LinkHarness.key, derivedSecret: nil))
        h.answerHandshake()
        h.advance(by: 10)
        let id = h.submit(BolusPermissionRequest(), allowing: .delivery)
        #expect(h.results[id] == .notSent(.characteristicUnavailable))
    }

    @Test func failedSubscriptionWhileReadyIsRestored() {
        var h = LinkHarness()
        h.makeReady()
        h.apply(.subscription(.currentStatus, isNotifying: false, failed: true))
        #expect(h.commands == [.subscribe(.currentStatus)])
        #expect(h.timers[.resubscribe] != nil)
        #expect(h.state.connection?.subscribed.contains(.currentStatus) == false)
    }

    @Test func invalidatedServiceEndsTheConnection() {
        var h = LinkHarness()
        h.makeReady()
        h.advance(by: 10)
        h.apply(.servicesInvalidated)
        #expect(h.commands.contains(.cancelConnection(Self.id)))
        #expect(h.state.telemetry.spans.last?.reason == .servicesInvalidated)
    }

    @Test func probeThatDrewAnOp77IsNotSentAgain() {
        var h = LinkHarness()
        h.makeReady(api: (4, 0), unit: LinkHarness.p2Unit)
        h.advance(by: 10)
        let id = h.submit(CurrentBatteryV2Request())
        h.replyError(code: 0)
        h.advance(by: 1)
        #expect(h.writes(of: CurrentBatteryV2Request.self) == 1)
        guard case .pumpError = h.results[id] else {
            Issue.record("expected the pump's error")
            return
        }
    }

    @Test func oneRetryMeansAtMostTwoSends() {
        var h = LinkHarness()
        h.makeReady()
        _ = h.submit(CurrentBatteryV1Request())
        h.replyError(code: 2)
        h.advance(by: 1)
        h.replyError(code: 0)
        h.advance(by: 1)
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 2)
    }

    @Test func cancelledRetryReportsThePumpsAnswer() {
        var h = LinkHarness()
        h.makeReady()
        _ = h.submit(InsulinStatusRequest())  // keeps the wire busy so the retry stays queued
        let id = h.submit(CurrentBatteryV1Request())
        h.reply(InsulinStatusResponse(cargo: [10, 0, 0, 0]))
        h.replyError(code: 2)
        h.advance(by: 0.5)
        h.apply(.cancel(id))
        guard case .pumpError = h.results[id] else {
            Issue.record("it reached the pump; expected its answer, got \(String(describing: h.results[id]))")
            return
        }
    }

    @Test func connectingAgainMergesANewerMatrix() {
        var h = LinkHarness()
        h.makeReady(api: (4, 0), unit: LinkHarness.p2Unit)
        var loaded = SupportMatrix()
        loaded.record(.unsupported, for: MessageKey(LoadStatusRequest.self), on: LinkHarness.p2Unit, note: "stored")
        h.apply(.connect(target, loaded))
        h.advance(by: 10)
        let id = h.submit(LoadStatusRequest())
        #expect(h.results[id] == .notSent(.unsupported))
    }

    @Test func cancelledSignedWritesAuthenticatedAnswerIsReported() {
        var h = LinkHarness()
        h.makeReady()
        let id = h.submit(BolusPermissionRequest(), allowing: .delivery)
        h.apply(.cancel(id))
        h.reply(BolusPermissionResponse(cargo: [0, 1, 0, 0, 0, 0]), signedAt: 586_961_779 + 2)
        let answered = h.events.contains {
            if case .cancelledRequestAnswered(id, .reply) = $0 { return true } else { return false }
        }
        #expect(answered)
    }

    @Test func qualifyingEventsAreNotClearedBeforeReady() {
        var h = LinkHarness()
        h.apply(.power(.poweredOn))
        h.apply(.connect(target, SupportMatrix()))
        h.apply(.connected(peripheralID: Self.id, name: "tslim X2 ***693"))
        h.apply(.notified(.qualifyingEvents, [1, 0, 0, 0]))
        #expect(h.events == [.qualifyingEvents(.alert)])
        #expect(h.commands.isEmpty)
    }
}
