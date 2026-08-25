import Testing
@testable import TandemMessages

/// Contract tests for the pure device/API compatibility predicate `MessageProps.isSupported(onModel:apiVersion:)`
/// (workstream B / D-08). These assert the predicate directly — transport-free, deterministic — so the send
/// gate's decision is provable independent of connection state.
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

    /// VA-06: a FULLY-unknown target fails open (send-then-firmware-NACK), but a partially-known target is
    /// now gated on the KNOWN dimension it violates — the old combined-guard fail-open (which required BOTH
    /// dimensions known before gating either) is closed. A known-COMPATIBLE partial still fails open on the
    /// still-unknown dimension (so an unknown API can't deadlock bootstrap).
    @Test func partialTargetGatesOnKnownViolationFullyUnknownFailsOpen() {
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: nil))               // both unknown ⇒ open
        // Known API below the 3.5 floor while family is still unknown ⇒ GATED (was fail-open pre-VA-06).
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: .v2_5) == false)
        // Known t:slim (wrong family) while API is still unknown ⇒ GATED (was fail-open pre-VA-06).
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

    // MARK: - C4-01/CX-T-03: the 9 API-2.5 op-77 signed writes carry `.benchConservativeUnverifiedFloor`
    //
    // Ported from experimental@245b531 (port-fidelity restoration, Phase 15 Plan 01). Each of these
    // MessageProps now declares `minApi: .benchConservativeUnverifiedFloor` (= .v3_4). Per-write assertion
    // proves the gate reports unsupported for a below-floor KNOWN apiVersion and supported (fail-open) for
    // a nil apiVersion — mirroring `apiFloorGatesKnownBelowMinimum` / `partialTargetGatesOnKnownViolationFullyUnknownFailsOpen`
    // above. Runtime app behavior is unchanged: apiVersion is still nil at every call site (CX-T-04 deferred).
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
            // Unknown apiVersion ⇒ fails open (apiVersion is nil at every call site today — CX-T-04 deferred).
            #expect(props.isSupported(onModel: .tslim, apiVersion: nil))
        }
    }

    // MARK: - C4-02: the bench-observed op-77-class reads carry the same conservative floor
    //
    // Shipping-metadata additions (distinct provenance from C4-01 — not a cherry-pick): sourced from
    // experimental's `BenchCommandCatalog.benchObservedUnsupported` list (T-1, tslim API ≤2.5). Same
    // assertion shape as the writes above.
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
}
