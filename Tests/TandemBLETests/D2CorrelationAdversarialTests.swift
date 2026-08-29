import Testing
import Foundation
import TandemMessages
@testable import TandemBLE

/// Under `.txIdMatch`, a mis-correlation must not attribute the wrong status/ack to a pending
/// request: wrong-channel replay, NACK precision among several in-flight, duplicate/stale replay,
/// a shared-txId collision, and cancellation isolation.
@Suite struct D2CorrelationAdversarialTests {

    /// Drive `perform` to the point where its pending transaction is registered (mirrors the helper in
    /// `PumpTransactionCoordinatorTests`).
    @MainActor private func launchAndRegister(
        _ coord: PumpTransactionCoordinator, on ch: Characteristic, opCode: UInt8,
        deadline: TimeInterval = 5, txId: UInt8 = 7
    ) async -> Task<[UInt8], Error> {
        let before = coord.inFlightCount
        let task = Task { @MainActor in
            try await coord.perform(expectedResponseOn: ch, opCode: opCode, deadline: deadline) { txId }
        }
        while coord.inFlightCount == before { await Task.yield() }  // wait until THIS transaction registers
        return task
    }

    // MARK: - Cross-characteristic isolation

    /// A same-opcode, same-txId frame arriving on the WRONG characteristic must never resolve the pending
    /// transaction — the `.txIdMatch` predicate requires `expectedCharacteristic == characteristic` too, so
    /// a same-txId echo on an unrelated channel is not attributed to it. The pending stays in flight until
    /// its real, correct-characteristic reply arrives.
    @MainActor @Test func txIdMatchRejectsSameTxIdOnDifferentCharacteristic() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 9)
        // Same opCode + same txId, but on .currentStatus instead of .control — must NOT match.
        #expect(coord.ingest(frame: [0x03, 9, 0], on: .currentStatus) == false)
        #expect(coord.inFlightCount == 1)
        // The correct-characteristic reply resolves it normally.
        #expect(coord.ingest(frame: [0x03, 9, 0xAA], on: .control))
        #expect(try await task.value == [0x03, 9, 0xAA])
        #expect(coord.inFlightCount == 0)
    }

    // MARK: - Op-77 NACK precision

    /// An op-77 NACK echoing a specific in-flight txId resolves EXACTLY that transaction among several
    /// distinct-txId pendings — never a sibling. An op-77 carrying a txId that matches NO pending is
    /// unsolicited (`ingest` returns `false`), never mis-attributed to the wrong one by falling through to
    /// some other match.
    @MainActor @Test func txIdMatchOp77NackResolvesOnlyMatchingTxIdAmongSeveral() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let a = await launchAndRegister(coord, on: .control, opCode: 0x10, txId: 1)
        let b = await launchAndRegister(coord, on: .control, opCode: 0x20, txId: 2)
        let c = await launchAndRegister(coord, on: .control, opCode: 0x30, txId: 3)
        #expect(coord.inFlightCount == 3)

        // op-77 echoing txId 2 (the MIDDLE one) resolves ONLY b.
        #expect(coord.ingest(frame: [77, 2, 1, 0x20], on: .control))
        let bFrame = try await b.value
        #expect(bFrame.first == 77 && bFrame[1] == 2)
        #expect(coord.inFlightCount == 2)  // a and c both still in flight

        // a and c resolve independently on their own real replies — proving the NACK didn't touch them.
        #expect(coord.ingest(frame: [0x10, 1, 0], on: .control))
        #expect(try await a.value == [0x10, 1, 0])
        #expect(coord.ingest(frame: [0x30, 3, 0], on: .control))
        #expect(try await c.value == [0x30, 3, 0])
        #expect(coord.inFlightCount == 0)
    }

    /// An op-77 carrying a txId that matches no pending transaction is routed as unsolicited.
    @MainActor @Test func txIdMatchOp77UnknownTxIdIsUnsolicited() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x10, txId: 1)
        // op-77 echoing txId 99 — no pending has that txId.
        #expect(coord.ingest(frame: [77, 99, 0], on: .control) == false)
        #expect(coord.inFlightCount == 1)
        // The real reply still resolves the pending.
        #expect(coord.ingest(frame: [0x10, 1, 0], on: .control))
        _ = try await task.value
    }

    // MARK: - No double-resolve

    /// A duplicate/stale frame arriving AFTER its transaction already resolved must not double-resolve —
    /// `resolve(id:)` is keyed by the unique transaction id and is a no-op once that id is gone, so the
    /// second (stale) ingest returns `false` and `inFlightCount` stays at 0.
    @MainActor @Test func txIdMatchDoesNotDoubleResolveDuplicateFrame() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let task = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 4)
        #expect(coord.ingest(frame: [0x03, 4, 0xAA], on: .control))  // first ingest resolves it
        #expect(try await task.value == [0x03, 4, 0xAA])
        #expect(coord.inFlightCount == 0)
        // An identical duplicate/stale frame arrives again — must be a no-op.
        #expect(coord.ingest(frame: [0x03, 4, 0xAA], on: .control) == false)
        #expect(coord.inFlightCount == 0)
    }

    // MARK: - Shared-txId defined behavior

    /// Two pendings sharing the same (characteristic, txId) — pathological wrap — must resolve only
    /// the oldest match off one frame. Delivery is serialized so this collision is unreachable in practice.
    @MainActor @Test func txIdMatchSharedTxIdResolvesOldestOnlyDefinedBehavior() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        // Both awaiting the SAME opCode + SAME txId on the SAME characteristic — the collision case.
        let older = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 6)
        let newer = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 6)
        #expect(coord.inFlightCount == 2)

        // One matching frame arrives — must resolve exactly one (the oldest), never both.
        #expect(coord.ingest(frame: [0x03, 6, 0xAA], on: .control))
        let olderFrame = try await older.value
        #expect(olderFrame == [0x03, 6, 0xAA])
        #expect(coord.inFlightCount == 1)  // the newer one is still in flight, not double-resolved

        // The still-pending sibling resolves on a subsequent frame of its own.
        #expect(coord.ingest(frame: [0x03, 6, 0xBB], on: .control))
        let newerFrame = try await newer.value
        #expect(newerFrame == [0x03, 6, 0xBB])
        #expect(coord.inFlightCount == 0)
    }

    // MARK: - Cancellation isolates the owning transaction

    /// Re-assert `cancellingOneTaskResolvesOnlyThatTransaction` (proven under `.opcodeFIFO` in
    /// `PumpTransactionCoordinatorTests`) under `.txIdMatch`: cancelling ONE awaiting task resolves ONLY
    /// that transaction (`.cancelled`); a sibling with a distinct txId keeps awaiting and still resolves
    /// normally on its own reply — no leaked continuation, no misfire.
    @MainActor @Test func txIdMatchCancellationResolvesOnlyOwningTransaction() async throws {
        let coord = PumpTransactionCoordinator()
        coord.correlationMode = .txIdMatch
        let a = await launchAndRegister(coord, on: .control, opCode: 0x03, txId: 1)
        let b = await launchAndRegister(coord, on: .control, opCode: 0x05, txId: 2)
        #expect(coord.inFlightCount == 2)

        a.cancel()
        let aResult = await a.result
        if case .success = aResult { Issue.record("expected the cancelled task to throw") }
        if case .failure(let error) = aResult {
            #expect(error as? PumpTransactionCoordinator.TxError == .cancelled)
        }
        #expect(coord.inFlightCount == 1)  // only a was resolved

        // b is unaffected — its own reply still resolves it normally.
        #expect(coord.ingest(frame: [0x05, 2, 0], on: .control))
        let bFrame = try await b.value
        #expect(bFrame.first == 0x05)
        #expect(coord.inFlightCount == 0)
    }
}
