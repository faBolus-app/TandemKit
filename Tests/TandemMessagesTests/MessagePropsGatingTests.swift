import Testing
@testable import TandemMessages

/// Contract tests for the pure device/API compatibility predicate
/// `MessageProps.isSupported(onModel:apiVersion:)` — transport-free, so the send gate's decision is
/// independent of connection state.
@Suite struct MessagePropsGatingTests {

    // A message that declares NO device/API restriction (both fields nil) is universally sendable.
    private let unrestricted = MessageProps(opCode: 0x01, type: .request)
    // SetSleepScheduleRequest is the annotated tracer: supportedDevices=[.mobi], minApi=.mobi_v3_5.
    private var mobiOnly: MessageProps { SetSleepScheduleRequest.props }

    /// nil supportedDevices + nil minApi ⇒ supported for any known model at any version (behavior-preserving).
    @Test func unrestrictedIsAlwaysSupported() {
        #expect(unrestricted.isSupported(onModel: .tslim, apiVersion: .v2_5))
        #expect(unrestricted.isSupported(onModel: .mobi, apiVersion: .mobi_v3_5))
        #expect(unrestricted.isSupported(onModel: nil, apiVersion: nil))
    }

    /// A declared incompatibility is enforced ONLY against a KNOWN target that violates it.
    @Test func declaredRestrictionGatesKnownIncompatibleTarget() {
        // Known t:slim @ v2.5: wrong device family AND below the 3.5 floor ⇒ not supported.
        #expect(mobiOnly.isSupported(onModel: .tslim, apiVersion: .v2_5) == false)
        // Known Mobi @ 3.5: right family, meets the floor ⇒ supported.
        #expect(mobiOnly.isSupported(onModel: .mobi, apiVersion: .mobi_v3_5))
        // Known Mobi @ a higher version ⇒ still supported (floor is a minimum).
        #expect(mobiOnly.isSupported(onModel: .mobi, apiVersion: .mobi_v3_8))
    }

    /// A known Mobi below the API floor is gated even though the device family matches.
    @Test func apiFloorGatesKnownBelowMinimum() {
        #expect(mobiOnly.isSupported(onModel: .mobi, apiVersion: .v3) == false) // 3.0 < 3.5
    }

