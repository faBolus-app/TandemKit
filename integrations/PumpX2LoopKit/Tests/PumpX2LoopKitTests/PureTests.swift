import XCTest
import LoopKit
import PumpX2Messages
@testable import PumpX2LoopKit

final class PureTests: XCTestCase {

    // MARK: DoseEntry conversion — the authoritative-units invariant

    func testUnfinalizedBolusConvertsWithAuthoritativeDeliveredUnits() {
        let finalized = TandemUnfinalizedDose(
            doseType: .bolus, programmedUnits: 5.0, finalizedUnits: 3.2,
            startTime: Date(timeIntervalSince1970: 1000), duration: 200,
            scheduledCertainty: .certain, automatic: false, insulinType: nil, bolusId: 7,
            syncIdentifier: Data("x".utf8))
        let entry = DoseEntry(finalized)
        XCTAssertEqual(entry.type, .bolus)
        XCTAssertEqual(entry.programmedUnits, 5.0)      // value = programmed / requested
        XCTAssertEqual(entry.deliveredUnits, 3.2)       // delivered = pump-authoritative
        XCTAssertFalse(entry.isMutable)                 // finalized → immutable

        var inFlight = finalized
        inFlight.finalizedUnits = nil
        let inFlightEntry = DoseEntry(inFlight)
        XCTAssertNil(inFlightEntry.deliveredUnits)      // never fabricate a delivered amount
        XCTAssertTrue(inFlightEntry.isMutable)          // in flight → mutable
    }

    func testSyncIdentifierIsDeterministicAndKeyedOnPumpIds() {
        let a = TandemUnfinalizedDose.syncIdentifier(pumpSerial: "SN1", tag: "bolus", id: 7)
        let b = TandemUnfinalizedDose.syncIdentifier(pumpSerial: "SN1", tag: "bolus", id: 7)
        let c = TandemUnfinalizedDose.syncIdentifier(pumpSerial: "SN1", tag: "bolus", id: 8)
        XCTAssertEqual(a, b)      // same (serial, tag, id) → same identifier (dedup-stable)
        XCTAssertNotEqual(a, c)   // different id → different identifier
    }

    // MARK: History mapping

    func testHistoryMappingReportsPumpAuthoritativeDeliveredAndDropsNonDoseEvents() {
        let events: [any HistoryLogEvent] = [
            Fixture.bolusCompleted(pumpTimeSec: 100, sequenceNum: 1, bolusId: 42, deliveredUnits: 3.2, requestedUnits: 5.0),
            Fixture.pumpingSuspended(pumpTimeSec: 200, sequenceNum: 2),
            UnknownHistoryLog(cargo: [UInt8](repeating: 0, count: 26)), // must be dropped
        ]
        let mapped = TandemHistoryMapping.newPumpEvents(from: events, pumpSerial: "SN1")
        XCTAssertEqual(mapped.count, 2)   // unknown dropped

        let bolus = try! XCTUnwrap(mapped.first { $0.type == .bolus })
        XCTAssertEqual(bolus.dose?.deliveredUnits ?? -1, 3.2, accuracy: 0.001)   // authoritative delivered
        XCTAssertEqual(bolus.dose?.programmedUnits ?? -1, 5.0, accuracy: 0.001)  // requested
        XCTAssertFalse(bolus.dose!.isMutable)
        XCTAssertTrue(mapped.contains { $0.type == .suspend })
    }

    // MARK: Temp-basal percent↔U/hr

