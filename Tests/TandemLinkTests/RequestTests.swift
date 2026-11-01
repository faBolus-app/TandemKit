import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// The request queue: gates, one request in flight, txId matching, op-77 classification
///, careful probing, single-shot signed writes, and the signed-reply freshness check.
@Suite struct RequestTests {
    static let id = LinkHarness.pumpID
    static let pumpTime: UInt32 = 586_961_779
    let drop = BluetoothError(domain: "CBErrorDomain", code: 7)

    /// P2 (API 4.0): almost nothing has supported evidence, so most reads are untested there.
    func readyP2() -> LinkHarness {
        var h = LinkHarness()
        h.makeReady(api: (4, 0), unit: LinkHarness.p2Unit, pumpTime: Self.pumpTime)
        return h
    }

    func readyP1() -> LinkHarness {
        var h = LinkHarness()
        h.makeReady(pumpTime: Self.pumpTime)
        return h
    }

    // MARK: Gates

    @Test func notReadyIsRefusedWithoutSending() {
        var h = LinkHarness()
        let id = h.submit(CurrentBatteryV1Request())
        #expect(h.results[id] == .notSent(.notReady))
    }

    @Test func riskAboveWhatTheCallAllowsIsRefused() {
        var h = readyP1()
        let id = h.submit(CancelBolusRequest(bolusId: 1), allowing: .read)
        #expect(h.results[id] == .notSent(.writeBlocked(CancelBolusRequest().operationRisk)))
        #expect(h.writes(of: CancelBolusRequest.self) == 0)
    }

    @Test func signedWriteOutsideTheAllowedSixIsRefused() {
        var h = readyP1()
        let id = h.submit(ChangeTimeDateRequest(tandemEpochTime: 0), allowing: .delivery)
        #expect(h.results[id] == .notSent(.signedWriteNotAllowed))
    }

    @Test func modelRestrictedMessageNeedsAKnownModel() {
        var h = LinkHarness()
        h.makeReady(model: nil, name: nil)
        let id = h.submit(SetModesRequest(), allowing: .delivery)
        #expect(h.results[id] == .notSent(.signedWriteNotAllowed))
        let mobiOnly = h.submit(UnknownMobiOpcode110Request())
        #expect(h.results[mobiOnly] == .notSent(.identityUnknown))
    }

    // MARK: One in flight, txId

