import Foundation
import Testing
import TandemMessages

/// `QualifyingEvent.decode` against upstream's bit values. The link's dispatch and clear are tested
/// with the state machine (`LinkReducerTests`).
@Suite struct QualifyingEventsDecodeTests {
    private func le4(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }

    // MARK: - QualifyingEvent.decode bit-value fidelity (transcribed from QualifyingEvent.java)

    @Test func decodeMatchesUpstreamBitValuesForSingleBits() {
        #expect(QualifyingEvent.decode(le4(1)) == .alert)
        #expect(QualifyingEvent.decode(le4(2)) == .alarm)
        #expect(QualifyingEvent.decode(le4(4)) == .reminder)
        #expect(QualifyingEvent.decode(le4(8)) == .malfunction)
        #expect(QualifyingEvent.decode(le4(16)) == .cgmAlert)
        #expect(QualifyingEvent.decode(le4(524_288)) == .pumpCommunicationsSuspended)
        #expect(QualifyingEvent.decode(le4(0x8000_0000)) == .bolusPermissionRevoked)  // bit 31
    }

    @Test func decodeCombinesMultipleBitsAsAnOptionSet() {
        let decoded = QualifyingEvent.decode(le4(1 | 2 | 524_288))  // alert + alarm + comms-suspended
        #expect(decoded == [.alert, .alarm, .pumpCommunicationsSuspended])
        #expect(decoded.contains(.alert))
        #expect(decoded.contains(.alarm))
        #expect(decoded.contains(.pumpCommunicationsSuspended))
        #expect(!decoded.contains(.battery))
    }

    /// Fail-closed: an undersized buffer decodes to `[]`, never a spurious bit / crash — `Bytes
    /// .readUint32` itself preconditions on 4 bytes, so the guard in `decode` must run first.
    @Test func decodeOfUndersizedBufferFailsClosedToEmpty() {
        #expect(QualifyingEvent.decode([]) == [])
        #expect(QualifyingEvent.decode([1, 2, 3]) == [])
    }

    @Test func decodeOfAllZeroBitmapIsEmpty() {
        #expect(QualifyingEvent.decode(le4(0)) == [])
    }
}
