import Foundation
import TandemMessages
import Testing

@testable import TandemBench

/// The cancel-overlap check holds one request's write back and sends it just before the next control
/// write, so the pump has it outstanding when the control request arrives.
@Suite struct BenchWriteHoldTests {
    private let status: [[UInt8]] = [[0, 7, 0x2c, 7, 0, 0xaa, 0xbb]]
    private let cancel: [[UInt8]] = [[1, 8, 0xa0, 8, 30], [0, 8, 0x01, 0x02]]

    @Test func theHeldWriteGoesJustBeforeTheNextControlWrite() {
        var hold = BenchWriteHold()
        hold.hold(next: .currentStatus)
        #expect(hold.writes(.currentStatus, status).isEmpty)
        #expect(hold.heldTxId == 7)
        let out = hold.writes(.control, cancel)
        #expect(out.map(\.characteristic) == [.currentStatus, .control])
        #expect(out.map(\.packets) == [status, cancel])
        // Once out, nothing more is held.
        #expect(hold.writes(.control, cancel).map(\.characteristic) == [.control])
    }

    @Test func writesOnOtherCharacteristicsPassMeanwhile() {
        var hold = BenchWriteHold()
        hold.hold(next: .currentStatus)
        #expect(hold.writes(.qualifyingEvents, [[0, 0, 0, 0]]).map(\.characteristic) == [.qualifyingEvents])
        #expect(hold.writes(.currentStatus, status).isEmpty)
        #expect(hold.writes(.qualifyingEvents, [[0, 0, 0, 0]]).map(\.characteristic) == [.qualifyingEvents])
    }

    @Test func onlyTheNextWriteIsHeld() {
        var hold = BenchWriteHold()
        hold.hold(next: .currentStatus)
        _ = hold.writes(.currentStatus, status)
        _ = hold.writes(.control, cancel)
        #expect(hold.writes(.currentStatus, status).map(\.characteristic) == [.currentStatus])
    }

    @Test func aControlWriteIsNeverHeld() {
        var hold = BenchWriteHold()
        hold.hold(next: .control)
        #expect(hold.writes(.control, cancel).map(\.characteristic) == [.control])
    }

    @Test func theHeldReplyIsToldApartByItsCharacteristicAndTxId() {
        var hold = BenchWriteHold()
        hold.hold(next: .currentStatus)
        _ = hold.writes(.currentStatus, status)
        // Not out yet: nothing can answer it.
        #expect(!hold.answersHeld(.currentStatus, [0, 7, 0x2d]))
        _ = hold.writes(.control, cancel)
        #expect(hold.answersHeld(.currentStatus, [0, 7, 0x2d]))
        #expect(!hold.answersHeld(.control, [0, 7, 0xa1]))
        #expect(!hold.answersHeld(.currentStatus, [0, 8, 0x2d]))
    }

    @Test func clearingDropsAWriteStillHeld() {
        var hold = BenchWriteHold()
        hold.hold(next: .currentStatus)
        _ = hold.writes(.currentStatus, status)
        hold.clear()
        #expect(hold.writes(.control, cancel).map(\.characteristic) == [.control])
        #expect(hold.heldTxId == nil)
    }
}
