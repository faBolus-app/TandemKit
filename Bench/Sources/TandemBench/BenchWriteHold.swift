import Foundation
import TandemMessages

/// The cancel-overlap check's write order: whether a t:slim answers a control request written while a
/// request on another characteristic still waits for its reply, as Mobi writes its cancel.
///
/// The link sends one request at a time, and the bench doesn't change that. Instead the bench transport
/// holds one request's write back: the link gives up on it at its short deadline and sends the next, and
/// the held write goes out just before that next control write. The pump then has the held request
/// outstanding when the control request arrives. Both are the link's own frames, with consecutive txIds;
/// only when the first one reaches the pump changes.
public struct BenchWriteHold: Sendable {
    /// The characteristic whose next write is held back, until it is.
    public private(set) var waitingFor: Characteristic?
    /// The held write, until it goes out.
    public private(set) var pending: [[UInt8]]?
    /// The held request's characteristic and txId, kept after it goes out so its reply can be told apart.
    public private(set) var heldOn: Characteristic?
    public private(set) var heldTxId: UInt8?

    public init() {}

    /// Hold the next write on `characteristic`. Never the control characteristic: the held write has to
    /// go out before a control write.
    public mutating func hold(next characteristic: Characteristic) {
        guard characteristic != .control else { return }
        self = BenchWriteHold()
        waitingFor = characteristic
    }

    /// The writes to make now, in order, for the link's write of `packets` on `characteristic`: none when
    /// it is the one held back; the held one and then this one for a control write; otherwise this one.
    public mutating func writes(
        _ characteristic: Characteristic, _ packets: [[UInt8]]
    ) -> [(characteristic: Characteristic, packets: [[UInt8]])] {
        if characteristic == waitingFor, let first = packets.first, first.count >= 2 {
            waitingFor = nil
            pending = packets
            heldOn = characteristic
            heldTxId = first[1]
            return []
        }
        if characteristic == .control, let held = pending, let heldOn {
            pending = nil
            return [(heldOn, held), (characteristic, packets)]
        }
        return [(characteristic, packets)]
    }

    /// Whether `packet`, a notification on `characteristic`, belongs to the held request's reply.
    public func answersHeld(_ characteristic: Characteristic, _ packet: [UInt8]) -> Bool {
        guard let heldOn, let heldTxId, pending == nil else { return false }
        return characteristic == heldOn && packet.count >= 2 && packet[1] == heldTxId
    }

    /// Forgets the check: the link dropped, or it is over. A write still held is never sent.
    public mutating func clear() { self = BenchWriteHold() }
}
