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

    /// Fail-OPEN: an unknown model and/or unknown apiVersion is never gated — preserves today's
    /// send-then-firmware-NACK behavior; only a KNOWN target can trip a restriction.
    @Test func unknownTargetFailsOpen() {
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: nil))          // both unknown
        #expect(mobiOnly.isSupported(onModel: nil, apiVersion: .v2_5))        // model unknown
        #expect(mobiOnly.isSupported(onModel: .tslim, apiVersion: nil))       // version unknown
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
}
