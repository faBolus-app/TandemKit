import Foundation
import TandemMessages
import Testing

@testable import TandemBench

/// The bench package builds TandemKit with the `BenchWrites` trait; these hold only in that build.
/// TandemKit's own tests check the default build, where the write is refused.
@Suite struct BenchWritesTraitTests {
    @Test func theBenchBuildAllowsItsExtraWrite() {
        #expect(SupportMatrix.isAllowedSignedWrite(ChangeTimeDateRequest(tandemEpochTime: 1)))
        #expect(SupportMatrix.benchSignedWrites.count == 1)
        // UserInteraction is now on the app's own list, so every build allows it.
        #expect(SupportMatrix.isAllowedSignedWrite(UserInteractionRequest()))
    }

    /// Nothing else is widened: every other signed write outside the eight stays refused.
    @Test func everyOtherSignedWriteStaysRefused() {
        let others: [any Message] = [
            PlaySoundRequest(), SetMaxBolusLimitRequest(), SetModesRequest(), SetTempRateRequest(),
            SuspendPumpingRequest(), FactoryResetRequest()
        ]
        func allowed(_ message: some Message) -> Bool { SupportMatrix.isAllowedSignedWrite(message) }
        for message in others where message.signed {
            let ok = allowed(message)
            #expect(!ok, "\(type(of: message))")
        }
        for key in SupportMatrix.benchSignedWrites {
            #expect(!SupportMatrix.allowedSignedWrites.contains(key))
        }
    }
}

@Suite struct BenchBolusTests {
    /// Units-only is byte for byte the layout of pumpX2's 1 U override capture, at 0.05 U.
    @Test func unitsOnlyIsTheCapturedOverrideForm() throws {
        let r = try BenchBolusKind.units.request(bolusId: 10650, carbs: 9, bg: 140)
        let captured = InitiateBolusRequest(totalVolume: 50, bolusID: 10650, bolusTypeBitmask: 8)
        #expect(r.cargo == captured.cargo)
        #expect(r.foodVolume == 0 && r.correctionVolume == 0 && r.bolusCarbs == 0 && r.bolusBG == 0)
        #expect(
            try BenchBolusKind.cancel.request(bolusId: 5, carbs: 0, bg: 0).cargo
                == BenchBolusKind.units.request(bolusId: 5, carbs: 0, bg: 0).cargo)
    }

    /// Carb is the 13 g capture's form: mask 1, the whole dose as food, carbs and BG filled in.
    @Test func carbIsTheCapturedCarbForm() throws {
        let r = try BenchBolusKind.carb.request(bolusId: 7, carbs: 2, bg: 142)
        #expect(r.bolusTypeBitmask == 1 && r.totalVolume == 50 && r.foodVolume == 50 && r.correctionVolume == 0)
        #expect(r.bolusCarbs == 2 && r.bolusBG == 142)
    }

    /// No carbs and a correction: FOOD2 | CORRECTION, the library's rule.
    @Test func correctionIsFood2AndCorrectionWithTheBg() throws {
        let r = try BenchBolusKind.correction.request(bolusId: 7, carbs: 30, bg: 180)
        #expect(r.bolusTypeBitmask == 10 && r.correctionVolume == 50 && r.foodVolume == 0)
        #expect(r.bolusCarbs == 0 && r.bolusBG == 180)
    }

    @Test func everyKindIsTheSmallestBolusAndADeliveryWrite() throws {
        for kind in BenchBolusKind.allCases {
            let r = try kind.request(bolusId: 1, carbs: 1, bg: 120)
            #expect(r.totalVolume == 50)
            #expect(r.operationRisk == .delivery)
            #expect(r.props.modifiesInsulinDelivery)
        }
    }

    @Test func anUnsettledBolusBlocksTheNext() {
        let now = Date()
        var log = BenchBolusLog(entries: [
            .init(date: now.addingTimeInterval(-7200), serial: 1, kind: "units", bolusId: 3)
        ])
        #expect(log.refusal(now: now)?.contains("no settled outcome") == true)
        let settled = log.settleLast("ended")
        #expect(settled)
        #expect(log.refusal(now: now) == nil)
        let again = log.settleLast("again")
        #expect(!again)
    }

    @Test func atMostThreeAnHour() {
        let now = Date()
        let settled = (0..<3).map {
            BenchBolusLog.Entry(
                date: now.addingTimeInterval(-Double($0) * 600), serial: 1, kind: "units", bolusId: $0, outcome: "ended"
            )
        }
        #expect(BenchBolusLog(entries: settled).refusal(now: now)?.contains("3 bench boluses") == true)
        #expect(BenchBolusLog(entries: Array(settled.prefix(2))).refusal(now: now) == nil)
        #expect(BenchBolusLog(entries: settled).refusal(now: now.addingTimeInterval(3600)) == nil)
    }

    /// Two runs at once: each keeps the other's entries, and a settled outcome isn't lost to a stale copy.
    @Test func savingMergesWithTheCopyOnDisk() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let p1 = BenchBolusLog.Entry(date: t, serial: 1, kind: "units", bolusId: 10)
        let p2 = BenchBolusLog.Entry(date: t.addingTimeInterval(5), serial: 2, kind: "carb", bolusId: 20)
        var settledP1 = p1
        settledP1.outcome = "op-77 error 7"
        let disk = BenchBolusLog(entries: [settledP1])
        let mine = BenchBolusLog(entries: [p1, p2])
        let merged = mine.merging(disk)
        #expect(merged.entries.count == 2)
        #expect(merged.entries[0].outcome == "op-77 error 7")
        #expect(merged.entries[1] == p2)
        #expect(merged.refusal(now: t.addingTimeInterval(10))?.contains("20") == true)
    }

    @Test func theLogRoundTrips() throws {
        let log = BenchBolusLog(entries: [
            .init(date: Date(timeIntervalSince1970: 1_800_000_000), serial: 9, kind: "carb", bolusId: 4)
        ])
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(BenchBolusLog.self, from: data) == log)
    }
}