    func testTempBasalConversionReportsEffectiveNotRequestedRate() throws {
        let exact = try TandemTempBasalConversion.percent(forUnitsPerHour: 1.5, scheduledUnitsPerHour: 1.0, minPercent: 0, maxPercent: 250)
        XCTAssertEqual(exact.percent, 150)
        XCTAssertEqual(exact.effectiveUnitsPerHour, 1.5, accuracy: 0.0001)

        // Over-range clamps to the achievable percent and reports the EFFECTIVE rate, not the request.
        let over = try TandemTempBasalConversion.percent(forUnitsPerHour: 10.0, scheduledUnitsPerHour: 1.0, minPercent: 0, maxPercent: 250)
        XCTAssertEqual(over.percent, 250)
        XCTAssertEqual(over.effectiveUnitsPerHour, 2.5, accuracy: 0.0001)

        XCTAssertThrowsError(try TandemTempBasalConversion.percent(forUnitsPerHour: 1.0, scheduledUnitsPerHour: 0.0, minPercent: 0, maxPercent: 250))
    }

    // MARK: Status projection

    func testStatusProjection() {
        var s = TandemPumpManagerState(authKey: [1, 2, 3], pumpSerial: "SN1")
        s.suspended = true
        let suspended = TandemStatusProjection.status(from: s, bolusEngage: .stable, basalEngage: .stable, now: Date())
        XCTAssertEqual(suspended.basalDeliveryState?.isSuspended, true)
        XCTAssertEqual(suspended.bolusState, .noBolus)
        XCTAssertFalse(suspended.deliveryIsUncertain)

        s.deliveryUncertain = true
        XCTAssertTrue(TandemStatusProjection.status(from: s, bolusEngage: .stable, basalEngage: .stable, now: Date()).deliveryIsUncertain)

        var s2 = TandemPumpManagerState(authKey: [1], pumpSerial: "SN1")
        s2.pendingDose = TandemUnfinalizedDose(doseType: .bolus, programmedUnits: 2, finalizedUnits: nil,
                                               startTime: Date(), duration: 80, scheduledCertainty: .uncertain,
                                               automatic: false, insulinType: nil, bolusId: 5, syncIdentifier: Data())
        if case .inProgress = TandemStatusProjection.status(from: s2, bolusEngage: .stable, basalEngage: .stable, now: Date()).bolusState {} else {
            XCTFail("expected in-progress bolus")
        }
        // engagement drives the transitional cases
        XCTAssertEqual(TandemStatusProjection.status(from: s2, bolusEngage: .engaging, basalEngage: .stable, now: Date()).bolusState, .initiating)
        XCTAssertEqual(TandemStatusProjection.status(from: s2, bolusEngage: .stable, basalEngage: .suspending, now: Date()).basalDeliveryState, .suspending)
    }

    // MARK: rawState round-trip

    func testRawStateRoundTrip() throws {
        let original = TandemPumpManagerState(
            timeZone: TimeZone(secondsFromGMT: 3600)!, authKey: [9, 8, 7],
            pumpPeripheralID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            pumpSerial: "SN9",
            pendingDose: TandemUnfinalizedDose(doseType: .bolus, programmedUnits: 4, finalizedUnits: nil,
                                               startTime: Date(timeIntervalSince1970: 5000), duration: 160,
                                               scheduledCertainty: .uncertain, automatic: true, insulinType: nil,
                                               bolusId: 11, syncIdentifier: Data("id".utf8)),
            lastReconciliation: Date(timeIntervalSince1970: 6000), deliveryUncertain: true, suspended: true,
            batteryPercent: 55, reservoirUnits: 120)
        let restored = try XCTUnwrap(TandemPumpManagerState(rawValue: original.rawValue))
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.pendingDose?.bolusId, 11)  // the reconcile key survives relaunch
        XCTAssertTrue(restored.deliveryUncertain)

        // A newer/unknown version is rejected, not mis-decoded.
        var bad = original.rawValue
        bad["version"] = 999
        XCTAssertNil(TandemPumpManagerState(rawValue: bad))
    }

    func testNoticeStatesNotForRealInsulin() {
        XCTAssertTrue(PumpX2LoopKitNotice.text.contains("NOT for use with real insulin"))
        XCTAssertTrue(PumpX2LoopKitNotice.text.contains("sole authority"))
    }
}
