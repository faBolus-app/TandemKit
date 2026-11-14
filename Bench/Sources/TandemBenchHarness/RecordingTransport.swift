import Foundation
import TandemBLE
import TandemBench
import TandemLink
import TandemMessages

/// CoreBluetooth with every packet written to the transcript: each write and notification with its
/// characteristic and bytes, and the Bluetooth events between them (connects, drops, subscriptions).
///
/// Authorization frames are logged by length only: a pairing exchange is the one thing in a transcript
/// that could help someone work out a pairing code. `PUMP_RECORD_PAIRING=1` keeps them, for a test of
/// the legacy pairing check built from a real exchange; such a transcript stays private.
///
/// `controlChunk` re-cuts control writes at another size (the chunk-size check); the framed bytes don't
/// change, only where the packets split. Nothing else is altered.
@MainActor
final class RecordingTransport: LinkTransport {
    var report: ((LinkInput) -> Void)?
    private let inner: CoreBluetoothTransport
    private let transcript: Transcript
    var controlChunk: Int?
    /// Keep authorization frames in the transcript.
    var recordPairing = false
    /// Called for each request written (not the qualifying-events clear or pairing frames).
    var onRequestWritten: (() -> Void)?
    /// The cancel-overlap check: one write held back until just before the next control write.
    var hold = BenchWriteHold()
    /// When the held write went out, when its reply started arriving, and that reply's opcode (an op-77
    /// answers too, but isn't the read's reply).
    private(set) var heldSentAt: Date?
    private(set) var heldAnsweredAt: Date?
    private(set) var heldAnswerOpCode: UInt8?
    /// The link-drop bolus: cancel the connection shortly after the next control write goes out.
    var dropAfterNextControlWrite = false
    private var peripheral: UUID?

    init(transcript: Transcript) {
        self.transcript = transcript
        inner = CoreBluetoothTransport(restoreIdentifier: nil)
        inner.report = { [weak self] input in
            guard let self else { return }
            self.log(input)
            self.report?(input)
        }
    }

    /// Ends the connection as a drop would: the link sees it disconnect and reconnects by itself.
    func dropNow() {
        guard let peripheral else { return transcript.line("no connection to drop") }
        transcript.line("dropping the link on purpose")
        inner.perform(.cancelConnection(peripheral))
    }

    func perform(_ command: TransportCommand) {
        if case .discover(let id) = command { peripheral = id }
        guard case .write(let characteristic, let packets) = command else {
            transcript.detail("bt> \(command)")
            inner.perform(command)
            return
        }
        var out = packets
        if characteristic == .control, let chunk = controlChunk {
            if let cut = BenchRechunk.split(packets, chunk: chunk) {
                out = cut
                transcript.line("control write re-cut at \(chunk) bytes: \(packets.count) -> \(cut.count) packet(s)")
            } else {
                transcript.line("control write left as built: it couldn't be re-cut at \(chunk)")
            }
        }
        let writes = hold.writes(characteristic, out)
        if writes.isEmpty {
            transcript.line(
                "held back the \(characteristic.name) write (txId \(hold.heldTxId ?? 0)) until the next control write")
        }
        for (target, packets) in writes {
            if target != characteristic {
                heldSentAt = Date()
                heldAnsweredAt = nil
                heldAnswerOpCode = nil
                transcript.line("sent the held \(target.name) write (txId \(hold.heldTxId ?? 0)) just before this one")
            }
            write(target, packets)
        }
    }

    private func write(_ characteristic: Characteristic, _ out: [[UInt8]]) {
        if characteristic == .authorization, !recordPairing {
            transcript.detail("tx \(characteristic.name) \(out.count) packet(s), \(out.map(\.count)) bytes (redacted)")
        } else {
            for (i, p) in out.enumerated() {
                transcript.detail("tx \(characteristic.name) \(i + 1)/\(out.count) [\(p.count)] \(Hex.encode(p))")
            }
            if characteristic != .qualifyingEvents, characteristic != .authorization { onRequestWritten?() }
        }
        inner.perform(.write(characteristic, out))
        if characteristic == .control, dropAfterNextControlWrite {
            dropAfterNextControlWrite = false
            // A moment for the packets to reach the radio; the reply takes longer than this.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                self.dropNow()
            }
        }
    }

    private func log(_ input: LinkInput) {
        switch input {
        case .notified(let characteristic, let bytes):
            // A reply's first packet is [packets left, txId] then the frame, which starts with its opcode.
            if heldAnsweredAt == nil, hold.answersHeld(characteristic, bytes) {
                heldAnsweredAt = Date()
                heldAnswerOpCode = bytes.count > 2 ? bytes[2] : nil
            }
            if characteristic == .authorization, !recordPairing {
                transcript.detail("rx \(characteristic.name) [\(bytes.count)] (redacted)")
            } else {
                transcript.detail("rx \(characteristic.name) [\(bytes.count)] \(Hex.encode(bytes))")
            }
        case .discovered:
            break  // repeats every advertisement while scanning; the link reports each pump once
        case .disconnected:
            // A write still held never goes out on a later connection.
            hold.clear()
            transcript.detail("bt< \(input)")
        default:
            transcript.detail("bt< \(input)")
        }
    }
}
