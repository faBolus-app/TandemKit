import Testing
@testable import TandemMessages

/// faBolus must never calculate a trend arrow. The pump's own `HomeScreenMirrorResponse.cgmTrendIconId`
/// is authoritative (including an explicit `noArrow` state); a client-side derivation from
/// `CurrentEgvGuiDataV2Response.trendRate` must return `nil` rather than guess.
@Suite struct TrendProvenanceTests {

    // MARK: The pump's own icon (authoritative)

    /// Ids match upstream `HomeScreenMirrorResponse.CGMTrendIcon`.
    @Test func pumpTrendIconMapsEveryDeclaredId() {
        let expected: [(Int, String)] = [
            (0, ""),    // NO_ARROW — the state a derived arrow cannot express
            (1, "⇈"),   // DOUBLE_UP
            (2, "↑"),   // UP
            (3, "↗"),   // UP_RIGHT
            (4, "→"),   // FLAT
            (5, "↘"),   // DOWN_RIGHT
            (6, "↓"),   // DOWN
            (7, "⇊"),   // DOUBLE_DOWN
        ]
        for (id, arrow) in expected {
            var cargo = [UInt8](repeating: 0, count: 9)
            cargo[0] = UInt8(id)
            let m = HomeScreenMirrorResponse(cargo: cargo)
            #expect(m.cgmTrendIconId == id)
            #expect(m.cgmTrendArrow == arrow, "icon id \(id) should render \(arrow.isEmpty ? "no arrow" : arrow)")
        }
    }

    /// An id the pump firmware might add later must degrade to "no arrow", never to a guessed direction.
    @Test func unknownPumpTrendIconRendersNoArrow() {
        for id: UInt8 in [8, 9, 200, 255] {
            var cargo = [UInt8](repeating: 0, count: 9)
            cargo[0] = id
            let m = HomeScreenMirrorResponse(cargo: cargo)
            #expect(m.cgmTrendIcon == nil)
            #expect(m.cgmTrendArrow == "")
        }
    }

    // MARK: The derived fallback

    /// Builds an 8-byte EGV V2 cargo: reading @4 (short), status @6, signed trend rate @7.
    private func egv(reading: Int, status: UInt8, rate: Int8) -> CurrentEgvGuiDataV2Response {
        var cargo = [UInt8](repeating: 0, count: 8)
        let r = Bytes.firstTwoBytesLittleEndian(reading); cargo[4] = r[0]; cargo[5] = r[1]
        cargo[6] = status
        cargo[7] = UInt8(bitPattern: rate)
        return CurrentEgvGuiDataV2Response(cargo: cargo)
    }

    /// The E8 mechanism: `0x7f` is the Dexcom-family "rate unavailable" sentinel, and decoding it as a
    /// rate yields +12.7 mg/dL/min — a double-up arrow while the pump shows none.
    @Test func sentinelRateYieldsNoArrow() {
        let up = egv(reading: 120, status: 1, rate: Int8.max)      // 0x7f
        #expect(up.trendRateIsUnavailable)
        #expect(up.trendRateIfKnown == nil)
        #expect(up.trendArrow == nil, "0x7f must not read as a rapid rise")

        let down = egv(reading: 120, status: 1, rate: Int8.min)    // 0x80
        #expect(down.trendRateIsUnavailable)
        #expect(down.trendArrow == nil)
    }

    /// An INVALID (0) or UNAVAILABLE (4) frame has no usable rate, so it has no arrow — the assignment
    /// used to happen outside the validity check, so garbage still produced an arrow.
    @Test func invalidOrUnavailableFrameYieldsNoArrow() {
        for status: UInt8 in [0, 4] {
            let m = egv(reading: 120, status: status, rate: 20)
            #expect(!m.hasValidReading)
            #expect(m.trendRateIfKnown == nil)
            #expect(m.trendArrow == nil, "status \(status) must not produce an arrow")
        }
    }

    /// Equal magnitudes must produce equal severity. `-3.0` used to map to a single arrow while `+3.0`
    /// fell through the catch-all `default` to double-up.
    @Test func bandsAreSymmetric() {
        // rate is in 0.1 mg/dL/min units, so ±30 == ±3.0 mg/dL/min.
        #expect(egv(reading: 120, status: 1, rate: -30).trendArrow == "⇊")
        #expect(egv(reading: 120, status: 1, rate: 30).trendArrow == "⇈")
        #expect(egv(reading: 120, status: 1, rate: -25).trendArrow == "↓")
        #expect(egv(reading: 120, status: 1, rate: 25).trendArrow == "↑")
        #expect(egv(reading: 120, status: 1, rate: -15).trendArrow == "↘")
        #expect(egv(reading: 120, status: 1, rate: 15).trendArrow == "↗")
        #expect(egv(reading: 120, status: 1, rate: 0).trendArrow == "→")
        #expect(egv(reading: 120, status: 1, rate: -10).trendArrow == "→")
        #expect(egv(reading: 120, status: 1, rate: 10).trendArrow == "→")
    }