    @Test func oneRequestInFlightAndRepliesMatchByTxId() {
        var h = readyP1()
        let a = h.submit(CurrentBatteryV1Request())
        let b = h.submit(InsulinStatusRequest())
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 1)
        #expect(h.writes(of: InsulinStatusRequest.self) == 0)  // waits for the first reply
        let txA = h.lastWrite!.txId
        // A reply with the wrong txId isn't this request's: it's unsolicited.
        h.notify(CurrentBatteryV1Response(cargo: [50, 0]), txId: txA &+ 7)
        #expect(h.results[a] == nil)
        #expect(h.events.contains { if case .unsolicited = $0 { return true } else { return false } })
        h.reply(CurrentBatteryV1Response(cargo: [50, 0]))
        guard case .reply(let r) = h.results[a] else {
            Issue.record("no reply")
            return
        }
        #expect(r.txId == txA)
        #expect(h.writes(of: InsulinStatusRequest.self) == 1)
        #expect(h.lastWrite!.txId == txA &+ 1)
        h.reply(InsulinStatusResponse(cargo: [10, 0, 0, 0]))
        #expect(h.results[b] != nil)
    }

    @Test func timedOutReadIsUnknownAndFreesTheWire() {
        var h = readyP1()
        let a = h.submit(CurrentBatteryV1Request(), deadline: 5)
        let b = h.submit(InsulinStatusRequest(), deadline: 20)
        h.advance(by: 5)
        #expect(h.results[a] == .unknown(.timedOut))
        #expect(h.writes(of: InsulinStatusRequest.self) == 1)
        #expect(h.results[b] == nil)
    }

    @Test func cancelledRequestOnTheWireKeepsTheSlotUntilItsReply() {
        var h = readyP1()
        let a = h.submit(CurrentBatteryV1Request())
        let b = h.submit(InsulinStatusRequest())
        h.apply(.cancel(a))
        #expect(h.results[a] == .unknown(.cancelled))
        #expect(h.writes(of: InsulinStatusRequest.self) == 0)  // a late reply mustn't answer b
        h.reply(CurrentBatteryV1Response(cargo: [50, 0]))
        #expect(h.writes(of: InsulinStatusRequest.self) == 1)
        h.apply(.cancel(b))
        h.advance(by: 30)
        #expect(h.results.count == 2)
    }

    @Test func dropFailsQueuedAsNotSentAndInFlightAsUnknown() {
        var h = readyP1()
        let a = h.submit(CurrentBatteryV1Request())
        let b = h.submit(InsulinStatusRequest())
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.results[a] == .unknown(.connectionLost))
        #expect(h.results[b] == .notSent(.connectionLost))
    }

    // MARK: Support matrix

    @Test func unsupportedReadIsNeverSentTwiceToTheSamePump() {
        var h = readyP2()
        h.advance(by: 10)
        let first = h.submit(LoadStatusRequest())
        #expect(h.writes(of: LoadStatusRequest.self) == 1)
        h.replyError(code: 6, request: LoadStatusRequest.props.opCode)  // BAD_OPCODE
        h.advance(by: 1)
        guard case .pumpError(let e) = h.results[first] else {
            Issue.record("expected the pump's error")
            return
        }
        #expect(e.isBadOpcode)
        let changed = h.allEvents.compactMap {
            if case .supportMatrixChanged(let m) = $0 { return m } else { return nil }
        }.last
        #expect(
            changed?.entry(
                for: LoadStatusRequest(), unit: LinkHarness.p2Unit, model: .tslim,
                apiVersion: ApiVersion(major: 4, minor: 0)
            ).status == .unsupported)

        // Same connection, a later connection, and after a relaunch with the persisted matrix.
        let again = h.submit(LoadStatusRequest())
        #expect(h.results[again] == .notSent(.unsupported))
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.connectAndAuthenticate()
        h.answerHandshake(api: (4, 0), unit: LinkHarness.p2Unit)
        h.advance(by: 10)
        let later = h.submit(LoadStatusRequest())
        #expect(h.results[later] == .notSent(.unsupported))

        var relaunched = LinkHarness()
        relaunched.makeReady(api: (4, 0), unit: LinkHarness.p2Unit, support: changed!)
        relaunched.advance(by: 10)
        let afterRelaunch = relaunched.submit(LoadStatusRequest())
        #expect(relaunched.results[afterRelaunch] == .notSent(.unsupported))
        #expect(h.writes(of: LoadStatusRequest.self) == 1)
    }

    @Test func firmwareUpdateStartsTheUnitOver() {
        var h = readyP2()
        h.advance(by: 10)
        _ = h.submit(LoadStatusRequest())
        h.replyError(code: 6)
        h.advance(by: 1)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.connectAndAuthenticate()
        let updated = PumpUnit(serialNumber: 2000, armSoftwareVersion: 8, mspSoftwareVersion: 7)
        h.answerHandshake(api: (4, 0), unit: updated)
        h.advance(by: 10)
        let id = h.submit(LoadStatusRequest())
        #expect(h.results[id] == nil)
        #expect(h.writes(of: LoadStatusRequest.self) == 2)
    }

    // MARK: Probing

    @Test func probeNeverRunsInThePostPairingBurst() {
        var h = readyP2()
        let probe = h.submit(CurrentBatteryV2Request())  // untested on P2 (suspected)
        let known = h.submit(HistoryLogStatusRequest())  // supported on P2
        // The supported read goes first; the probe waits for the link to hold.
        #expect(h.writes(of: CurrentBatteryV2Request.self) == 0)
        #expect(h.writes(of: HistoryLogStatusRequest.self) == 1)
        h.reply(HistoryLogStatusResponse(cargo: [UInt8](repeating: 0, count: 12)))
        #expect(h.results[known] != nil)
        h.advance(by: 9.9)
        #expect(h.writes(of: CurrentBatteryV2Request.self) == 0)
        h.advance(by: 0.1)
        #expect(h.writes(of: CurrentBatteryV2Request.self) == 1)
        #expect(h.results[probe] == nil)
    }

    @Test func successfulProbesContinueInSequenceAndAreRecorded() {
        // Owner, 2026-10-31: probes run one after another after the hold; only an op-77 stops them.
        var h = readyP2()
        h.advance(by: 10)
        let a = h.submit(CurrentBatteryV2Request())
        let b = h.submit(ControlIQIOBRequest())
        h.reply(CurrentBatteryV2Response(cargo: [UInt8](repeating: 0, count: 11)))
        #expect(h.writes(of: ControlIQIOBRequest.self) == 1)
        h.reply(ControlIQIOBResponse(cargo: [UInt8](repeating: 0, count: 17)))
        #expect(h.results[a] != nil && h.results[b] != nil)
        let matrix = h.allEvents.compactMap {
            if case .supportMatrixChanged(let m) = $0 { return m } else { return nil }
        }.last
        #expect(
            matrix?.entry(
                for: ControlIQIOBRequest(), unit: LinkHarness.p2Unit, model: .tslim,
                apiVersion: ApiVersion(major: 4, minor: 0)
            ).status == .supported)
    }

    @Test func firstProbeErrorStopsProbingForTheConnection() {
        var h = readyP2()
        h.advance(by: 10)
        let a = h.submit(CurrentBatteryV2Request())
        let b = h.submit(ControlIQIOBRequest())
        let known = h.submit(HistoryLogStatusRequest())
        h.replyError(code: 6)
        h.advance(by: 1)
        #expect(h.results[b] == .notSent(.probeStopped))
        #expect(h.writes(of: HistoryLogStatusRequest.self) == 1)  // supported reads carry on
        #expect(h.results[known] == nil)
        let c = h.submit(InsulinStatusRequest())
        #expect(h.results[c] == .notSent(.probeStopped))
        #expect(h.results[a] != nil)
    }

    @Test func probeCausedDropDoesNotClimbTheLadder() {
        var h = readyP1()
        h.advance(by: 10)
        let probe = h.submit(LoadStatusRequest())  // suspected on P1 (T-1)
        h.replyError(code: 6, request: 0)
        h.advance(by: 0.09)  // on P1 the drop came about 90 ms later
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.ladder.flaps == 0)
        #expect(h.commands.contains(.connect(Self.id)))  // reconnect at once
        #expect(
            h.state.telemetry.spans.last?.reason
                == .afterUnsupportedRequest(MessageKey(LoadStatusRequest.self), errorCode: 6))
        guard case .pumpError = h.results[probe] else {
            Issue.record("the probe gets the pump's answer")
            return
        }
        #expect(!h.allEvents.contains { if case .connectionUnstable = $0 { return true } else { return false } })
    }

    /// P1 answers an unsupported command with `00 00` and drops. One such drop could be a fluke, so
    /// it takes two (owner, 2026-10-31) before the command is unsupported; neither climbs the ladder.
    @Test func errorZeroThenDropNeedsTwoStrikes() {
        var h = readyP1()
        let unsupported: (LinkHarness) -> SupportStatus? = { h in
            h.allEvents.compactMap { if case .supportMatrixChanged(let m) = $0 { return m } else { return nil } }.last?
                .entry(for: LoadStatusRequest(), unit: LinkHarness.p1Unit, model: .tslim, apiVersion: .v2_5).status
        }
        for strike in 1...2 {
            h.advance(by: 10)
            let probe = h.submit(LoadStatusRequest())
            #expect(h.results[probe] == nil)
            h.replyError(code: 0)
            h.advance(by: 0.09)
            h.apply(.disconnected(peripheralID: Self.id, drop))
            #expect(h.state.ladder.flaps == 0)
            #expect(unsupported(h) == (strike == 1 ? .untested : .unsupported))
            h.connectAndAuthenticate()
            h.answerHandshake()
        }
        h.advance(by: 10)
        let third = h.submit(LoadStatusRequest())
        #expect(h.results[third] == .notSent(.unsupported))
        #expect(h.writes(of: LoadStatusRequest.self) == 2)
    }

    @Test func dropOutsideTheSettleWindowIsUnrelated() {
        var h = readyP1()
        h.advance(by: 10)
        _ = h.submit(LoadStatusRequest())
        h.replyError(code: 0)
        h.advance(by: 1.5)  // the window passed with the link up
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.state.telemetry.spans.last?.reason == .linkLost(drop))
        let strikes = h.allEvents.contains {
            if case .supportMatrixChanged(let m) = $0 {
                return m.recorded[LinkHarness.p1Unit]?[MessageKey(LoadStatusRequest.self)]?.contains {
                    $0.result == .droppedAfterError
                } == true
            }
            return false
        }
        #expect(!strikes)
    }

    @Test func errorZeroFromP1DoesNotLoop() {
        // A read the class says works, answered with error 0 and no drop: one retry, then it sits out.
        var h = readyP1()
        let id = h.submit(CurrentBatteryV1Request())
        h.replyError(code: 0)
        h.advance(by: 1)
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 2)  // the bounded retry
        #expect(h.results[id] == nil)
        h.replyError(code: 0)
        h.advance(by: 1)
        guard case .pumpError = h.results[id] else {
            Issue.record("expected the pump's error")
            return
        }
        #expect(h.state.sittingOut.contains(MessageKey(CurrentBatteryV1Request.self)))
        for _ in 0..<5 {
            let again = h.submit(CurrentBatteryV1Request())
            #expect(h.results[again] == .notSent(.sittingOut))
        }
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 2)
    }

    @Test func transientErrorGetsABoundedRetry() {
        var h = readyP1()
        let id = h.submit(CurrentBatteryV1Request())
        h.replyError(code: 2)
        h.advance(by: 1)
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 2)
        h.replyError(code: 2)
        h.advance(by: 1)
        guard case .pumpError = h.results[id] else {
            Issue.record("expected the pump's error")
            return
        }
        #expect(h.writes(of: CurrentBatteryV1Request.self) == 2)
        #expect(!h.state.sittingOut.contains(MessageKey(CurrentBatteryV1Request.self)))
    }

    @Test func nothingIsSentDuringTheSettleWindow() {
        var h = readyP1()
        _ = h.submit(CurrentBatteryV1Request())
        _ = h.submit(InsulinStatusRequest())
        h.replyError(code: 6)
        #expect(h.writes(of: InsulinStatusRequest.self) == 0)
        h.advance(by: 0.5)
        #expect(h.writes(of: InsulinStatusRequest.self) == 0)
        h.advance(by: 0.5)
        #expect(h.writes(of: InsulinStatusRequest.self) == 1)
    }

    @Test func retestForgetsTheUnitsEvidence() {
        var h = readyP2()
        h.advance(by: 10)
        _ = h.submit(LoadStatusRequest())
        h.replyError(code: 6)
        h.advance(by: 1)
        h.apply(.retest(MessageKey(LoadStatusRequest.self)))
        // Probing stopped on this connection, so the retest runs on the next one.
        h.apply(.disconnected(peripheralID: Self.id, drop))
        h.connectAndAuthenticate()
        h.answerHandshake(api: (4, 0), unit: LinkHarness.p2Unit)
        h.advance(by: 10)
        let id = h.submit(LoadStatusRequest())
        #expect(h.results[id] == nil)
        #expect(h.writes(of: LoadStatusRequest.self) == 2)
    }

    // MARK: Signed writes

    func permission(_ h: inout LinkHarness) -> RequestID {
        h.submit(BolusPermissionRequest(), allowing: .delivery)
    }

    @Test func signedWriteIsSignedWithTheLastPumpTimeAndAcceptedWhenVerified() {
        var h = readyP1()
        let id = permission(&h)
        #expect(h.writes(of: BolusPermissionRequest.self) == 1)
        h.advance(by: 7)
        h.reply(BolusPermissionResponse(cargo: [0, 0x9A, 0x29, 0, 0, 0]), signedAt: Self.pumpTime + 7)
        guard case .reply(let r) = h.results[id] else {
            Issue.record("expected a reply")
            return
        }
        #expect(r.signedPumpTime == Self.pumpTime + 7)
        #expect((r.message as? BolusPermissionResponse)?.bolusId == 10650)
    }

    @Test func signedWriteIsNeverResent() {
        for ending in ["timeout", "drop", "error0", "transient", "unverified", "writeFailed"] {
            var h = readyP1()
            let id = permission(&h)
            switch ending {
            case "timeout": h.advance(by: 10)
            case "drop": h.apply(.disconnected(peripheralID: Self.id, drop))
            case "error0":
                h.replyError(code: 0, signedAt: Self.pumpTime)
                h.advance(by: 1)
            case "transient":
                h.replyError(code: 2, signedAt: Self.pumpTime)
                h.advance(by: 1)
            case "unverified":
                h.reply(UnsignedControlError(cargo: [0, 0]))
                h.advance(by: 1)
            default: h.apply(.writeFailed(.control, txId: nil))
            }
            if ending == "drop" {
                h.connectAndAuthenticate()
                h.answerHandshake()
            }
            h.advance(by: 120)
            #expect(h.writes(of: BolusPermissionRequest.self) == 1, "\(ending)")
            #expect(h.results[id] != nil, "\(ending)")
        }
    }

    @Test func onlyAuthenticatedAnswersAreDefinite() {
        var h = readyP1()
        let timedOut = permission(&h)
        h.advance(by: 10)
        #expect(h.results[timedOut] == .unknown(.timedOut))

        let dropped = permission(&h)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        #expect(h.results[dropped] == .unknown(.connectionLost))

        var u = readyP1()
        let unverified = permission(&u)
        u.notify(ControlError(cargo: [0, 0]), txId: u.lastWrite!.txId, signedAt: Self.pumpTime, key: [0xBA, 0xD0])
        #expect(u.results[unverified] == .unknown(.unverifiedError(.hmacMismatch)))

        var r = readyP1()
        let rejected = permission(&r)
        r.replyError(code: 3, signedAt: Self.pumpTime)
        r.advance(by: 1)
        guard case .pumpError(let e) = r.results[rejected] else {
            Issue.record("a verified op-77 is a reject")
            return
        }
        #expect(e.errorCodeId == 3)
    }

    @Test func replayedOldSignedReplyIsNotTakenAsThisOnesAnswer() {
        // An authentic reply from before this request (its trailer time is older) arrives with the txId
        // of the request on the wire, as a replay after the 8-bit txIds wrap would.
        var h = readyP1()
        h.advance(by: 600)
        let id = permission(&h)
        h.reply(BolusPermissionResponse(cargo: [0, 1, 0, 0, 0, 0]), signedAt: Self.pumpTime + 5)
        #expect(h.results[id] == .unknown(.staleSignedReply))

        var future = readyP1()
        let id2 = permission(&future)
        future.reply(BolusPermissionResponse(cargo: [0, 1, 0, 0, 0, 0]), signedAt: Self.pumpTime + 3_600)
        #expect(future.results[id2] == .unknown(.staleSignedReply))
    }

    @Test func signedWriteAfterAnHourUsesTheEstimatedPumpClock() {
        var h = readyP1()
        h.advance(by: 3_600)
        let id = permission(&h)
        h.reply(BolusPermissionResponse(cargo: [0, 1, 0, 0, 0, 0]), signedAt: Self.pumpTime + 3_602)
        guard case .reply = h.results[id] else {
            Issue.record("fresh reply refused")
            return
        }
    }

    @Test func untestedSignedWriteWaitsForTheHoldButIsNotAProbe() {
        // DismissNotification is untested on P1: it waits for the hold, and a probe that stopped
        // doesn't block it.
        var h = readyP1()
        let id = h.submit(DismissNotificationRequest(kind: .alert, notificationId: 1), allowing: .benign)
        #expect(h.writes(of: DismissNotificationRequest.self) == 0)
        h.advance(by: 10)
        #expect(h.writes(of: DismissNotificationRequest.self) == 1)
        h.replyError(code: 0, signedAt: Self.pumpTime + 10)
        h.advance(by: 0.09)
        h.apply(.disconnected(peripheralID: Self.id, drop))
        guard case .pumpError = h.results[id] else {
            Issue.record("a verified op-77 is a reject")
            return
        }
        #expect(h.state.ladder.flaps == 0)
    }

    @Test func qualifyingEventsAreReportedAndClearedButNotDuringASignedWrite() {
        var h = readyP1()
        h.apply(.notified(.qualifyingEvents, [1, 0, 0, 0]))
        #expect(h.events == [.qualifyingEvents(.alert)])
        #expect(h.commands == [.write(.qualifyingEvents, [[0, 0, 0, 0]])])
        _ = permission(&h)
        h.apply(.notified(.qualifyingEvents, [2, 0, 0, 0]))
        #expect(h.commands.isEmpty)
        h.apply(.notified(.qualifyingEvents, [0, 0, 0, 0]))
        #expect(h.events.isEmpty)
    }
}
