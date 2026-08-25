import Foundation
import TandemMessages
import TandemBLE

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
        case .reconnectExhausted:
            // The kit's reconnect ladder gave up without reaching `.ready` (a flapping peer during
            // pairing). The link is down exactly like `.disconnected`; the driver has no notion of
            // "stop auto-retrying" today, so this maps 1:1 rather than introducing a new driver-facing
            // state.
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
            // U1-06: forward the session key on the RESPONSE-PARSE call, exactly like the SEND call
            // above already does (`authenticationKey: signing?.authKey ?? []`) — omitting it here meant
            // a signed response on this LoopKit path was never HMAC-verified (VA-04 protects the app
            // path; this call site silently opted out of it).
            let parsed = try ResponseParser.parse(frame: frame, characteristic: message.characteristic,
                                                  authenticationKey: signing?.authKey ?? [])
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
        // Pre-existing blocking build defect (unrelated to U1-06, fixed here as a Rule-3 blocker
        // since it makes this file fail to compile): PumpBLEClient.ClientError grew
        // `.unsupportedOnDevice(opcode:)` (D-08 device/API send gate) without this switch being
        // updated. Its own doc comment says it is refused "BEFORE any byte is emitted, exactly like
        // writeBlocked" — map it the same way.
        case .writeBlocked, .unsupportedOnDevice: return .writeBlocked
        case .unknownCharacteristic, .writeFailed, .reconnectLoopDetected: return .connectionLost
        }
    }
}
