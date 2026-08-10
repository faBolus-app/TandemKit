import XCTest
import LoopKit
import PumpX2Messages
@testable import PumpX2LoopKit

@MainActor
final class DeliveryTests: XCTestCase {

    private func makeManager(_ fake: FakeTandemConnection) -> TandemPumpManager {
        TandemPumpManager(state: TandemPumpManagerState(authKey: [1, 2, 3], pumpSerial: "SN1"), connection: fake)
    }

    /// A successfully accepted bolus reports in-progress and is NOT flagged uncertain.
    func testEnactBolusSuccessIsInProgressAndCertain() async {
        let fake = FakeTandemConnection()
        fake.onSend = { msg in
            switch msg {
            case is TimeSinceResetRequest: return Fixture.timeSinceReset()
            case is BolusPermissionRequest: return Fixture.bolusPermission(granted: true, bolusId: 77)
            case is InitiateBolusRequest: return Fixture.initiate(accepted: true, bolusId: 77)
            default: throw TandemTransportError.badResponse("unexpected \(type(of: msg))")
            }
        }
        let m = makeManager(fake)
        let exp = expectation(description: "bolus")
        m.enactBolus(units: 2.5, activationType: .manualNoRecommendation) { err in
            XCTAssertNil(err); exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertFalse(m.status.deliveryIsUncertain)
        if case .inProgress(let d) = m.status.bolusState {
            XCTAssertEqual(d.programmedUnits, 2.5)
        } else {
            XCTFail("expected in-progress bolus, got \(m.status.bolusState)")
        }
    }

    /// A lost reply AFTER the initiate write → uncertain delivery, durable, and a new bolus is refused.
    func testEnactBolusIndeterminateOnInitiateTimeout() async {
        let fake = FakeTandemConnection()
        fake.onSend = { msg in
            switch msg {
            case is TimeSinceResetRequest: return Fixture.timeSinceReset()
            case is BolusPermissionRequest: return Fixture.bolusPermission(granted: true, bolusId: 88)
            case is InitiateBolusRequest: throw TandemTransportError.timedOut // write issued, no ack
            default: throw TandemTransportError.badResponse("x")
            }
        }
        let m = makeManager(fake)
        let exp = expectation(description: "indeterminate")
        m.enactBolus(units: 1.0, activationType: .manualNoRecommendation) { err in
            if case .uncertainDelivery = err {} else { XCTFail("expected uncertainDelivery, got \(String(describing: err))") }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertTrue(m.status.deliveryIsUncertain)

        // Fail-closed: no new delivery while the prior outcome is unresolved.
        let exp2 = expectation(description: "refused")
        m.enactBolus(units: 1.0, activationType: .manualNoRecommendation) { err in
            if case .deviceState = err {} else { XCTFail("expected fail-closed deviceState, got \(String(describing: err))") }
            exp2.fulfill()
        }
        await fulfillment(of: [exp2], timeout: 5)
    }

    /// A parsed explicit NACK is a terminal failure that leaves nothing pending (never delivered).
    func testEnactBolusNackIsCleanFailure() async {
        let fake = FakeTandemConnection()
        fake.onSend = { msg in
            switch msg {
            case is TimeSinceResetRequest: return Fixture.timeSinceReset()
            case is BolusPermissionRequest: return Fixture.bolusPermission(granted: true, bolusId: 5)
            case is InitiateBolusRequest: return Fixture.initiate(accepted: false, bolusId: 5) // NACK
            default: throw TandemTransportError.badResponse("x")
            }
        }
        let m = makeManager(fake)
        let exp = expectation(description: "nack")
        m.enactBolus(units: 1.0, activationType: .manualNoRecommendation) { err in
            XCTAssertNotNil(err)
            if case .uncertainDelivery = err { XCTFail("a parsed NACK must not be uncertain") }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 5)
        XCTAssertFalse(m.status.deliveryIsUncertain)
        XCTAssertEqual(m.status.bolusState, .noBolus)
    }

    /// After reconnect/refresh, the pump's authoritative last-bolus record finalizes and clears state.
    func testReconcileFinalizesState() async {
        let fake = FakeTandemConnection()
        fake.onSend = { msg in
            switch msg {
            case is TimeSinceResetRequest: return Fixture.timeSinceReset()
            case is BolusPermissionRequest: return Fixture.bolusPermission(granted: true, bolusId: 99)
            case is InitiateBolusRequest: return Fixture.initiate(accepted: true, bolusId: 99)
            case is LastBolusStatusV2Request: return Fixture.lastBolusV2(bolusId: 99, deliveredUnits: 1.8, requestedUnits: 2.0)
            default: throw TandemTransportError.badResponse("x")
            }
        }
        let m = makeManager(fake)
        let e1 = expectation(description: "issue")
        m.enactBolus(units: 2.0, activationType: .manualNoRecommendation) { _ in e1.fulfill() }
        await fulfillment(of: [e1], timeout: 5)

        let e2 = expectation(description: "reconcile")
        m.ensureCurrentPumpData { _ in e2.fulfill() }
        await fulfillment(of: [e2], timeout: 5)
        XCTAssertEqual(m.status.bolusState, .noBolus)
        XCTAssertFalse(m.status.deliveryIsUncertain)
    }

    /// A cancel returns the pump's authoritative delivered amount — never a fabricated one.
    func testCancelReturnsAuthoritativeDeliveredDose() async {
        let fake = FakeTandemConnection()
        fake.onSend = { msg in
            switch msg {
            case is TimeSinceResetRequest: return Fixture.timeSinceReset()
            case is BolusPermissionRequest: return Fixture.bolusPermission(granted: true, bolusId: 33)
            case is InitiateBolusRequest: return Fixture.initiate(accepted: true, bolusId: 33)
            case is CancelBolusRequest: return Fixture.initiate(accepted: true, bolusId: 33) // ack ignored
            case is LastBolusStatusV2Request: return Fixture.lastBolusV2(bolusId: 33, deliveredUnits: 0.5, requestedUnits: 2.0)
            default: throw TandemTransportError.badResponse("x")
            }
        }
        let m = makeManager(fake)
        let e1 = expectation(description: "issue")
        m.enactBolus(units: 2.0, activationType: .manualNoRecommendation) { _ in e1.fulfill() }
        await fulfillment(of: [e1], timeout: 5)

        let e2 = expectation(description: "cancel")
        m.cancelBolus { result in
            switch result {
            case .success(let dose):
                XCTAssertEqual(dose?.deliveredUnits ?? -1, 0.5, accuracy: 0.001) // authoritative partial
            case .failure(let err):
                XCTFail("expected success, got \(err)")
            }
            e2.fulfill()
        }
        await fulfillment(of: [e2], timeout: 5)
        XCTAssertEqual(m.status.bolusState, .noBolus)
    }

    /// No live connection → every delivery fail-closes rather than pretending.
    func testFailsClosedWithoutConnection() async {
        let m = TandemPumpManager(state: TandemPumpManagerState(authKey: [1], pumpSerial: "SN1"), connection: nil)
        let exp = expectation(description: "no conn")
        m.enactBolus(units: 1.0, activationType: .manualNoRecommendation) { err in
            if case .deviceState = err {} else { XCTFail("expected fail-closed deviceState") }
            exp.fulfill()
        }
        await fulfillment(of: [exp], timeout: 2)
    }

    /// The history fan-out reaches the host delegate with the pump-authoritative delivered amount.
    func testHistoryFanoutReachesDelegate() async {
        let fake = FakeTandemConnection()
        let m = makeManager(fake)
        let delegate = CapturingPumpManagerDelegate()
        let dq = DispatchQueue(label: "delegate.test")
        m.pumpManagerDelegate = delegate
        m.delegateQueue = dq

        m.ingestHistory(events: [
            Fixture.bolusCompleted(pumpTimeSec: 100, sequenceNum: 1, bolusId: 42, deliveredUnits: 3.2, requestedUnits: 5.0),
        ])
        // Drain the delegate queue and read captured events on it (avoids a data race).
        let events = dq.sync { delegate.newEvents }
        let bolus = events.first { $0.type == .bolus }
        XCTAssertEqual(bolus?.dose?.deliveredUnits ?? -1, 3.2, accuracy: 0.001)
    }
}
