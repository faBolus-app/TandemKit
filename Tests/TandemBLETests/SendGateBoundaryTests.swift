import Testing
import TandemMessages
@testable import TandemBLE

/// Send-path boundary tests for the device/API send gate (workstream B / D-08). The gate lives at
/// `PumpBLEClient.send` — NOT `PumpTransactionCoordinator` (D-05) — and is checked BEFORE the readiness
/// guard, so a KNOWN-incompatible message is refused with `.unsupportedOnDevice` even with no live
/// connection, while a permitted message falls through to the readiness guard and throws `.notReady`.
/// That `.unsupportedOnDevice` (gated) vs `.notReady` (would-be-emitted) split is what makes the gate
/// observable in a unit test without a peripheral (mirrors `WritePolicyInterlockTests`, which asserts the
/// pure decision to avoid `.notReady` masking a wrongly-permitted send).
///
/// RED proof (additive, no source mutation of the dose-path file): before the gate is wired into `send`,
/// a KNOWN-t:slim SetSleepScheduleRequest is NOT gated — `send` reaches the readiness guard and throws
/// `.notReady`, so `knownTslimGatesMobiOnlySend` fails RED; after the gate is added it passes GREEN.
@Suite struct SendGateBoundaryTests {

    // SetSleepScheduleRequest is annotated MOBI_ONLY + minApi .mobi_v3_5 (opcode 0xCE); it is signed
    // control (.settings), so .allowNonDelivery is the minimal policy that clears the write interlock and
    // lets execution actually reach the device/API gate.
    private func mobiOnlyMessage() -> SetSleepScheduleRequest {
        SetSleepScheduleRequest(slot: 0, schedule: [0, 0, 0, 0, 0, 0], flag: 0)
    }

    /// KNOWN t:slim (@ v2.5): a MOBI_ONLY message is GATED — refused with `.unsupportedOnDevice`, no bytes
    /// emitted (the gate precedes the readiness guard, so the refusal is not masked by `.notReady`).
    @MainActor @Test func knownTslimGatesMobiOnlySend() {
        let client = PumpBLEClient()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .tslim, apiVersion: .v2_5)
        #expect(throws: PumpBLEClient.ClientError.unsupportedOnDevice(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// KNOWN Mobi (@ 3.5): the message IS supported — it passes the gate and falls through to the
    /// readiness guard, throwing `.notReady` (no connection in a unit test). Not `.unsupportedOnDevice`:
    /// a supported send is emitted-path, never gated.
    @MainActor @Test func knownMobiPermitsMobiOnlySend() {
        let client = PumpBLEClient()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// KNOWN Mobi BELOW the API floor (@ 3.0 < 3.5): gated on the minApi floor even though the family matches.
    @MainActor @Test func knownMobiBelowApiFloorIsGated() {
        let client = PumpBLEClient()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .v3)
        #expect(throws: PumpBLEClient.ClientError.unsupportedOnDevice(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// UNKNOWN target (no device context set): fail-OPEN — the send is NOT gated, so it reaches the
    /// readiness guard and throws `.notReady`, exactly as before the gate existed. No currently-working
    /// send regresses.
    @MainActor @Test func unknownTargetFailsOpen() {
        let client = PumpBLEClient()
        client.writePolicy = .allowNonDelivery
        // deliberately no setDeviceContext — model/api stay nil (unidentified)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// The device/API gate does not usurp the write-policy interlock: a MOBI_ONLY message to a KNOWN Mobi
    /// under the default `.readOnly` policy is still refused by `writeBlocked` (authorization is checked
    /// first), proving the gate is additive to — not a replacement for — the existing send interlock.
    @MainActor @Test func writePolicyInterlockStillPrecedesGate() {
        let client = PumpBLEClient()                       // default .readOnly
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5)
        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }
}
