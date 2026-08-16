import Foundation

/// One raw BLE packet. A sequence of `Packet`s over a characteristic makes up one `Message`.
/// Port of `com.jwoglom.pumpx2.pump.messages.bluetooth.models.Packet`.
///
/// Wire layout of `build()`: `[packetsRemaining, transactionId, internalCargo...]`. For the
/// first/only packet, `internalCargo` is `[opcode, txId, len, cargo..., (hmac), crcLo, crcHi]`.
public struct Packet: Equatable, Sendable {
    public let packetsRemaining: UInt8
    public let transactionId: UInt8
    public let internalCargo: [UInt8]

    public init(packetsRemaining: UInt8, transactionId: UInt8, internalCargo: [UInt8]) {
        self.packetsRemaining = packetsRemaining
        self.transactionId = transactionId
        self.internalCargo = internalCargo
    }

    public func build() -> [UInt8] {
        [packetsRemaining, transactionId] + internalCargo
    }

    public func merge(_ newPacket: Packet) -> Packet {
        Packet(
            packetsRemaining: newPacket.packetsRemaining,
            transactionId: transactionId,
            internalCargo: internalCargo + newPacket.internalCargo
        )
    }
}
