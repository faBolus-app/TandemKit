import Testing
import TandemMessages
@testable import TandemAuth

/// `PairingCoordinator.handle(frame:)` must fail closed on a CRC-invalid frame or a declared length
/// that does not match the buffer (`3 + declaredLen == frame.count - 2`). A well-formed frame (real CRC,
/// exact declared length) is unaffected.
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

    /// A frame whose trailing 2 bytes are not `Bytes.calculateCRC16(body)` must fail the
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

    /// A declared length that claims more cargo than is actually present (`3 + declaredLen
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

    /// A declared length shorter than the actual cargo (`3 + declaredLen < frame.count - 2`)
    /// must fail closed rather than being clamped.
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

    /// A well-formed frame (valid CRC, exact declared length) is handled as before — no regression
    /// to the JPAKE happy path.
    @Test func wellFormedFrameAdvancesAuthNormally() throws {
        let coord = try startedCoordinator()
        coord.onError = { Issue.record("unexpected pairing error: \($0)") }

        let cargo = withAppId([UInt8](repeating: 0xAA, count: 10))
        coord.handle(frame: wellFormedFrame(33, cargo))

        #expect(coord.step == .sent1b)
    }
}
