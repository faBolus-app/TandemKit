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
}
