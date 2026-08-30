import Testing
@testable import TandemMessages

/// Regression tests for **F2** of debug session `pump-software-4-0-unknown-version`.
///
/// A real t:slim X2 in the field reported API version **4.0** — above every entry in the `ApiVersion`
/// table (which tops out at `.mobi_v3_8`). Because `MessageProps.isSupported` tests only
/// `apiVersion < minApi` (a lower bound, with no notion of an unclassifiable version), a pump above the
/// whole table satisfies **every** declared floor. Five Mobi-era messages relied on `minApi: .mobi_v3_5`
/// as a *de-facto* device-family gate while declaring no `supportedDevices`, so on that pump they became
/// sendable to a t:slim for the first time.
///
/// F2 moves that restriction onto the axis it actually belongs to: `supportedDevices: [.mobi]`.
///
/// **Scope — exactly three messages, and why not five.** Only messages whose Mobi restriction is
/// INHERITED from upstream pumpX2's `MOBI_API_V3_5` tagging are covered. The two AAM reads that also carry
/// `.mobi_v3_5` (`HighestAamRequest` op-120, `ActiveAamBitsRequest` op-146) are deliberately EXCLUDED: that
/// floor is this repo's own Control-IQ-era proxy, not an upstream device-family claim, and
/// `MessagePropsGatingTests.aamReadsCarryTheControlIQEraFloor()` affirmatively asserts
/// `supportedDevices == nil` for both because a Control-IQ t:slim at a high-enough API may legitimately
/// support them. That contract was set with more evidence than this session had; it wins. The exposure it
/// leaves on an above-table pump is recorded in the session file as residual, needing fail-closed version
/// classification rather than a device tag.
///
/// **What these tests are and are not.** The oracle is DERIVED from the project's documented fail-safe
/// contract (an unproven restriction fails SAFE = no-send), not observed from hardware. See the session
/// file for the kept message where that inherited claim is weakest — `LastBolusStatusV3Request`, which a
/// sibling session is separately considering sending to a t:slim.
@Suite struct MobiOnlyModelAxisGateTests {

    /// The above-the-whole-table version this pump actually reported. Deliberately built with the
    /// initializer rather than a named constant, because the point is that it has no named constant.
    private let apiV4 = ApiVersion(major: 4, minor: 0)

    /// The three formerly un-tagged, upstream-MOBI_ONLY messages, by name for legible failure output.
    /// The AAM pair is intentionally absent — see the suite doc comment.
    private var subjects: [(String, MessageProps)] {
        [
            ("SetG6TransmitterIdRequest", SetG6TransmitterIdRequest.props),
            ("DisconnectPumpRequest", DisconnectPumpRequest.props),
            ("LastBolusStatusV3Request", LastBolusStatusV3Request.props),
        ]
    }

    // MARK: - The RED assertion (the actual defect)

    /// THE DEFECT: a Mobi-era message must not be sendable to a KNOWN t:slim just because the pump's
    /// API version happens to sit above the known table. Before F2 all five returned `true` here.
    @Test func mobiEraMessagesAreRefusedOnTslimAtAboveTableVersion() {
        for (name, props) in subjects {
            #expect(
                props.isSupported(onModel: .tslim, apiVersion: apiV4) == false,
                "\(name) must be refused on a t:slim at API 4.0: a version above the known table must not be read as 'supports everything'")
        }
    }

    // MARK: - Positive control (proves the mechanism, not just the outcome)

    /// `SetSleepScheduleRequest` was ALREADY tagged `supportedDevices: [.mobi]`. It was correctly refused
    /// at API 4.0 before F2 and after it. Its contrast with the five above is the whole proof that the
    /// only thing separating "refused" from "permitted" on this pump was the missing model-axis tag.
    @Test func alreadyTaggedTracerWasNeverAffected() {
        #expect(SetSleepScheduleRequest.props.isSupported(onModel: .tslim, apiVersion: apiV4) == false)
    }

    // MARK: - No-regression guards (must hold both before AND after F2)

    /// A real Mobi must be entirely unaffected — including one at the same above-table version, so the
    /// fix cannot be mistaken for "refuse everything unfamiliar".
    @Test func realMobiIsUnaffected() {
        for (name, props) in subjects {
            #expect(props.isSupported(onModel: .mobi, apiVersion: .mobi_v3_5), "\(name) @ Mobi 3.5")
            #expect(props.isSupported(onModel: .mobi, apiVersion: .mobi_v3_8), "\(name) @ Mobi 3.8")
            #expect(props.isSupported(onModel: .mobi, apiVersion: apiV4), "\(name) @ Mobi 4.0 must stay sendable")
        }
    }

    /// Boundary neighbours either side of the 3.5 floor, plus the bench-evidenced 2.5 pump. These were
    /// already refused via the API floor before F2 and stay refused via the model axis after it — which is
    /// precisely why F2 changes no observable behaviour for any pump at or below API 3.4.
    @Test func tslimBelowTheFloorWasAlreadyRefusedAndStaysRefused() {
        for (name, props) in subjects {
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v2_5) == false, "\(name) @ t:slim 2.5")
            #expect(props.isSupported(onModel: .tslim, apiVersion: .v3_4) == false, "\(name) @ t:slim 3.4")
        }
    }

    /// The API floor must still bite on the model's own family: a Mobi below its floor stays refused, so
    /// F2 adds the model axis without disabling the version axis.
    @Test func apiFloorStillAppliesWithinTheMobiFamily() {
        for (name, props) in subjects {
            #expect(props.isSupported(onModel: .mobi, apiVersion: .v3_4) == false, "\(name) @ Mobi 3.4")
        }
    }

    // MARK: - The deliberate exclusion (guards against re-tagging the AAM pair)

    /// The AAM pair must remain device-UNgated. This duplicates
    /// `MessagePropsGatingTests.aamReadsCarryTheControlIQEraFloor()` on purpose: this suite is where the
    /// temptation to tag them lives, so the prohibition belongs here too. If a capture ever proves a
    /// Control-IQ t:slim refuses AAM, change it deliberately in both places — not to silence a failure.
    @Test func aamPairIsIntentionallyNotModelGated() {
        #expect(HighestAamRequest.props.supportedDevices == nil)
        #expect(ActiveAamBitsRequest.props.supportedDevices == nil)
        // And therefore still permitted on a t:slim at the above-table version — the residual exposure.
        #expect(HighestAamRequest.props.isSupported(onModel: .tslim, apiVersion: ApiVersion(major: 4, minor: 0)))
        #expect(ActiveAamBitsRequest.props.isSupported(onModel: .tslim, apiVersion: ApiVersion(major: 4, minor: 0)))
    }

    // MARK: - Documented residual (F1 territory — intentionally NOT fixed by F2)

    /// F2 does not close the fail-open on an UNKNOWN model: with `model == nil` the device dimension is
    /// skipped by design, so these stay sendable. This is recorded as an executable statement of the
    /// remaining exposure, which only F1 (version classification + fail-closed) addresses. If a future
    /// change makes this refuse, that is an improvement — update this test deliberately, do not delete it.
    @Test func unknownModelStillFailsOpenPendingF1() {
        for (name, props) in subjects {
            #expect(props.isSupported(onModel: nil, apiVersion: apiV4), "\(name): documented fail-open on nil model")
        }
    }
}
