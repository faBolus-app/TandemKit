import Testing
@testable import TandemMessages

/// Byte-exact lock for the **extended (combo) bolus** cargo, which faBolus relies on for delivery.
/// Vector from the oracle test `testInitiateBolusRequest_Mobi_Extended8h`: a pure-extended bolus of
/// 2000 mU (2.0 U) over 28800 s (8 h), bolusID 248, bolusTypeBitmask 12 (FOOD2|EXTENDED).
@Suite struct InitiateBolusExtendedTests {
    @Test func extendedComboCargoMatchesOracle() {
        let req = InitiateBolusRequest(
            totalVolume: 0, bolusID: 248, bolusTypeBitmask: 12,
            foodVolume: 0, correctionVolume: 0, bolusCarbs: 0, bolusBG: 0, bolusIOB: 0,
            extendedVolume: 2000, extendedSeconds: 28800, extended3: 0)

        // Oracle cargo (signed Java bytes) reinterpreted as UInt8.
        let expected: [UInt8] = [
            0, 0, 0, 0, 248, 0, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 208, 7, 0, 0, 128, 112, 0, 0, 0, 0, 0, 0
        ]
        #expect(req.cargo == expected)
        #expect(req.bolusTypeBitmask == 12)
        #expect(req.extendedVolume == 2000)
        #expect(req.extendedSeconds == 28800)
    }

    /// Guards the min-extended precondition boundary (0.40 U total across now + later).
    @Test func minExtendedIs400Milliunits() {
        #expect(InitiateBolusRequest.minExtendedBolusMilliunits == 400)
    }

    /// Oracle byte-lock for a carb bolus. Vector from the upstream oracle test
    /// `testInitiateBolusRequest_ID10652_013u_13g_carbs_142mgdl` — 0.13 U (130 mU), bolusID 10652,
    /// carbs 13 g @ bytes 17-18, BG 142 mg/dL @ bytes 19-20. The reverse-engineered app sends
    /// bitmask 1 = FOOD1 ("used when there is carbs"), with foodVolume == totalVolume (the whole dose
    /// is the food component) and correctionVolume 0 — NOT FOOD2(8)/foodVolume 0.
    @Test func carbBolusFood1CargoMatchesOracle() {
        let req = InitiateBolusRequest(
            totalVolume: 130, bolusID: 10652, bolusTypeBitmask: 1,
            foodVolume: 130, correctionVolume: 0, bolusCarbs: 13, bolusBG: 142, bolusIOB: 0,
            extendedVolume: 0, extendedSeconds: 0, extended3: 0)
        let expected: [UInt8] = [
            130, 0, 0, 0, 156, 41, 0, 0, 1, 130, 0, 0, 0, 0, 0, 0, 0, 13, 0, 142, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]
        #expect(req.cargo == expected)
        #expect(req.bolusTypeBitmask == 1)  // FOOD1
        #expect(req.foodVolume == 130)
        #expect(req.correctionVolume == 0)
        #expect(req.bolusCarbs == 13)
        #expect(req.bolusBG == 142)
        #expect(req.bolusIOB == 0)
    }

    /// Oracle byte-lock for a carb bolus with IOB. Vector from
    /// `testInitiateBolusRequest_ID10653_011u_11g_carbs_161mgdl_013u_iob` — 0.11 U (110 mU),
    /// bolusID 10653, carbs 11 g, BG 161, bolusIOB 130 (0.13 U) @ bytes 21-24. Confirms the app DOES
    /// populate bolusIOB rather than leaving it zero.
    @Test func carbBolusWithIobCargoMatchesOracle() {
        let req = InitiateBolusRequest(
            totalVolume: 110, bolusID: 10653, bolusTypeBitmask: 1,
            foodVolume: 110, correctionVolume: 0, bolusCarbs: 11, bolusBG: 161, bolusIOB: 130,
            extendedVolume: 0, extendedSeconds: 0, extended3: 0)
        let expected: [UInt8] = [
            110, 0, 0, 0, 157, 41, 0, 0, 1, 110, 0, 0, 0, 0, 0, 0, 0, 11, 0, 161, 0,
            130, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        ]
        #expect(req.cargo == expected)
        #expect(req.bolusTypeBitmask == 1)  // FOOD1
        #expect(req.foodVolume == 110)
        #expect(req.bolusIOB == 130)
    }
}