    /// A real frame still works: the previously-verified 9-byte Control-IQ+ cargo.
    @Test func realFrameStillDerivesAnArrow() {
        let cargo: [UInt8] = [0xc5, 0x67, 0xe2, 0x22, 0x9e, 0x00, 0x01, 0x04, 0x00]
        let m = CurrentEgvGuiDataV2Response(cargo: cargo)
        #expect(m.trendRate == 4)                    // +0.4 mg/dL/min
        #expect(m.trendRateIfKnown == 0.4)
        #expect(m.trendArrow == "→")                 // steady
    }

    // MARK: - V1 twin (op 35), used on older firmware that rejects the V2 request (op 192)

    /// Same 8-byte layout as `egv(...)` above, for the V1 response.
    private func egvV1(reading: Int, status: UInt8, rate: Int8) -> CurrentEGVGuiDataResponse {
        var cargo = [UInt8](repeating: 0, count: 8)
        let r = Bytes.firstTwoBytesLittleEndian(reading); cargo[4] = r[0]; cargo[5] = r[1]
        cargo[6] = status
        cargo[7] = UInt8(bitPattern: rate)
        return CurrentEGVGuiDataResponse(cargo: cargo)
    }

    /// The V1 decoder read `trendRate` UNSIGNED (`Int(raw[7])`) while the reference sign-extends
    /// (Java `byte`). A falling rate therefore decoded as a large positive one — every FALLING trend
    /// would have rendered as RAPIDLY RISING once the V1 response was actually consumed. Latent until
    /// the op192 fix started substituting this response on older pumps.
    @Test func v1TrendRateIsSigned() {
        #expect(egvV1(reading: 120, status: 1, rate: -1).trendRate == -1)
        #expect(egvV1(reading: 120, status: 1, rate: -30).trendRate == -30)
        #expect(egvV1(reading: 120, status: 1, rate: -30).trendRateMgDlPerMin == -3.0)
        // The exact misread the unsigned decode produced: 0xFF -> 255 -> +25.5 mg/dL/min.
        #expect(egvV1(reading: 120, status: 1, rate: -1).trendRate != 255)
        #expect(egvV1(reading: 120, status: 1, rate: -30).trendArrow == "⇊",
                "a falling rate must not render as rising")
    }

    /// The V1 twin must behave identically to V2 for every band, sentinel and validity rule — they
    /// carry identical cargo semantics and now share `EgvTrend.arrow(forRate:)`, so a divergence here
    /// would mean an older pump silently gets different trend/validity behaviour than a newer one.
    @Test func v1MatchesV2ForEveryBandAndSentinel() {
        for rate: Int8 in [-30, -25, -15, -10, 0, 10, 15, 25, 30, Int8.max, Int8.min] {
            for status: UInt8 in [0, 1, 2, 3, 4] {
                let v1 = egvV1(reading: 120, status: status, rate: rate)
                let v2 = egv(reading: 120, status: status, rate: rate)
                #expect(v1.hasValidReading == v2.hasValidReading, "status \(status) rate \(rate)")
                #expect(v1.trendRate == v2.trendRate, "status \(status) rate \(rate)")
                #expect(v1.trendRateIsUnavailable == v2.trendRateIsUnavailable, "status \(status) rate \(rate)")
                #expect(v1.trendRateIfKnown == v2.trendRateIfKnown, "status \(status) rate \(rate)")
                #expect(v1.trendArrow == v2.trendArrow, "status \(status) rate \(rate)")
            }
        }
    }

    /// Boundary neighbours around the validity equivalence class, mirroring the V2 rules.
    @Test func v1ValidityBoundaries() {
        #expect(!egvV1(reading: 0, status: 1, rate: 0).hasValidReading)     // reading must be > 0
        #expect(egvV1(reading: 1, status: 1, rate: 0).hasValidReading)
        #expect(egvV1(reading: 599, status: 1, rate: 0).hasValidReading)
        #expect(!egvV1(reading: 600, status: 1, rate: 0).hasValidReading)   // must be < 600
        #expect(!egvV1(reading: 120, status: 0, rate: 0).hasValidReading)   // INVALID
        #expect(egvV1(reading: 120, status: 2, rate: 0).hasValidReading)    // LOW
        #expect(egvV1(reading: 120, status: 3, rate: 0).hasValidReading)    // HIGH
        #expect(!egvV1(reading: 120, status: 4, rate: 0).hasValidReading)   // UNAVAILABLE
    }
}
