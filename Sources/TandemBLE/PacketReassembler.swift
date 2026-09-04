import Foundation

/// Reassembles multi-packet BLE notifications into a single message frame.
///
/// Each raw packet is `[packetsRemaining, txId, internalCargo...]`. `packetsRemaining` counts
/// down to 0 on the final packet. The reassembled frame is the concatenation of every
/// packet's `internalCargo` — i.e. `[opcode, txId, len, cargo..., crc]` — ready for parsing.
///
/// Mirrors the packet-merge behavior of upstream `PacketArrayList`, not `Packet.merge` — the
/// latter enforces none of this type's txId / packetsRemaining / 512-byte protections and is not
/// a usable entry point for this path.
public struct PacketReassembler {
    /// Hard ceiling on the reassembled buffer. Comfortably above the protocol max frame of
    /// 260 bytes (3-byte header + 255 max length byte + 2-byte CRC); the 512 headroom bounds a
    /// peer that never terminates a sequence so the buffer cannot grow unboundedly (memory DoS).
    private static let maxReassembledFrameSize = 512

    private var accumulated: [UInt8] = []
    private var expectedTxId: UInt8?
    /// The `packetsRemaining` value expected on the next packet of the current sequence.
    /// Set on the first packet; each subsequent packet must decrement it by exactly 1.
    private var expectedRemaining: UInt8?

    public init() {}

    /// Ingests one raw notification packet. Returns the full frame when the final packet
    /// (`packetsRemaining == 0`) arrives, otherwise nil. Returns nil and resets on malformed
    /// input: too short, a txId mismatch across a multi-packet sequence, a `packetsRemaining`
    /// that does not decrement by exactly 1 within a sequence (mis-ordered/duplicated), or an
    /// accumulation that would exceed `maxReassembledFrameSize`.
    public mutating func ingest(_ raw: [UInt8]) -> [UInt8]? {
        guard raw.count >= 2 else {
            reset()
            return nil
        }
        let packetsRemaining = raw[0]
        let txId = raw[1]
        let internalCargo = Array(raw[2...])

        if let expected = expectedTxId, expected != txId {
            // A new transaction started mid-stream; restart from this packet.
            reset()
        }

        // A fresh sequence starts either on the very first packet or immediately after a
        // txId-change reset above. Its first packet accepts any `packetsRemaining`; every
        // subsequent packet of the same txId must decrement by exactly 1.
        if expectedTxId == nil {
            expectedRemaining = packetsRemaining
        } else {
            guard let prev = expectedRemaining, packetsRemaining == prev &- 1 else {
                reset()
                return nil
            }
            expectedRemaining = packetsRemaining
        }

        // Bound accumulation: never let the buffer exceed the frame cap.
        if accumulated.count + internalCargo.count > Self.maxReassembledFrameSize {
            reset()
            return nil
        }

        expectedTxId = txId
        accumulated.append(contentsOf: internalCargo)

        if packetsRemaining == 0 {
            let frame = accumulated
            reset()
            return frame
        }
        return nil
    }

    public mutating func reset() {
        accumulated.removeAll()
        expectedTxId = nil
        expectedRemaining = nil
    }
}