@Suite struct BenchSafetyGateTests {
    @Test func theSerialHasToBeThisPumps() {
        #expect(BenchSafetyGate.serialRefusal(typed: " 123456 ", pumpSerial: 123456) == nil)
        #expect(BenchSafetyGate.serialRefusal(typed: "123457", pumpSerial: 123456) != nil)
        #expect(BenchSafetyGate.serialRefusal(typed: "", pumpSerial: 123456) != nil)
        #expect(BenchSafetyGate.serialRefusal(typed: "123456", pumpSerial: nil) != nil)
    }

    @Test func aWriteNeedsTheFlagAndTheSerial() {
        #expect(BenchSafetyGate.writeRefusal(environment: [:], typed: "1", pumpSerial: 1) != nil)
        #expect(BenchSafetyGate.writeRefusal(environment: ["PUMP_BENCH_WRITES": "1"], typed: "1", pumpSerial: 1) == nil)
        #expect(BenchSafetyGate.writeRefusal(environment: ["PUMP_BENCH_WRITES": "1"], typed: "2", pumpSerial: 1) != nil)
    }

    @Test func aBolusNeedsSalineOrAnEmptyPump() {
        let saline = ["PUMP_SALINE_ATTESTED": "1"]
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: [:], typed: "1", pumpSerial: 1, noCartridge: false, reservoirUnits: 0) != nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: saline, typed: "1", pumpSerial: 1, noCartridge: false, reservoirUnits: 120) == nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: saline, typed: "2", pumpSerial: 1, noCartridge: false, reservoirUnits: 120) != nil)
        // The rejection test: its own attestation, and the pump must report an empty reservoir. A 0 U
        // reading alone isn't enough: a nearly empty insulin cartridge reads 0 too.
        let empty = ["PUMP_NO_CARTRIDGE_ATTESTED": "1"]
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: [:], typed: "1", pumpSerial: 1, noCartridge: true, reservoirUnits: 0) != nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: saline, typed: "1", pumpSerial: 1, noCartridge: true, reservoirUnits: 0) != nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: empty, typed: "1", pumpSerial: 1, noCartridge: true, reservoirUnits: 0) == nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: empty, typed: "1", pumpSerial: 1, noCartridge: true, reservoirUnits: 40) != nil)
        #expect(
            BenchSafetyGate.bolusRefusal(
                environment: empty, typed: "1", pumpSerial: 1, noCartridge: true, reservoirUnits: nil) != nil)
    }

    @Test func theClockTargetMovesOnWithTheTimeSinceTheRead() {
        #expect(BenchClock.target(pumpTime: 1000, readAt: 10, now: 12.4, offset: 0) == 1002)
        #expect(BenchClock.target(pumpTime: 1000, readAt: 10, now: 10, offset: 300) == 1300)
        #expect(BenchClock.target(pumpTime: 100, readAt: 0, now: 0, offset: -300) == 0)
        #expect(BenchClock.target(pumpTime: 1000, readAt: 10, now: 5, offset: 0) == 1000)
    }
}
