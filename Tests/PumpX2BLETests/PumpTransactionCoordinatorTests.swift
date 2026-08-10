import Testing
import Foundation
import PumpX2Messages
@testable import PumpX2BLE

/// PX-08: the transaction coordinator is the deterministic, CoreBluetooth-free "fake transport" the
/// remediation plan requires for FB-02. A `write` thunk stands in for the BLE write; `ingest` stands in
/// for a notified response frame. Every property the plan asks for — correlation, deadline, fail-closed
/// completion, no-misfire on a stale deadline — is asserted here without hardware.
@Suite struct PumpTransactionCoordinatorTests {

    /// Drive `perform` to the point where its pending transaction is registered.
    @MainActor private func launchAndRegister(
        _ coord: PumpTransactionCoordinator, on ch: Characteristic, opCode: UInt8,
        deadline: TimeInterval = 5, txId: UInt8 = 7
    ) async -> Task<[UInt8], Error> {
        let before = coord.inFlightCount
        let task = Task { @MainActor in
            try await coord.perform(expectedResponseOn: ch, opCode: opCode, deadline: deadline) { txId }
        }
        while coord.inFlightCount == before { await Task.yield() }   // wait until THIS transaction registers
        return task
    }

    @MainActor @Test func responseResolvesTheAwaitingTransaction() async throws {
        let coord = PumpTransactionCoordinator()
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03)
        let consumed = coord.ingest(frame: [0x03, 7, 0], on: .control)
        #expect(consumed)
        let frame = try await task.value
        #expect(frame == [0x03, 7, 0])
        #expect(coord.inFlightCount == 0)
    }

    /// A frame nobody awaits is not consumed (so the BLE layer routes it to the delegate instead).
    @MainActor @Test func unawaitedFrameIsNotConsumed() {
        let coord = PumpTransactionCoordinator()
        #expect(coord.ingest(frame: [0x99, 1, 0], on: .currentStatus) == false)
    }

    /// A synchronous write failure (authorization / not-ready) is rethrown and never registers a pending
    /// transaction — so it can't leak or later mis-resolve.
    @MainActor @Test func synchronousWriteFailureRegistersNothing() async {
        let coord = PumpTransactionCoordinator()
        await #expect(throws: PumpBLEClient.ClientError.self) {
            try await coord.perform(expectedResponseOn: .control, opCode: 0x03, deadline: 5) {
                throw PumpBLEClient.ClientError.writeBlocked(policy: .readOnly, opcode: 0x1C)
            }
        }
        #expect(coord.inFlightCount == 0)
    }

    @MainActor @Test func deadlineResolvesTimedOut() async {
        let coord = PumpTransactionCoordinator()
        await #expect(throws: PumpTransactionCoordinator.TxError.timedOut(characteristic: .currentStatus, opCode: 0x99)) {
            try await coord.perform(expectedResponseOn: .currentStatus, opCode: 0x99, deadline: 0.02) { 7 }
        }
        #expect(coord.inFlightCount == 0)
    }

    /// Fail-closed: a disconnect resumes the pending transaction with `.connectionLost`, never hangs.
    @MainActor @Test func failAllResumesPending() async {
        let coord = PumpTransactionCoordinator()
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03)
        coord.failAll(.connectionLost)
        #expect(coord.inFlightCount == 0)
        let result = await task.result
        if case .success = result { Issue.record("expected connectionLost, got success") }
    }

    /// Correlation: two transactions awaiting different opcodes resolve independently to their own frame.
    @MainActor @Test func correlatesByOpcode() async throws {
        let coord = PumpTransactionCoordinator()
        let a = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 1)
        let b = await launchAndRegister(coord, on: .control, opCode: 0x05, txId: 2)
        #expect(coord.inFlightCount == 2)
        // Resolve the second one first; the first stays pending.
        #expect(coord.ingest(frame: [0x05, 2, 0], on: .control))
        let bFrame = try await b.value
        #expect(bFrame.first == 0x05)
        #expect(coord.inFlightCount == 1)
        #expect(coord.ingest(frame: [0x03, 1, 0], on: .control))
        let aFrame = try await a.value
        #expect(aFrame.first == 0x03)
    }

    /// A response that arrives before the deadline resolves the transaction; the (now-stale) deadline
    /// task firing afterward is a no-op (the id is gone) — it cannot mis-resolve a later transaction.
    @MainActor @Test func staleDeadlineDoesNotMisfire() async throws {
        let coord = PumpTransactionCoordinator()
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03, deadline: 0.05)
        #expect(coord.ingest(frame: [0x03, 7, 42], on: .control))
        _ = try await task.value
        // Start a fresh transaction and let the previous (already-cancelled) deadline window elapse.
        let task2 = await launchAndRegister(coord, on: .control, opCode: 0x03, deadline: 5, txId: 9)
        try? await Task.sleep(nanoseconds: 80_000_000)   // > the first deadline
        #expect(coord.inFlightCount == 1)                // task2 still awaiting — not killed by a stale timer
        coord.ingest(frame: [0x03, 9, 1], on: .control)
        _ = try await task2.value
    }

    /// Two transactions sharing the SAME (characteristic, opcode) resolve FIFO: the first-registered gets
    /// the first matching frame. (The Tandem wire has no per-request response tag, so same-opcode requests
    /// are serialized in practice; this documents the ordering the delivery flow relies on — §6 req 3.)
    @MainActor @Test func sameOpcodeResolvesFIFO() async throws {
        let coord = PumpTransactionCoordinator()
        let a = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 1)
        let b = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 2)
        #expect(coord.inFlightCount == 2)
        #expect(coord.ingest(frame: [0x03, 1, 0xAA], on: .control))   // first frame → oldest (a)
        let aFrame = try await a.value
        #expect(aFrame == [0x03, 1, 0xAA])
        #expect(coord.inFlightCount == 1)
        #expect(coord.ingest(frame: [0x03, 2, 0xBB], on: .control))   // next frame → b
        let bFrame = try await b.value
        #expect(bFrame == [0x03, 2, 0xBB])
    }

    /// Cancelling ONE awaiting task resolves only that transaction (`.cancelled`); a sibling keeps
    /// awaiting and still resolves normally — no leaked continuation, no misfire (§6 req 4).
    @MainActor @Test func cancellingOneTaskResolvesOnlyThatTransaction() async throws {
        let coord = PumpTransactionCoordinator()
        let a = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 1)
        let b = await launchAndRegister(coord, on: .control, opCode: 0x05, txId: 2)
        #expect(coord.inFlightCount == 2)
        a.cancel()
        let aResult = await a.result
        if case .success = aResult { Issue.record("expected the cancelled task to throw") }
        #expect(coord.inFlightCount == 1)                             // only a was resolved
        #expect(coord.ingest(frame: [0x05, 2, 0], on: .control))      // b unaffected
        let bFrame = try await b.value
        #expect(bFrame.first == 0x05)
    }

    // MARK: - R3-D: delivery-class serialization

    /// A second delivery-class (`serialized`) transaction is rejected `.busy` — BEFORE any write — while
    /// one is outstanding, so two identical in-flight delivery opcodes can never cross-resolve. A
    /// non-serialized read is unaffected and still runs concurrently.
    @MainActor @Test func serializedRejectsSecondDeliveryWhileOneInFlight() async throws {
        let coord = PumpTransactionCoordinator()
        var writes = 0
        let first = Task { @MainActor in
            try await coord.perform(expectedResponseOn: .control, opCode: 0x10, deadline: 5,
                                    serialized: true) { writes += 1; return 1 }
        }
        while !coord.hasSerializedInFlight { await Task.yield() }
        #expect(writes == 1)

        // Second serialized command → `.busy`, and it must NOT have written.
        await #expect(throws: PumpTransactionCoordinator.TxError.busy) {
            try await coord.perform(expectedResponseOn: .control, opCode: 0x11, deadline: 5,
                                    serialized: true) { writes += 1; return 2 }
        }
        #expect(writes == 1)

        // A concurrent non-serialized read is still allowed.
        let read = Task { @MainActor in
            try await coord.perform(expectedResponseOn: .control, opCode: 0x20, deadline: 5,
                                    serialized: false) { writes += 1; return 3 }
        }
        while coord.inFlightCount < 2 { await Task.yield() }
        #expect(writes == 2)

        _ = coord.ingest(frame: [0x10, 1, 0], on: .control)
        _ = coord.ingest(frame: [0x20, 3, 0], on: .control)
        _ = try await first.value
        _ = try await read.value
    }

    /// Once the outstanding delivery-class transaction resolves, another is admitted — the block is
    /// per-in-flight, not a permanent lock.
    @MainActor @Test func serializedAdmittedAgainAfterFirstResolves() async throws {
        let coord = PumpTransactionCoordinator()
        let first = await launchAndRegister(coord, on: .control, opCode: 0x10)   // (non-serialized helper)
        // Make it serialized-in-flight by resolving the helper, then run a real serialized pair in order.
        _ = coord.ingest(frame: [0x10, 7, 0], on: .control)
        _ = try await first.value

        var writes = 0
        let a = Task { @MainActor in
            try await coord.perform(expectedResponseOn: .control, opCode: 0x30, deadline: 5,
                                    serialized: true) { writes += 1; return 1 }
        }
        while !coord.hasSerializedInFlight { await Task.yield() }
        _ = coord.ingest(frame: [0x30, 1, 0], on: .control)
        _ = try await a.value
        #expect(!coord.hasSerializedInFlight)

        // A second serialized command now proceeds (the first is done).
        let b = Task { @MainActor in
            try await coord.perform(expectedResponseOn: .control, opCode: 0x31, deadline: 5,
                                    serialized: true) { writes += 1; return 2 }
        }
        while !coord.hasSerializedInFlight { await Task.yield() }
        #expect(writes == 2)
        _ = coord.ingest(frame: [0x31, 2, 0], on: .control)
        _ = try await b.value
    }

    // MARK: - D2 (Addendum G): txId correlation

    /// Fail-closed default: a fresh coordinator correlates by opcode FIFO (the `main` reference path).
    @MainActor @Test func defaultCorrelationModeIsOpcodeFIFO() {
        #expect(PumpTransactionCoordinator().correlationMode == .opcodeFIFO)
    }

    /// The core reorder win: two reads sharing the SAME opcode but distinct txIds resolve to their OWN
    /// frame even when the pump replies out of order. FIFO would give the first-arriving frame to the
    /// oldest transaction (a mis-attribution); txId-match keys on the echoed `frame[1]`.
    @MainActor @Test func txIdMatchResolvesOutOfOrderSameOpcodeReads() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let a = await launchAndRegister(coord, on: .currentStatus, opCode: 0x03, txId: 1)
        let b = await launchAndRegister(coord, on: .currentStatus, opCode: 0x03, txId: 2)
        #expect(coord.inFlightCount == 2)
        // The txId-2 reply arrives FIRST → must resolve `b`, not the oldest (`a`).
        #expect(coord.ingest(frame: [0x03, 2, 0xBB], on: .currentStatus))
        #expect(try await b.value == [0x03, 2, 0xBB])
        #expect(coord.inFlightCount == 1)
        #expect(coord.ingest(frame: [0x03, 1, 0xAA], on: .currentStatus))
        #expect(try await a.value == [0x03, 1, 0xAA])
    }

    /// A rejected control write is answered with op-77 echoing the FAILING request's txId. txId-match
    /// accepts it as a terminal reply for the matching transaction (77 ≠ the expected opcode, but the
    /// txId matches), so the write resolves with the NACK frame instead of hanging to its deadline.
    @MainActor @Test func txIdMatchAcceptsOp77NackByTxId() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x1C, txId: 3)
        #expect(coord.ingest(frame: [77, 3, 2, 0x1C, 3], on: .control))   // op-77, txId 3
        let frame = try await task.value
        #expect(frame.first == 77 && frame[1] == 3)
        #expect(coord.inFlightCount == 0)
    }

    /// An unsolicited stream frame is NEVER consumed by a pending transaction — even one that happens to
    /// share the pending's txId — because its opcode is neither the expected response nor a NACK (77). It
    /// is routed to the delegate (ingest returns false), and the awaiting read stays in flight.
    @MainActor @Test func txIdMatchNeverConsumesUnsolicitedStreamFrame() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 5)
        #expect(coord.ingest(frame: [129, 5, 0], on: .control) == false)   // op-129 stream, same txId 5
        #expect(coord.inFlightCount == 1)
        #expect(coord.ingest(frame: [0x03, 5, 0], on: .control))           // its real reply resolves it
        _ = try await task.value
    }

    /// txId is a `UInt8`; the wire counter wraps 255 → 0. Two in-flight reads straddling the wrap stay
    /// distinct. (A same-txId collision needs 256 concurrent transactions — impossible with delivery
    /// serialized to one in-flight command and only a handful of reads.)
    @MainActor @Test func txIdMatchDistinguishesWraparoundTxIds() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let hi = await launchAndRegister(coord, on: .currentStatus, opCode: 0x03, txId: 255)
        let lo = await launchAndRegister(coord, on: .currentStatus, opCode: 0x03, txId: 0)
        #expect(coord.ingest(frame: [0x03, 0, 0xB0], on: .currentStatus))
        #expect(try await lo.value == [0x03, 0, 0xB0])
        #expect(coord.ingest(frame: [0x03, 255, 0xAA], on: .currentStatus))
        #expect(try await hi.value == [0x03, 255, 0xAA])
    }

    /// txId correlation must NOT relax delivery-class serialization: a bolus is still never pipelined, so
    /// a second `serialized` command is rejected `.busy` before writing, exactly as under opcode FIFO.
    /// This is the load-bearing safety invariant of D2 (delivery stays 1-in-flight in BOTH modes).
    @MainActor @Test func txIdMatchStillSerializesDelivery() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        var writes = 0
        let first = Task { @MainActor in
            try await coord.perform(expectedResponseOn: .control, opCode: 0x10, deadline: 5,
                                    serialized: true) { writes += 1; return 1 }
        }
        while !coord.hasSerializedInFlight { await Task.yield() }
        #expect(writes == 1)
        await #expect(throws: PumpTransactionCoordinator.TxError.busy) {
            try await coord.perform(expectedResponseOn: .control, opCode: 0x11, deadline: 5,
                                    serialized: true) { writes += 1; return 2 }
        }
        #expect(writes == 1)
        _ = coord.ingest(frame: [0x10, 1, 0], on: .control)
        _ = try await first.value
    }

    /// A frame too short to carry a txId byte cannot be correlated in txId-match mode — treated as
    /// unsolicited (routed to the delegate), never mis-attributed to a pending transaction.
    @MainActor @Test func txIdMatchTreatsFrameWithoutTxIdAsUnsolicited() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 7)
        #expect(coord.ingest(frame: [0x03], on: .control) == false)
        #expect(coord.inFlightCount == 1)
        #expect(coord.ingest(frame: [0x03, 7, 0], on: .control))
        _ = try await task.value
    }
}
