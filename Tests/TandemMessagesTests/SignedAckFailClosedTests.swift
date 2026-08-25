import Testing
@testable import TandemMessages

/// VA-20: the two accept-bearing signed dose-acks must fail CLOSED — never decode as accepted/granted, and
/// never trap — when constructed from a buffer shorter than their declared size. This is unreachable via
/// `ResponseParser` (it length-guards the cargo and VA-04 HMAC-verifies a signed response before `make`),
/// so these pins guard a DIRECT caller / future refactor: a truncated frame must not read as an authoritative
/// accepted bolus or granted permission, and `Bytes.read*`'s `precondition` must not crash the process.
struct SignedAckFailClosedTests {

    @Test func initiateBolusResponseShortBufferIsNotAccepted() {
        // size is 6; every shorter buffer must be not-accepted (and must not trap).
        for short: [UInt8] in [[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0, 0]] {
            #expect(!InitiateBolusResponse(cargo: short).accepted)
        }
        // A full, status-0 buffer still decodes as accepted (no regression to the happy path).
        #expect(InitiateBolusResponse(cargo: [0, 0, 0, 0, 0, 0]).accepted)
        #expect(!InitiateBolusResponse(cargo: [1, 0, 0, 0, 0, 0]).accepted)  // status != 0 ⇒ not accepted
    }

    @Test func bolusPermissionResponseShortBufferIsNotGranted() {
        for short: [UInt8] in [[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0, 0]] {
            #expect(!BolusPermissionResponse(cargo: short).granted)
        }
        #expect(BolusPermissionResponse(cargo: [0, 0, 0, 0, 0, 0]).granted)
        #expect(!BolusPermissionResponse(cargo: [1, 0, 0, 0, 0, 0]).granted)
    }

    // CX-T-12: SuspendPumpingResponse/ResumePumpingResponse/SetTempRateResponse must also fail CLOSED on a
    // short/empty cargo — today an empty buffer leaves `status` at its default 0 (== accepted), which is
    // exactly backwards for a signed dose-affecting ack decoded from attacker/test-controlled bytes.

    @Test func suspendPumpingResponseShortBufferIsNotAccepted() {
        // size is 1; only the empty buffer is "short" for this type.
        #expect(!SuspendPumpingResponse(cargo: []).accepted)
        // Full-length, status-0 buffer still decodes accepted (no regression).
        #expect(SuspendPumpingResponse(cargo: [0]).accepted)
        #expect(!SuspendPumpingResponse(cargo: [1]).accepted)
    }

    @Test func resumePumpingResponseShortBufferIsNotAccepted() {
        #expect(!ResumePumpingResponse(cargo: []).accepted)
        #expect(ResumePumpingResponse(cargo: [0]).accepted)
        #expect(!ResumePumpingResponse(cargo: [1]).accepted)
    }

    @Test func setTempRateResponseShortBufferIsNotAccepted() {
        // size is 4; every shorter buffer (including the one-byte-short case) must be not-accepted.
        for short: [UInt8] in [[], [0], [0, 0], [0, 0, 0]] {
            #expect(!SetTempRateResponse(cargo: short).accepted)
        }
        // Full-length, status-0 buffer still decodes accepted (no regression).
        #expect(SetTempRateResponse(cargo: [0, 0, 0, 0]).accepted)
        #expect(!SetTempRateResponse(cargo: [1, 0, 0, 0]).accepted)
    }

    // CX-T-02: a signed response with status==0 but a nonzero denial field (nackReasonId /
    // statusTypeId) is a DENIAL, not a grant/accept. Collapsing the gate to `status == 0` alone
    // accepts a response the pump is using to say "no". `granted`/`accepted` must gate on the
    // denial field too — status==0 && denialField==0 — so an unknown/nonzero denial code fails
    // CLOSED even though the leading status byte is zero.

    @Test func bolusPermissionResponseStatusZeroWithNackReasonIsNotGranted() {
        // status==0, bolusId==0, nackReasonId!=0 (byte index 5) ⇒ NOT granted despite status==0.
        #expect(!BolusPermissionResponse(cargo: [0, 0, 0, 0, 0, 7]).granted)
        // status==0, nackReasonId==0 ⇒ granted (no regression to the happy path).
        #expect(BolusPermissionResponse(cargo: [0, 0, 0, 0, 0, 0]).granted)
    }

    @Test func initiateBolusResponseStatusZeroWithStatusTypeIdIsNotAccepted() {
        // status==0, bolusId==0, statusTypeId!=0 (byte index 5) ⇒ NOT accepted despite status==0.
        #expect(!InitiateBolusResponse(cargo: [0, 0, 0, 0, 0, 3]).accepted)
        // status==0, statusTypeId==0 ⇒ accepted (no regression to the happy path).
        #expect(InitiateBolusResponse(cargo: [0, 0, 0, 0, 0, 0]).accepted)
    }
}
