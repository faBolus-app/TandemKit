import Testing
import TandemMessages
@testable import TandemBLE

/// The device/API send gate at `PumpBLEClient.send` runs before the readiness guard, so a known-
/// incompatible message is refused with `.unsupportedOnDevice` even with no live connection.
/// Model-restricted sends fail closed on an unidentified or untrusted identity; unrestricted
/// messages still fail open. Opcodes are not globally unique — the gate keys by `(characteristic, opCode)`.
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

    /// Unknown target (no device context): fail-closed — refused pre-write with `.identityNotEstablished`.
    @MainActor @Test func unknownTargetFailsClosedForModelRestrictedSend() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        // deliberately no setDeviceContext — model/api/trust stay nil/false (unidentified)
        #expect(throws: PumpBLEClient.ClientError.identityNotEstablished(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// A non-nil but untrusted model (heuristic misread) must fail closed: the identity gate keys on
    /// trust, not on `connectedPumpModel != nil`. Gating only on a non-nil model would fail open on a wrong identity.
    @MainActor @Test func untrustedHeuristicMobiIsGatedForModelRestrictedSend() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: false)
        #expect(throws: PumpBLEClient.ClientError.identityNotEstablished(opcode: 0xCE)) {
            try client.send(self.mobiOnlyMessage())
        }
    }

    /// A trusted, known-compatible model reaches the readiness guard (`.notReady`), never the identity gate.
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

    /// An unrestricted message (`supportedDevices == nil`) on an untrusted/unidentified target still
    /// fails open through the identity gate to `.notReady`. The identity gate must never catch an
    /// unrestricted message just because the target is untrusted.
    @MainActor @Test func unrestrictedMessageStillFailsOpenOnUnidentifiedTarget() {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowBenignControl   // permits this message's .benign risk
        // deliberately no setDeviceContext — model/api/trust stay nil/false (unidentified, untrusted)
        #expect(throws: PumpBLEClient.ClientError.notReady) {
            try client.send(DismissNotificationRequest(kind: .alert, notificationId: 1))
        }
    }

    /// The write-policy interlock still precedes the identity gate even when identity is untrusted —
    /// a denying policy throws `.writeBlocked` first, never `.identityNotEstablished`.
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

    // MARK: - Model-restricted catalog

    /// The 16 model-restricted messages, derived from each type's own static `.props` (never a
    /// hand-typed opcode). 14 control/delivery + 2 reads, all `[.mobi]`-only.
    private static let modelRestrictedControlDeliveryMessages: [any Message] = [
        SuspendPumpingRequest(), ResumePumpingRequest(),
        SetTempRateRequest(), StopTempRateRequest(),
        SetModesRequest(), SetActiveIDPRequest(),
        EnterFillTubingModeRequest(), FillCannulaRequest(),
        CreateIDPRequest(), DeleteIDPRequest(), RenameIDPRequest(),
        SetIDPSegmentRequest(), SetIDPSettingsRequest(),
        SetSleepScheduleRequest(),
    ]
    private static let modelRestrictedReadMessages: [any Message] = [
        CgmStatusV2Request(), UnknownMobiOpcode110Request(),
    ]

    /// Every model-restricted control/delivery message, and the 2 model-restricted reads, is refused
    /// pre-write with `.identityNotEstablished` on an untrusted/unidentified target — driven from each
    /// type's actual `.props`, never a hand-typed opcode.
    @MainActor @Test func allModelRestrictedControlDeliveryMessagesAreGatedOnUntrustedIdentity() {
        for message in Self.modelRestrictedControlDeliveryMessages {
            let client = PumpBLEClient.forUnitTest()
            client.writePolicy = .allowNonDelivery
            // deliberately no setDeviceContext — model/api/trust stay nil/false (unidentified)
            #expect(client.identityGateError(for: message) == .identityNotEstablished(opcode: message.opCode),
                    "\(type(of: message)) (opcode \(message.opCode)) must be gated on an untrusted identity")
        }
    }

    /// The 2 model-restricted reads are also refused pre-write on an untrusted/unidentified target
    /// (neither is in `SendGateBootstrapAllowlist`).
    @MainActor @Test func modelRestrictedReadsAreGatedOnUntrustedIdentityUnderSB() {
        for message in Self.modelRestrictedReadMessages {
            let client = PumpBLEClient.forUnitTest()
            #expect(client.identityGateError(for: message) == .identityNotEstablished(opcode: message.opCode),
                    "\(type(of: message)) (opcode \(message.opCode)) must be gated on an untrusted identity under S-B")
        }
    }

    /// Opcode 0xA4 is shared by `LastBolusStatusV2Request` (`.currentStatus` read, unrestricted) and
    /// `SetTempRateRequest` (`.control` Mobi-only delivery). Allowlisting the read's `(characteristic, opCode)`
    /// must never exempt the delivery side.
    @MainActor @Test func allowlistingTheCollidingReadOpcodeNeverExemptsTheCollidingDeliveryOpcode() {
        #expect(LastBolusStatusV2Request.props.opCode == SetTempRateRequest.props.opCode)
        #expect(SetTempRateRequest.props.characteristic == .control)
        #expect(SetTempRateRequest.props.operationRisk == .delivery)

        let client = PumpBLEClient.forUnitTest()
        // Allowlist ONLY the READ side's compound key (.currentStatus, 0xA4) — the colliding opcode.
        client.bootstrapAllowlistOverrideForTesting = [
            SendGateAllowlistKey(characteristic: .currentStatus, opCode: LastBolusStatusV2Request.props.opCode)
        ]
        // The DELIVERY side, at the SAME raw opcode but a DIFFERENT characteristic, is still refused.
        #expect(client.identityGateError(for: SetTempRateRequest()) ==
                    .identityNotEstablished(opcode: SetTempRateRequest.props.opCode),
                "allowlisting the (.currentStatus, 0xA4) read key must never exempt the (.control, 0xA4) delivery command")
    }

    /// A model-restricted read whose compound key is injected into the debug override, with
    /// `operationRisk == .read`, fails open on an untrusted target — proving the allowlist branch is
    /// reachable. The same raw opcode on a `.control` message is still refused: the allowlist names one
    /// exact `(characteristic, opCode)` pair, never a bare opcode.
    @MainActor @Test func allowlistedBootstrapReadStillFailsOpenOnUnidentifiedTarget() {
        let client = PumpBLEClient.forUnitTest()
        let readMessage = CgmStatusV2Request()
        let key = SendGateAllowlistKey(characteristic: readMessage.characteristic, opCode: readMessage.opCode)
        client.bootstrapAllowlistOverrideForTesting = [key]

        #expect(readMessage.operationRisk == .read)
        #expect(client.identityGateError(for: readMessage) == nil,
                "an allowlisted (Characteristic, opCode) key must fail OPEN for a .read-risk message")

        // The production allowlist itself stays empty — only the test override is non-empty.
        #expect(SendGateBootstrapAllowlist.entries.isEmpty)

        // The SAME key on a .control message (constructed via the override with a mismatched risk) is still
        // refused: SetTempRateRequest's own key is (.control, 0xA4) — different from readMessage's
        // (.currentStatus, 0xBE) — so it is not exempted by this override at all, reinforcing that the
        // allowlist can only ever name one exact (characteristic, opCode) pair, never a bare opcode.
        #expect(client.identityGateError(for: SetTempRateRequest()) ==
                    .identityNotEstablished(opcode: SetTempRateRequest.props.opCode))
    }

    /// An awaited send that is identity-refused leaves no pending coordinator entry — the pre-write
    /// throw never registers a transaction.
    @MainActor @Test func identityRefusalLeavesNoTransactionPending() async {
        let client = PumpBLEClient.forUnitTest()
        client.writePolicy = .allowNonDelivery
        client.setDeviceContext(model: .mobi, apiVersion: .mobi_v3_5, trusted: false)
        await #expect(throws: PumpBLEClient.ClientError.identityNotEstablished(opcode: 0xCE)) {
            try await client.sendAwaitingResponse(self.mobiOnlyMessage(), deadline: 5)
        }
        #expect(client.transactions.inFlightCount == 0,
                "a pre-write identity refusal must never register a pending transaction")
    }
}
