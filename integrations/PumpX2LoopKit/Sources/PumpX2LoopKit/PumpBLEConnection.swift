import Foundation
import PumpX2Messages
import PumpX2BLE

/// Adapts the real `PumpBLEClient` to the driver's `TandemPumpConnection` seam.
///
/// This is the ONLY file that touches CoreBluetooth-backed transport. It maps the client's raw-frame
/// `sendAwaitingResponse` + `ResponseParser` flow into the typed `send` the driver expects, and
/// normalizes `PumpBLEClient.ClientError` / `PumpTransactionCoordinator.TxError` into
/// `TandemTransportError` — crucially preserving the indeterminate distinction (`timedOut` /
/// `connectionLost` after a delivery write).
@MainActor
public final class PumpBLEConnection: TandemPumpConnection {
    private let client: PumpBLEClient

    public init(client: PumpBLEClient) {
        self.client = client
    }

    public var connectionState: TandemConnectionState {
        switch client.state {
        case .ready:
            return .ready
        case .idle, .scanning, .connecting, .discovering:
            return .connecting
        case .disconnected:
            return .disconnected
        case .poweredOff, .unauthorized, .unsupported, .resetting, .unknown:
            return .unavailable
        }
    }

    public func send(_ message: any Message,
                     signing: TandemSigning?,
                     allowInsulinDelivery: Bool,
                     serialized: Bool,
                     deadline: TimeInterval) async throws -> any Message {
        let frame: [UInt8]
        do {
            frame = try await client.sendAwaitingResponse(
                message,
                authenticationKey: signing?.authKey ?? [],
                pumpTimeSinceReset: signing?.pumpTimeSinceReset ?? 0,
                allowInsulinDelivery: allowInsulinDelivery,
                deadline: deadline,
                serialized: serialized
            )
        } catch let e as PumpTransactionCoordinator.TxError {
            throw Self.map(e)
        } catch let e as PumpBLEClient.ClientError {
            throw Self.map(e)
        }
        do {
            let parsed = try ResponseParser.parse(frame: frame, characteristic: message.characteristic)
            return parsed.message
        } catch {
            throw TandemTransportError.badResponse("\(error)")
        }
    }

    @discardableResult
    public func withDeliveryPolicy<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        try await client.withWritePolicy(.allowDelivery, body)
    }

    private static func map(_ e: PumpTransactionCoordinator.TxError) -> TandemTransportError {
        switch e {
        case .timedOut: return .timedOut
        case .connectionLost: return .connectionLost
        case .cancelled: return .cancelled
        case .busy: return .busy
        }
    }

    private static func map(_ e: PumpBLEClient.ClientError) -> TandemTransportError {
        switch e {
        case .notReady: return .notReady
        case .writeBlocked: return .writeBlocked
        case .unknownCharacteristic, .writeFailed: return .connectionLost
        }
    }
}
