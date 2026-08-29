import Testing
import Foundation
@testable import TandemBLE

/// Reconnect backoff includes additive jitter so a phone and pump retrying on fixed intervals cannot
/// lock into a beat pattern. Jitter is bounded (never tightens the ladder, never runs away) and actually varies.
@Suite struct ReconnectBackoffJitterTests {

    @Test func jitteredDelayStaysWithinBaseAndFiftyPercentMore() {
        for base in [5.0, 10.0, 20.0, 30.0] as [TimeInterval] {
            for _ in 0..<1000 {
                let d = PumpBLEClient.jitteredDelay(base: base)
                #expect(d >= base)  // never shorter than the ladder step
                #expect(d <= base * 1.5)  // never more than +50%
            }
        }
    }

    @Test func nonPositiveBaseIsReturnedUnchanged() {
        #expect(PumpBLEClient.jitteredDelay(base: 0) == 0)
        #expect(PumpBLEClient.jitteredDelay(base: -5) == -5)
    }

    @Test func jitterActuallyVaries() {
        // Over many draws on a nonzero base there must be more than one distinct value — i.e. it is not a
        // constant masquerading as jitter.
        let distinct = Set((0..<200).map { _ in PumpBLEClient.jitteredDelay(base: 20) })
        #expect(distinct.count > 1)
    }
}
