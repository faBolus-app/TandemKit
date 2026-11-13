import Testing

@testable import TandemMessages

/// The CGM state, snapshot and last-bolus fields the dose path gates on: the CGM alert icon, the Check BG
/// trend icons, the EGV status, the snapshot's ACK, glucose reading and auto-fill bytes, and the
/// last-bolus reply's validity byte.
@Suite struct CGMAndSnapshotDecodeTests {
    /// Two snapshots recorded from t:slim pumps (pumpX2's BolusCalcDataSnapshotResponseTest), cargo only.
    static let recorded: [[UInt8]] = [
        hex("00d100790b000078006e001e000170170000a861fa0a0000000090a9541bdd0f000001fb01015555555555555555"),
        hex("00ae00fe08000078006e001e000170170000a86100000000000040ae541b8d14000001f001015555555555555555")
    ]

    @Test func aRecordedSnapshotIsAcknowledgedWithItsGlucoseAndAutoFill() {
        let a = BolusCalcDataSnapshotResponse(cargo: Self.recorded[0])
        #expect(a.isAck)
        #expect(a.glucoseReading == 209)
        #expect(a.isf == 30)
        #expect(a.isAutopopAllowed)
        #expect(a.maxBolusHourlyTotal == 2_810)
        let b = BolusCalcDataSnapshotResponse(cargo: Self.recorded[1])
        #expect(b.isAck && b.glucoseReading == 174 && b.isAutopopAllowed && b.maxBolusHourlyTotal == 0)
    }

    @Test func aSnapshotWithANonZeroFirstByteIsNotAcknowledged() {
        var cargo = Self.recorded[0]
        cargo[0] = 1
        #expect(!BolusCalcDataSnapshotResponse(cargo: cargo).isAck)
        cargo[37] = 0
        #expect(!BolusCalcDataSnapshotResponse(cargo: cargo).isAutopopAllowed)
        // A short cargo decodes nothing, so it is never an acknowledged snapshot.
        #expect(!BolusCalcDataSnapshotResponse(cargo: [0, 0, 0]).isAck)
    }

    @Test func theLastBolusReplyIsValidOnlyWhenItsFirstByteIsOne() {
        for (first, valid) in [(1, true), (0, false), (2, false)] as [(UInt8, Bool)] {
            var cargo = [UInt8](repeating: 0, count: 24)
            cargo[0] = first
            #expect(LastBolusStatusV2Response(cargo: cargo).isValid == valid)
        }
    }

    private func mirror(trend: UInt8 = 4, alert: UInt8 = 255, basal: UInt8 = 0) -> HomeScreenMirrorResponse {
        var cargo = [UInt8](repeating: 0, count: 9)
        cargo[0] = trend
        cargo[1] = alert
        cargo[5] = basal
        return HomeScreenMirrorResponse(cargo: cargo)
    }

    /// Byte 5 is the basal icon, with pumpX2's ids.
    @Test func theBasalIconNamesEveryKnownStateAndNoOther() {
        #expect(mirror(basal: 0).basalStatusIcon == .basal)
        #expect(mirror(basal: 2).basalStatusIcon == .tempRate)
        #expect(mirror(basal: 3).basalStatusIcon == .zeroTempRate)
        #expect(mirror(basal: 4).basalStatusIcon == .suspend)
        #expect(mirror(basal: 200).basalStatusIcon == .hide)
        for id: UInt8 in [8, 9, 199, 255] { #expect(mirror(basal: id).basalStatusIcon == nil) }
        #expect(HomeScreenMirrorResponse.BasalStatusIcon.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 5, 6, 7, 200])
        #expect(mirror(alert: 4, basal: 4).cgmAlertIcon == .calibrate)
    }

    @Test func theCGMAlertIconNamesEveryKnownStateAndNoOther() {
        #expect(mirror(alert: 255).cgmAlertIcon == .noError)
        #expect(mirror(alert: 15).cgmAlertIcon == .tripleDashes)
        #expect(mirror(alert: 16).cgmAlertIcon == .low)
        #expect(mirror(alert: 18).cgmAlertIcon == .restartSession)
        for id: UInt8 in [9, 10, 25, 254] { #expect(mirror(alert: id).cgmAlertIcon == nil) }
        let startups = HomeScreenMirrorResponse.CGMAlertIcon.allCases.filter(\.isStartup).map(\.rawValue)
        #expect(startups == [0, 1, 2, 3, 19, 20, 21, 22, 23, 24])
    }

    @Test func checkBGTrendIconsAreFlaggedAndRenderNoArrow() {
        for id: UInt8 in 8...13 {
            #expect(mirror(trend: id).isCheckBG)
            #expect(mirror(trend: id).cgmTrendArrow == "")
        }
        for id: UInt8 in [0, 4, 7, 14] { #expect(!mirror(trend: id).isCheckBG) }
    }

    @Test func theEGVStatusIsNamed() {
        func egv(status: UInt8) -> CurrentEGVGuiDataResponse {
            CurrentEGVGuiDataResponse(cargo: [0, 0, 0, 0, 120, 0, status, 0])
        }
        #expect(egv(status: 1).egvStatus == .valid)
        #expect(egv(status: 2).egvStatus == .low)
        #expect(egv(status: 3).egvStatus == .high)
        #expect(egv(status: 4).egvStatus == .unavailable)
        #expect(egv(status: 9).egvStatus == nil)
    }
}

private func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}
