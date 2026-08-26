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
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .tslim, apiVersion: .v2_5, trusted: true)
        #expect(throws: PumpBLEClient.ClientError.unsupportedOnDevice(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// KNOWN Mobi (@ 3.5): the message IS supported — it passes the gate and falls through to the
    /// readiness guard, throwing `.notReady` (no connection in a unit test). Not `.unsupportedOnDevice`:
    /// a supported send is emitted-path, never gated.
    @MainActor @Test func knownMobiPermitsMobiOnlySend() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: true)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// KNOWN Mobi BELOW the API floor (@ 3.0 < 3.5): gated on the minApi floor even though the family matches.
    @MainActor @Test func knownMobiBelowApiFloorIsGated() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .v3, trusted: true)
        #expect(throws: PumpBLEClient.ClientError.unsupportedOnDevice(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// UNKNOWN target (no device context set): CC-06 (REMED-15.5) fail-CLOSED for the tracer message — the
    /// send is refused pre-write with `.identityNotEstablished`, no bytes emitted. (Was `.notReady` before
    /// the trusted-identity gate existed; this is the RED→GREEN flip that proves the mechanism end-to-end.)
    @MainActor @Test func unknownTargetFailsOpen() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        // deliberately no setDeviceContext — model/api/trust stay nil/false (unidentified)
        #expect(throws: PumpBLEClient.ClientError.identityNotEstablished(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// The codex C1 hazard, reproduced and closed: a t:slim silently reconnects and op33's ambiguous
    /// API-version heuristic misreads it as Mobi — `connectedPumpModel` is non-nil but WRONG, and
    /// `trusted: false` records that the caller never actually identified it. Before CC-06, `deviceSupportError`
    /// alone would return `nil` here (`.mobi` IS in `supportedDevices`), so the gate failed OPEN on a wrong
    /// identity. CC-06 must gate this — proving the fix keys on trust, not on `connectedPumpModel != nil`.
    @MainActor @Test func untrustedHeuristicMobiIsGatedForModelRestrictedSend() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: false)
        #expect(throws: PumpBLEClient.ClientError.identityNotEstablished(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// A TRUSTED, known-compatible model is unchanged by CC-06: the Mobi-only message reaches the
    /// readiness guard (`.notReady`), never the identity gate — the trusted-and-known happy path is
    /// unaffected by the new trust signal.
    @MainActor @Test func trustedMobiPermitsMobiOnlySendUnchanged() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: true)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// The device/API gate does not usurp the write-policy interlock: a MOBI_ONLY message to a KNOWN Mobi
    /// under the default `.readOnly` policy is still refused by `writeBlocked` (authorization is checked
    /// first), proving the gate is additive to — not a replacement for — the existing send interlock.
    @MainActor @Test func writePolicyInterlockStillPrecedesGate() {
        let client = PumpBLEClient.forUnitTest()                       // default .readOnly
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: true)
        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// No-regression proof (RESEARCH Pitfall #2 — guard-order regression): an UNRESTRICTED message
    /// (`supportedDevices == nil`) sent to an untrusted/unidentified target is STILL permitted — it falls
    /// through `identityGateError` (which fails open on `supportedDevices == nil`) to the readiness guard
    /// and throws `.notReady`, exactly as before CC-06. The new identity gate must never catch an
    /// unrestricted message just because the target is untrusted.
    @MainActor @Test func unrestrictedMessageStillFailsOpenOnUnidentifiedTarget() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowBenignControl   // permits this message's .benign risk
        // deliberately no setDeviceContext — model/api/trust stay nil/false (unidentified, untrusted)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(DismissNotificationRequest(kind: .alert, notificationId: 1))
        }
    }

    /// No-regression proof (codex C1 precedence completeness / RESEARCH Pitfall #5): the write-policy
    /// interlock (`authorizationError`) still precedes the CC-06 identity gate even when identity is
    /// UNTRUSTED — a denying policy throws `.writeBlocked` FIRST, never `.identityNotEstablished`, for
    /// both an unidentified target (nil model) and an identified-but-UNTRUSTED one (`trusted: false`).
    /// Proves the new gate did not invert the pre-existing authorization precedence.
    @MainActor @Test func writePolicyInterlockStillPrecedesGateEvenWhenUntrusted() {
        let unidentified = PumpBLEClient.forUnitTest()                 // default .readOnly, no device context
        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: 0xCE)) {
            try unidentified.send(self.mobiOnlyMessage())
        }

        let untrustedMobi = PumpBLEClient.forUnitTest()                // default .readOnly
        untrustedMobi.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: false)
        #expect(throws: PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: 0xCE)) {
            try untrustedMobi.send(self.mobiOnlyMessage())
        }
    }
}
