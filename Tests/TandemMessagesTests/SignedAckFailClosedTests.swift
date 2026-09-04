import Testing
@testable import TandemMessages

/// Truncated cargo for the two accept-bearing signed dose-acks must decode as not-accepted / not-granted
/// and must not trap. `ResponseParser` length-guards and HMAC-verifies before `make`, so this pins a
/// direct caller / future refactor: a short buffer must not read as an authoritative accepted bolus.
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

    // Truncated cargo for Suspend/Resume/SetTempRate must also fail closed — an empty buffer leaving
    // `status` at default 0 would decode as accepted.

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

    // A signed response with status==0 but a nonzero denial field is a denial, not a grant.
    // `granted`/`accepted` must require status==0 && denialField==0 so an unknown/nonzero denial fails closed.

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

    // Remaining delivery-affecting signed CONTROL acks: short/empty cargo must decode as not-accepted
    // (and must not trap); a full-length status-0 buffer must still decode accepted.

    @Test func stopTempRateResponseShortBufferIsNotAccepted() {
        for short: [UInt8] in [[], [0], [0, 0]] {  // size 3
            #expect(!StopTempRateResponse(cargo: short).accepted)
        }
        #expect(StopTempRateResponse(cargo: [0, 0, 0]).accepted)
        #expect(!StopTempRateResponse(cargo: [1, 0, 0]).accepted)
    }

    @Test func enterChangeCartridgeModeResponseShortBufferIsNotAccepted() {  // size 1
        #expect(!EnterChangeCartridgeModeResponse(cargo: []).accepted)
        #expect(EnterChangeCartridgeModeResponse(cargo: [0]).accepted)
        #expect(!EnterChangeCartridgeModeResponse(cargo: [1]).accepted)
    }

    @Test func enterFillTubingModeResponseShortBufferIsNotAccepted() {  // size 1
        #expect(!EnterFillTubingModeResponse(cargo: []).accepted)
        #expect(EnterFillTubingModeResponse(cargo: [0]).accepted)
        #expect(!EnterFillTubingModeResponse(cargo: [1]).accepted)
    }

    @Test func fillCannulaResponseShortBufferIsNotAccepted() {  // size 1
        #expect(!FillCannulaResponse(cargo: []).accepted)
        #expect(FillCannulaResponse(cargo: [0]).accepted)
        #expect(!FillCannulaResponse(cargo: [1]).accepted)
    }

    @Test func cancelBolusResponseShortBufferIsNotCancelled() {
        // size 5; wasCancelled == (statusId == 0 && reasonId == 0). A short/empty buffer must NEVER decode
        // wasCancelled == true — that would be "your bolus was cancelled" from zero pump bytes.
        for short: [UInt8] in [[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0]] {
            #expect(!CancelBolusResponse(cargo: short).wasCancelled)
        }
        #expect(CancelBolusResponse(cargo: [0, 0, 0, 0, 0]).wasCancelled)  // full, success (no regression)
        #expect(!CancelBolusResponse(cargo: [1, 0, 0, 0, 0]).wasCancelled)  // statusId != 0
        #expect(!CancelBolusResponse(cargo: [0, 0, 0, 2, 0]).wasCancelled)  // reasonId != 0 (byte 3)
    }

    // The two remaining distinct init SHAPES (the other ~19 hardened acks are byte-identical size-1
    // one-liners already covered by the size-1 cases above): a size-2 status+ack, and a statusCode-named ack.

    @Test func setSensorTypeResponseShortBufferIsNotAccepted() {  // size 2 (status@0, statusAcknowledgement@1)
        for short: [UInt8] in [[], [0]] {
            #expect(!SetSensorTypeResponse(cargo: short).accepted)
        }
        #expect(SetSensorTypeResponse(cargo: [0, 0]).accepted)
        #expect(!SetSensorTypeResponse(cargo: [1, 0]).accepted)
    }

    @Test func primeTubingSuspendResponseShortBufferIsNotAccepted() {  // size 3 (statusCode@0, reserve@2)
        for short: [UInt8] in [[], [0], [0, 0]] {
            #expect(!PrimeTubingSuspendResponse(cargo: short).accepted)
        }
        #expect(PrimeTubingSuspendResponse(cargo: [0, 0, 0]).accepted)
        #expect(!PrimeTubingSuspendResponse(cargo: [1, 0, 0]).accepted)
    }

    // The four modifiesInsulinDelivery: true acks below have no `accepted` computed property; status
    // itself is the accept/reject signal (status == 0 means accepted). Each opened `guard raw.count >=
    // Self.props.size else { return }`, so a short buffer left `status` at its default 0 — decoding a
    // truncated/empty frame as an accepted insulin-modifying write. Assert directly on `status`.

    @Test func additionalBolusResponseShortBufferIsNotAccepted() {  // size 5
        for short: [UInt8] in [[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0]] {
            #expect(AdditionalBolusResponse(cargo: short).status != 0)
        }
        // Full-length, status-0 buffer still decodes accepted (no regression).
        #expect(AdditionalBolusResponse(cargo: [0, 0, 0, 0, 0]).status == 0)
        #expect(AdditionalBolusResponse(cargo: [1, 0, 0, 0, 0]).status != 0)
    }

    @Test func createIDPResponseShortBufferIsNotAccepted() {  // size 2
        for short: [UInt8] in [[], [0]] {
            #expect(CreateIDPResponse(cargo: short).status != 0)
        }
        #expect(CreateIDPResponse(cargo: [0, 0]).status == 0)
        #expect(CreateIDPResponse(cargo: [1, 0]).status != 0)
    }

    @Test func deleteIDPResponseShortBufferIsNotAccepted() {  // size 2
        for short: [UInt8] in [[], [0]] {
            #expect(DeleteIDPResponse(cargo: short).status != 0)
        }
        #expect(DeleteIDPResponse(cargo: [0, 0]).status == 0)
        #expect(DeleteIDPResponse(cargo: [1, 0]).status != 0)
    }

    @Test func renameIDPResponseShortBufferIsNotAccepted() {  // size 2
        for short: [UInt8] in [[], [0]] {
            #expect(RenameIDPResponse(cargo: short).status != 0)
        }
        #expect(RenameIDPResponse(cargo: [0, 0]).status == 0)
        #expect(RenameIDPResponse(cargo: [1, 0]).status != 0)
    }
}
