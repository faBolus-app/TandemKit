import Testing
import Foundation
import CoreBluetooth
import TandemMessages
@testable import TandemBLE

/// CC-03 (kit half): the qualifying-events characteristic is subscribed but had no decode branch —
/// its 4-byte bitmap reached consumers only as an opaque `didReceiveFrame`. These tests prove the
/// added decode + typed-dispatch + reference-backed clear, extracted into
/// `PumpBLEClient.handleQualifyingEventsFrame(_:clear:)` so it is unit-testable without CoreBluetooth
/// (a macOS test host cannot construct a real `CBPeripheral`/`CBCharacteristic` — TCC-aborted at
/// scan). The `clear` closure IS the minimal spy seam mirroring `PumpCentral`: production wires it to
/// a real `.qualifyingEvents` characteristic write; the test wires it to a counter.
@MainActor
@Suite struct QualifyingEventsDecodeTests {

    /// Records `didReceiveQualifyingEvent` dispatches; the rest of the protocol keeps its default
    /// no-op (proving the additive-delegate pattern: a conformer need not implement everything).
    final class RecordingDelegate: PumpBLEClientDelegate {
        var events: [QualifyingEvent] = []
        func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {}
        func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {}
        func pumpClientDidBecomeReady(_ client: PumpBLEClient) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {}
        func pumpClient(_ client: PumpBLEClient, didError error: Error) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveQualifyingEvent event: QualifyingEvent) {
            events.append(event)
        }
    }

    /// A delegate that implements ONLY the pre-existing required methods — proving the new
    /// `didReceiveQualifyingEvent` default no-op extension exists (mirrors `willRetryReconnect`), so
    /// every existing conformer (WatchPumpClient, test/bench/harness delegates) keeps compiling.
    final class NoOpStubDelegate: PumpBLEClientDelegate {
        func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {}
        func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {}
        func pumpClientDidBecomeReady(_ client: PumpBLEClient) {}
        func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {}
        func pumpClient(_ client: PumpBLEClient, didError error: Error) {}
    }

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

    // MARK: - PumpBLEClient.handleQualifyingEventsFrame: decode -> dispatch -> conditional clear

    /// An all-zero bitmap triggers NO dispatch and NO clear.
    @Test func emptyBitmapDispatchesNothingAndClearsNothing() {
        let client = PumpBLEClient.forUnitTest()
        let delegate = RecordingDelegate()
        client.delegate = delegate
        var clearCount = 0

        client.handleQualifyingEventsFrame(le4(0)) { clearCount += 1 }

        #expect(delegate.events.isEmpty)
        #expect(clearCount == 0)
    }

    /// A non-empty bitmap with NO delivery transaction in flight dispatches the typed event AND
    /// issues exactly one clear write.
    @Test func nonEmptyBitmapDispatchesAndClearsWhenIdle() {
        let client = PumpBLEClient.forUnitTest()
        let delegate = RecordingDelegate()
        client.delegate = delegate
        var clearCount = 0
        #expect(!client.transactions.hasSerializedInFlight)

        client.handleQualifyingEventsFrame(le4(524_288)) { clearCount += 1 }  // PUMP_COMMUNICATIONS_SUSPENDED

        #expect(delegate.events == [.pumpCommunicationsSuspended])
        #expect(clearCount == 1)
    }

    /// Delivery-transaction safety (freeze reconciliation): when a delivery-class (`serialized`)
    /// transaction IS in flight, the clear write is DEFERRED — not issued — but the typed event is
    /// still decoded/dispatched.
    @Test func nonEmptyBitmapDefersClearWhenDeliveryInFlight() async throws {
        let client = PumpBLEClient.forUnitTest()
        let delegate = RecordingDelegate()
        client.delegate = delegate

        // Register a serialized (delivery-class) transaction without any CoreBluetooth involvement —
        // `perform`'s `write` thunk is a fake txId, mirroring PumpTransactionCoordinatorTests.
        let task = Task { @MainActor in
            try await client.transactions.perform(
                expectedResponseOn: .control, opCode: 0x03, deadline: 5, serialized: true
            ) { 9 }
        }
        // Bounded sleep-backed poll (not a `Task.yield()` hot-spin): a tight yield loop never actually
        // relinquishes a cooperative-pool thread, and under the FULL combined test suite (hundreds of
        // concurrent async tests) that starved the runtime badly enough to abort the whole process
        // (observed locally: `swift test` with no filter crashed with SIGABRT partway through; every
        // individually-filtered suite, including this one, was consistently green). A real `Task.sleep`
        // actually suspends, so it can't contribute to that class of exhaustion.
        var attempts = 0
        while !client.transactions.hasSerializedInFlight && attempts < 200 {
            try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms; 200 attempts = 200ms ceiling
            attempts += 1
        }

        var clearCount = 0
        client.handleQualifyingEventsFrame(le4(1)) { clearCount += 1 }  // .alert

        #expect(delegate.events == [.alert], "the event must still be dispatched even when the clear defers")
        #expect(clearCount == 0, "the clear write must be deferred while a delivery transaction is in flight")

        // Cleanup: resolve the pending transaction so the test doesn't leak a suspended continuation.
        client.transactions.failAll(.connectionLost)
        _ = await task.result
    }

    /// Additive-delegate interface (mirrors `willRetryReconnect`): a stub conformer that implements
    /// only the pre-existing methods still compiles and runs without crashing when a qualifying event
    /// is dispatched — the default no-op extension absorbs the call.
    @Test func stubDelegateWithoutOverrideCompilesAndRunsViaDefaultNoOp() {
        let client = PumpBLEClient.forUnitTest()
        client.delegate = NoOpStubDelegate()
        var clearCount = 0

        client.handleQualifyingEventsFrame(le4(2)) { clearCount += 1 }  // .alarm

        #expect(clearCount == 1, "dispatch to the default no-op must not prevent the clear from still firing")
    }
}
