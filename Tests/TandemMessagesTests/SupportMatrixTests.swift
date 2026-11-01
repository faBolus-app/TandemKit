import Foundation
import Testing
@testable import TandemMessages

@Suite struct SupportMatrixTests {
    private let p1Unit = PumpUnit(serialNumber: 1693, armSoftwareVersion: 1, mspSoftwareVersion: 1)
    private let p2Unit = PumpUnit(serialNumber: 2000, armSoftwareVersion: 7, mspSoftwareVersion: 7)
    private let p2API = ApiVersion(major: 4, minor: 0)

    @Test func onlySixSignedWritesAreAllowed() {
        #expect(SupportMatrix.allowedSignedWrites.count == 6)
        #expect(SupportMatrix.isAllowedSignedWrite(InitiateBolusRequest()))
        #expect(SupportMatrix.isAllowedSignedWrite(DismissNotificationRequest(kind: .alert, notificationId: 1)))
        #expect(!SupportMatrix.isAllowedSignedWrite(BolusPermissionReleaseRequest(bolusID: 1)))
        #expect(!SupportMatrix.isAllowedSignedWrite(ChangeTimeDateRequest(tandemEpochTime: 0)))
        #expect(SupportMatrix.isAllowedSignedWrite(PumpVersionRequest()))  // unsigned: not the allowlist's business
        for key in SupportMatrix.allowedSignedWrites {
            #expect(key.characteristic == .control)
        }
    }

    /// A class-level rejection makes a read suspected, never unsupported, and still probe-able.
    @Test func classRejectionIsSuspectedNotUnsupported() {
        let m = SupportMatrix()
        let e = m.entry(for: LoadStatusRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5)
        #expect(e.status == .untested && e.suspected)
        #expect(e.evidence.contains { $0.note.contains("T-1") })
        #expect(m.mayProbe(LoadStatusRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5))
    }

    /// HistoryLog (op-60) is never pre-marked unsupported or suspected: it works on P1, and settling a
    /// bolus from history depends on it.
    @Test func historyLogIsNeverPreMarked() {
        let m = SupportMatrix()
        for api in [ApiVersion.v2_5, p2API, ApiVersion.v3_4] {
            let e = m.entry(for: HistoryLogRequest(), unit: nil, model: .tslim, apiVersion: api)
            #expect(e.status != .unsupported && !e.suspected, "API \(api)")
        }
        #expect(m.entry(for: HistoryLogRequest(), unit: nil, model: .tslim, apiVersion: .v2_5).status == .supported)
    }

    @Test func noClassEvidenceIsUntested() {
        let e = SupportMatrix().entry(for: LoadStatusRequest(), unit: nil, model: .tslim, apiVersion: .v3_4)
        #expect(e.status == .untested && !e.suspected && e.evidence.isEmpty)
    }

    /// Class evidence is per API version: P1's results say nothing about P2.
    @Test func classEvidenceIsScopedToItsApiVersion() {
        let m = SupportMatrix()
        #expect(m.entry(for: LastBolusStatusV2Request(), unit: nil, model: .tslim, apiVersion: .v2_5).status == .supported)
        let p2 = m.entry(for: LastBolusStatusV2Request(), unit: nil, model: .tslim, apiVersion: p2API)
        #expect(p2.status == .untested && p2.suspected)
    }

    /// Only a recorded result for the unit makes a read unsupported, and only for that unit and firmware.
    @Test func unitEvidenceDecidesAndStaysWithTheUnit() {
        var m = SupportMatrix()
        m.record(.unsupported, for: MessageKey(LoadStatusRequest.self), on: p1Unit, note: "op-77 BAD_OPCODE")
        #expect(m.entry(for: LoadStatusRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5).status == .unsupported)
        #expect(!m.mayProbe(LoadStatusRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5))
        // Same serial on new firmware starts over.
        let updated = PumpUnit(serialNumber: 1693, armSoftwareVersion: 2, mspSoftwareVersion: 1)
        #expect(m.entry(for: LoadStatusRequest(), unit: updated, model: .tslim, apiVersion: .v2_5).status == .untested)
        // The latest observation wins.
        m.record(.supported, for: MessageKey(LoadStatusRequest.self), on: p1Unit, note: "answered")
        let e = m.entry(for: LoadStatusRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5)
        #expect(e.status == .supported)
        #expect(e.evidence.first?.note == "answered")
    }

    /// Signed writes and non-reads are never probed.
    @Test func signedWritesAreNeverProbed() {
        let m = SupportMatrix()
        #expect(!m.mayProbe(DismissNotificationRequest(kind: .alert, notificationId: 1), unit: p1Unit, model: .tslim, apiVersion: .v2_5))
        #expect(!m.mayProbe(PlaySoundRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5))
    }

    /// Supported reads need no probe.
    @Test func supportedReadIsNotProbed() {
        #expect(!SupportMatrix().mayProbe(PumpVersionRequest(), unit: p1Unit, model: .tslim, apiVersion: .v2_5))
    }

    /// The six allowed writes have evidence on a t:slim X2; DismissNotification on P1 is unknown.
    @Test func allowedWritesCarryTheirEvidence() {
        let m = SupportMatrix()
        #expect(m.entry(for: CancelBolusRequest(bolusId: 1), unit: nil, model: .tslim, apiVersion: .v2_5).status == .supported)
        #expect(m.entry(for: InitiateBolusRequest(), unit: nil, model: .tslim, apiVersion: p2API).status == .supported)
        let dismissOnP1 = m.entry(for: DismissNotificationRequest(kind: .alert, notificationId: 1), unit: nil, model: .tslim, apiVersion: .v2_5)
        #expect(dismissOnP1.status == .untested && !dismissOnP1.suspected)
    }

    /// No command has both an answer and a rejection at the same scope: the compiled-in evidence
    /// must not contradict itself.
    @Test func classEvidenceDoesNotContradictItself() {
        for (key, evidence) in SupportMatrix.classEvidence {
            for scope in Set(evidence.map(\.scope)) {
                let results = Set(evidence.filter { $0.scope == scope }.map(\.result))
                #expect(results.count == 1, "\(key) at \(scope): \(results)")
            }
        }
    }

    /// Class evidence is about t:slim X2 pumps; a Mobi (or an unknown model) at the same API version
    /// gets none of it.
    @Test func classEvidenceNeedsAKnownTslim() {
        let m = SupportMatrix()
        let api = ApiVersion(major: 4, minor: 0)
        for model in [PumpModel.mobi, nil] {
            let e = m.entry(for: LastBolusStatusV2Request(), unit: nil, model: model, apiVersion: api)
            #expect(e.status == .untested && !e.suspected && e.evidence.isEmpty)
        }
    }

    /// The matrix round-trips through Codable, so the app can persist it with the pairing.
    @Test func matrixRoundTripsThroughCodable() throws {
        var m = SupportMatrix()
        m.record(.unsupported, for: MessageKey(LoadStatusRequest.self), on: p2Unit, note: "op-77", at: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(m)
        #expect(try JSONDecoder().decode(SupportMatrix.self, from: data) == m)
    }

    @Test func pumpUnitComesFromPumpVersion() {
        var cargo = [UInt8](repeating: 0, count: 48)
        cargo[0] = 9  // armSwVer
        cargo[4] = 8  // mspSwVer
        cargo[16] = 7  // serialNum
        let unit = PumpUnit(PumpVersionResponse(cargo: cargo))
        #expect(unit == PumpUnit(serialNumber: 7, armSoftwareVersion: 9, mspSoftwareVersion: 8))
    }
}
