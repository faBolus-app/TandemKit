import Testing
import TandemMessages
@testable import TandemAuth

/// CX-T-08: `PairingCoordinator.handle(frame:)` today only guards `frame.count >= 5` and
/// `frameCargo` silently CLAMPS a declared length that overruns the frame — no CRC check exists
/// in the pairing path at all. These tests prove the restored guard: a CRC-invalid frame, and a
/// frame whose declared length does not satisfy `3 + declaredLen == frame.count - 2` (both
/// too-long and too-short), fail the handshake via `fail(.malformedFrame)` instead of being
/// parsed/clamped. A well-formed frame (real CRC, exact declared length) is unaffected.
@Suite struct PairingCoordinatorFrameTests {
    /// A well-formed inbound frame carrying a REAL CRC16 (unlike the dummy `[0, 0]` trailer used
    /// by `PairingCoordinatorTests`'s `frame()` helper, now updated to match).
    private func wellFormedFrame(_ opcode: UInt8, _ cargo: [UInt8]) -> [UInt8] {
        let body: [UInt8] = [opcode, 0, UInt8(cargo.count)] + cargo
        return body + Bytes.calculateCRC16(body)
    }
    private func withAppId(_ payload: [UInt8]) -> [UInt8] { [0, 0] + payload }  // appInstanceId=0

    private func startedCoordinator() throws -> PairingCoordinator {
        let coord = try PairingCoordinator(pairingCode: "123456")
        coord.onSendRequest = { _ in }  // swallow the outgoing Jpake1a/1b requests
        coord.start()
        return coord
    }

    /// RED: a frame whose trailing 2 bytes are NOT `Bytes.calculateCRC16(body)` must fail the
    /// handshake via `fail(.malformedFrame)`, never advance to the next step.
    @Test func crcInvalidFrameFailsClosed() throws {
        let coord = try startedCoordinator()
        var failure: Error?
        coord.onError = { failure = $0 }
        coord.onPaired = { _, _ in Issue.record("must not pair on a CRC-invalid frame") }

        let cargo = withAppId([UInt8](repeating: 0xAA, count: 10))
        var frame = wellFormedFrame(33, cargo)
        frame[frame.count - 1] ^= 0xFF  // corrupt the trailing CRC byte

        coord.handle(frame: frame)

        #expect(coord.step == .failed)
        #expect(failure as? PairingCoordinator.PairingError == .malformedFrame)
    }

    /// RED: a declared length that claims MORE cargo than is actually present (`3 + declaredLen
    /// > frame.count - 2`) must fail closed rather than being clamped by `min(...)`.
    @Test func declaredLengthTooLongFailsClosed() throws {
        let coord = try startedCoordinator()
        var failure: Error?
        coord.onError = { failure = $0 }
        coord.onPaired = { _, _ in Issue.record("must not pair on a length-mismatched frame") }

        let cargo = withAppId([UInt8](repeating: 0xAA, count: 10))
        var body: [UInt8] = [33, 0, UInt8(cargo.count)] + cargo
        body[2] = UInt8(cargo.count + 5)  // declares more cargo than is actually present
        let frame = body + Bytes.calculateCRC16(body)  // CRC is valid over this (mismatched) body

        coord.handle(frame: frame)

        #expect(coord.step == .failed)
        #expect(failure as? PairingCoordinator.PairingError == .malformedFrame)
    }

    /// RED: a declared length SHORTER than the actual cargo (`3 + declaredLen < frame.count - 2`)
    /// must fail closed — today this silently truncates to a possibly-empty challenge instead.
    @Test func declaredLengthTooShortFailsClosed() throws {
        let coord = try startedCoordinator()
        var failure: Error?
        coord.onError = { failure = $0 }
        coord.onPaired = { _, _ in Issue.record("must not pair on a length-mismatched frame") }

        let cargo = withAppId([UInt8](repeating: 0xAA, count: 10))
        var body: [UInt8] = [33, 0, UInt8(cargo.count)] + cargo
        body[2] = UInt8(cargo.count - 5)  // declares fewer bytes than are actually present
        let frame = body + Bytes.calculateCRC16(body)

        coord.handle(frame: frame)

        #expect(coord.step == .failed)
        #expect(failure as? PairingCoordinator.PairingError == .malformedFrame)
    }

    /// GREEN: a well-formed frame (valid CRC, exact declared length) is handled exactly as before
    /// the guard was added — no regression to the JPAKE happy path.
    @Test func wellFormedFrameAdvancesAuthNormally() throws {
        let coord = try startedCoordinator()
        coord.onError = { Issue.record("unexpected pairing error: \($0)") }

        let cargo = withAppId([UInt8](repeating: 0xAA, count: 10))
        coord.handle(frame: wellFormedFrame(33, cargo))

        #expect(coord.step == .sent1b)
    }
}
