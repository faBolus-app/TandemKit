import Foundation
import CryptoKit

/// Converts a `Message` into wire BLE packets: prepends opcode/txId/length framing, applies
/// the optional 24-byte HMAC-SHA1 signature block for signed (insulin-affecting) messages,
/// appends CRC-16, then chunks into MTU-sized packets.
///
/// Byte-exact port of `com.jwoglom.pumpx2.pump.messages.Packetize`. Verified against the
/// cliparser oracle.
public enum Packetize {
    public static let defaultMaxChunkSize = 18  // observed for currentStatus
    public static let controlMaxChunkSize = 40  // works for control requests

    /// Thrown when a message that modifies insulin delivery is packetized without the caller
    /// having explicitly enabled insulin-affecting actions. Mirrors upstream's gate.
    public struct ActionsAffectingInsulinDeliveryNotEnabledError: Error {}

    /// Input that can't be framed. Upstream (pumpx2 9625c529) rejects a missing message or cargo
    /// and a non-positive partition size rather than carrying on; these are the Swift equivalents,
    /// thrown before any byte is built so a bad message never reaches the pump half-formed.
    public enum PacketizeError: Error, Equatable {
        /// A chunk size below 1 sent the whole packet as one unchunked write; one so small that
        /// the packet needs more than 256 chunks can't be counted in the one-byte
        /// `packetsRemaining`.
        case invalidChunkSize(Int)
        /// The framed length (cargo plus any 24-byte signature) doesn't fit the one-byte length
        /// field.
        case cargoTooLong(opCode: UInt8, framedLength: Int)
        /// A signed message with no key would carry an HMAC the pump can't verify.
        case missingAuthenticationKey(opCode: UInt8)
    }

    static func determineMaxChunkSize(_ message: Message) -> Int {
        if message.characteristic == .control && message.type == .request {
            return controlMaxChunkSize
        }
        return defaultMaxChunkSize
    }

    /// - Parameters:
    ///   - authenticationKey: HMAC key for signed messages (the pairing code / derived
    ///     secret). Ignored for unsigned messages.
    ///   - pumpTimeSinceReset: seconds since pump reset, embedded into the signed block.
    ///   - actionsAffectingInsulinDeliveryEnabled: safety gate; must be true to packetize a
    ///     message with `modifiesInsulinDelivery`.
    public static func packetize(
        _ message: Message,
        authenticationKey: [UInt8] = [],
        txId: UInt8,
        pumpTimeSinceReset: UInt32 = 0,
        actionsAffectingInsulinDeliveryEnabled: Bool = false,
        maxChunkSize: Int? = nil
    ) throws -> [Packet] {
        // The delivery wall first, so a closed tier is what a caller sees, not a framing error.
        if message.props.modifiesInsulinDelivery && !actionsAffectingInsulinDeliveryEnabled {
            throw ActionsAffectingInsulinDeliveryNotEnabledError()
        }
        let cargo = message.cargo
        var length = 3 + cargo.count
        if message.signed { length += 24 }
        guard length - 3 <= Int(UInt8.max) else {
            throw PacketizeError.cargoTooLong(opCode: message.opCode, framedLength: length - 3)
        }
        if message.signed && authenticationKey.isEmpty {
            throw PacketizeError.missingAuthenticationKey(opCode: message.opCode)
        }
        let chunkSize = maxChunkSize ?? determineMaxChunkSize(message)
        // +2 for the CRC. packetsRemaining counts down from chunks-1, so at most 256 chunks.
        guard chunkSize > 0, (length + 2 + chunkSize - 1) / chunkSize <= Int(UInt8.max) + 1 else {
            throw PacketizeError.invalidChunkSize(chunkSize)
        }

        var packet = [UInt8](repeating: 0, count: length)
        packet[0] = message.opCode
        packet[1] = txId
        packet[2] = UInt8(length - 3)
        for (i, b) in cargo.enumerated() { packet[3 + i] = b }


        if message.signed {
            let i = length - 20
            var messageData = [UInt8](repeating: 0, count: i)
            for k in 0..<i { messageData[k] = packet[k] }
            // Embed pumpTimeSinceReset (4 bytes LE) at offset length-24 == i-4.
            let tsr = Bytes.toUint32(pumpTimeSinceReset)
            for k in 0..<4 { messageData[(length - 24) + k] = tsr[k] }

            let hmac = doHmacSha1(messageData, key: authenticationKey)  // 20 bytes
            for k in 0..<i { packet[k] = messageData[k] }
            for k in 0..<hmac.count { packet[i + k] = hmac[k] }
        }

        // Append CRC-16 over the full framed packet.
        let crc = Bytes.calculateCRC16(packet)
        let packetWithCRC = packet + crc

        // Chunk into maxChunkSize packets; packetsRemaining counts down from N-1 to 0.
        let chunked = partition(packetWithCRC, chunkSize)

        var packets = [Packet]()
        var b = chunked.count - 1
        for chunk in chunked {
            packets.append(Packet(packetsRemaining: UInt8(b), transactionId: txId, internalCargo: chunk))
            b -= 1
        }
        return packets
    }

    static func partition(_ bytes: [UInt8], _ size: Int) -> [[UInt8]] {
        precondition(size > 0, "partition size must be positive; packetize checks it first")
        var out = [[UInt8]]()
        var i = 0
        while i < bytes.count {
            out.append(Array(bytes[i..<min(i + size, bytes.count)]))
            i += size
        }
        return out
    }

    /// HMAC-SHA1(data, key) → 20 bytes. Mirrors upstream's Apache commons `HmacUtils`.
    public static func doHmacSha1(_ data: [UInt8], key: [UInt8]) -> [UInt8] {
        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(data),
            using: SymmetricKey(data: Data(key))
        )
        return [UInt8](mac)
    }

    /// Constant-time verification of an HMAC-SHA1 `mac` over `data` under `key`. Mirrors
    /// `doHmacSha1`'s algorithm so it is byte-exact with the oracle's `PacketArrayList.validate`, but
    /// compares via CryptoKit's `isValidAuthenticationCode` (constant-time; returns false — never traps —
    /// on a wrong-length mac). Use this to verify signed pump RESPONSES; never compare digests with `==`.
    public static func isValidHmacSha1(mac: [UInt8], data: [UInt8], key: [UInt8]) -> Bool {
        return HMAC<Insecure.SHA1>.isValidAuthenticationCode(
            Data(mac),
            authenticating: Data(data),
            using: SymmetricKey(data: Data(key))
        )
    }
}
