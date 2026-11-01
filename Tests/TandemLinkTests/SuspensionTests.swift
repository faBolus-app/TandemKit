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
    let target = PumpTarget(peripheralID: LinkHarness.pumpID, model: .tslim, credentials: .legacy(code: LinkHarness.legacyCode))

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
                return m.recorded.values.contains { $0.values.contains { $0.contains { $0.result == .droppedAfterError } } }
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
}
