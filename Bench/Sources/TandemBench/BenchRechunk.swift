import Foundation

/// Re-cuts one request's packets at another chunk size, for the control chunk-size check.
///
/// `Packetize` cuts control requests at 40 bytes and every other request at 18 (pumpX2 calls the 40 a
/// guess). The bench checks whether a t:slim accepts a control request cut at 18 without touching the
/// library: the bench transport re-cuts the packets it is handed. Each packet is
/// `[packetsRemaining, txId] + chunk`; the framed bytes, signature and CRC are unchanged, only where the
/// packets split. The result is what `Packetize.packetize(_:maxChunkSize:)` gives at that size.
public enum BenchRechunk {
    /// nil when the packets aren't one request's (a packet under 2 bytes, or mixed txIds), or the size
    /// can't be counted in the one-byte header.
    public static func split(_ packets: [[UInt8]], chunk: Int) -> [[UInt8]]? {
        guard chunk > 0, let first = packets.first, first.count >= 2 else { return nil }
        let txId = first[1]
        guard packets.allSatisfy({ $0.count >= 2 && $0[1] == txId }) else { return nil }
        let framed = packets.flatMap { $0.dropFirst(2) }
        guard !framed.isEmpty else { return nil }
        let count = (framed.count + chunk - 1) / chunk
        guard count <= 256 else { return nil }
        return (0..<count).map { i in
            let body = framed[(i * chunk)..<min((i + 1) * chunk, framed.count)]
            return [UInt8(count - 1 - i), txId] + body
        }
    }
}
