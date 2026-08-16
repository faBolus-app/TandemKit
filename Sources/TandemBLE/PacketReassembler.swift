import Foundation

/// Reassembles multi-packet BLE notifications into a single message frame.
///
/// Each raw packet is `[packetsRemaining, txId, internalCargo...]`. `packetsRemaining` counts
/// down to 0 on the final packet. The reassembled frame is the concatenation of every
/// packet's `internalCargo` — i.e. `[opcode, txId, len, cargo..., crc]` — ready for parsing.
///
/// Mirrors the packet-merge behavior of upstream `Packet.merge` / `PacketArrayList`.
public struct PacketReassembler {
    private var accumulated: [UInt8] = []
    private var expectedTxId: UInt8?

    public init() {}

    /// Ingests one raw notification packet. Returns the full frame when the final packet
    /// (`packetsRemaining == 0`) arrives, otherwise nil. Returns nil and resets on malformed
    /// input (too short, or a txId mismatch across a multi-packet sequence).
    public mutating func ingest(_ raw: [UInt8]) -> [UInt8]? {
        guard raw.count >= 2 else { reset(); return nil }
        let packetsRemaining = raw[0]
        let txId = raw[1]
        let internalCargo = Array(raw[2...])

        if let expected = expectedTxId, expected != txId {
            // A new transaction started mid-stream; restart from this packet.
            reset()
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
    }
}