    /// A fully-unknown target fails open (send-then-firmware-NACK), but a partially-known target is
    /// gated on the known dimension it violates. A known-compatible partial still fails open on the
    /// still-unknown dimension so an unknown API cannot deadlock bootstrap.
    @Test func partialTargetGatesOnKnownViolationFullyUnknownFailsOpen() {
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: nil))               // both unknown ⇒ open
        // Known API below the 3.5 floor while family is still unknown ⇒ gated (must not fail open).
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: .v2_5) == false)
        // Known t:slim (wrong family) while API is still unknown ⇒ gated.
        #expect(mobiOnly.isSupported(onModel: .tslim, apiVersion: nil) == false)
        // Known-COMPATIBLE family, API still unknown ⇒ still open (unknown API dim never deadlocks bootstrap).
        #expect(mobiOnly.isSupported(onModel: .mobi, apiVersion: nil))
    }

    /// A device-only restriction (no minApi) gates the wrong known family but fails open on unknown api.
    @Test func deviceOnlyRestriction() {
        let deviceOnly = MessageProps(opCode: 0x02, type: .request, supportedDevices: [.mobi])
        #expect(deviceOnly.isSupported(onModel: .tslim, apiVersion: .v2_5) == false)
        #expect(deviceOnly.isSupported(onModel: .mobi, apiVersion: .v2_5))
        #expect(deviceOnly.isSupported(onModel: nil, apiVersion: nil))
    }

    /// ApiVersion ordering is major-then-minor (Comparable), the basis of the minApi floor check.
    @Test func apiVersionOrdering() {
        #expect(ApiVersion.v2_5 < ApiVersion.mobi_v3_5)
        #expect(ApiVersion.v3_2 < ApiVersion.v3_4)
        #expect(ApiVersion.mobi_v3_8 < ApiVersion.future)
        #expect(!(ApiVersion.mobi_v3_5 < ApiVersion.mobi_v3_5))
    }

    // MARK: - Nine API-2.5 op-77 signed writes carry `.benchConservativeUnverifiedFloor`
    //
    // Each of these MessageProps declares `minApi: .benchConservativeUnverifiedFloor` (= .v3_4).
    // A known below-floor apiVersion is gated; a nil apiVersion still fails open.
    @Test func nineSignedWritesCarryTheConservativeFloor() {
        let floored: [MessageProps] = [
            SetLowInsulinAlertRequest.props,
            SetAutoOffAlertRequest.props,
            ChangeControlIQSettingsRequest.props,
            UserInteractionRequest.props,
            SetMaxBolusLimitRequest.props,
            SetMaxBasalLimitRequest.props,
            PlaySoundRequest.props,
            SetPumpSoundsRequest.props,
            ChangeTimeDateRequest.props,
        ]
        for props in floored {
            #expect(props.minApi == .benchConservativeUnverifiedFloor)
            // Known below-floor apiVersion (2.5, the bench-observed op-77 firmware) ⇒ gated (no-send).
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v2_5) == false)
            // Known at-floor apiVersion ⇒ supported (floor is inclusive minimum).
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v3_4))
            // Unknown apiVersion ⇒ fails open (apiVersion is still nil at every call site).
            #expect(props.isSupported(onModel: .tslim, apiVersion: nil))
        }
    }

    // MARK: - Bench-observed op-77-class reads carry the same conservative floor
    //
    // Same assertion shape as the writes above: known below-floor apiVersion is gated; nil fails open.
    @Test func benchObservedReadsCarryTheConservativeFloor() {
        let flooredReads: [MessageProps] = [
            LoadStatusRequest.props,
            ExtendedBolusStatusV2Request.props,
            TempRateStatusRequest.props,
            BasalIQStatusRequest.props,
            BasalIQSettingsRequest.props,
            BasalIQAlertInfoRequest.props,
            BleSoftwareInfoRequest.props,
            SecretMenuRequest.props,
            HistoryLogRequest.props,
            IDPSettingsRequest.props,
            IDPSegmentRequest.props,
            CreateHistoryLogRequest.props,
            StreamDataReadinessRequest.props,
        ]
        for props in flooredReads {
            #expect(props.minApi == .benchConservativeUnverifiedFloor)
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v2_5) == false)
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v3_4))
            #expect(props.isSupported(onModel: .tslim, apiVersion: nil))
        }
    }

    // MARK: - Auto-adjustment-mode reads carry the Control-IQ-era floor
    //
    // `HighestAamRequest` (op120) and `ActiveAamBitsRequest` (op146) are Control-IQ-era reads that
    // op-77 and tear the BLE link on an API-2.5 t:slim. Both carry `.mobi_v3_5`. This floor only
    // bites once a call site supplies a known apiVersion — fail-open on nil is preserved.
    @Test func aamReadsCarryTheControlIQEraFloor() {
        let aamReads: [MessageProps] = [
            HighestAamRequest.props,      // op120 — same AAM family as ActiveAamBits; floored together
            ActiveAamBitsRequest.props,   // op146/0x92 — upstream minApi = MOBI_API_V3_5
        ]
        for props in aamReads {
            #expect(props.minApi == .mobi_v3_5)
            // Known below-floor apiVersion (2.5, the flapping pump's firmware) ⇒ gated (no-send).
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v2_5) == false)
            // Known at-floor apiVersion ⇒ supported (floor is inclusive minimum).
            #expect(props.isSupported(onModel: .tslim, apiVersion: .mobi_v3_5))
            // Unknown apiVersion ⇒ fails open (apiVersion is still nil at every call site).
            #expect(props.isSupported(onModel: .tslim, apiVersion: nil))
            // AAM is API-gated, NOT device-gated: no supportedDevices restriction (a Control-IQ t:slim at a
            // high-enough API may support it) — so a KNOWN model alone never gates it.
            #expect(props.supportedDevices == nil)
        }
    }

    // MARK: - CONTROL_STREAM cartridge-fill state responses must be signed+stream
    //
    // Omitting `signed:`/`stream:` on 0xE1/0xE3/0xE5/0xE7/0xE9 silently skips HMAC verification
    // and the 24-byte auth-trailer strip — a forged cartridge-fill progress frame would decode as trusted.
    @Test func controlStreamStateResponsesAreSignedAndStream() {
        let props: [MessageProps] = [
            EnterChangeCartridgeModeStateStreamResponse.props,
            DetectingCartridgeStateStreamResponse.props,
            FillTubingStateStreamResponse.props,
            FillCannulaStateStreamResponse.props,
            ExitFillTubingModeStateStreamResponse.props,
        ]
        for p in props {
            #expect(p.signed == true)
            #expect(p.stream == true)
        }
    }
}
