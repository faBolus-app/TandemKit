import Foundation
import PumpX2Messages
import PumpX2BLE

/// The transport seam the driver is written against.
///
/// `PumpBLEClient` is a concrete `@MainActor final class` with no protocol of its own, and
/// `sendAwaitingResponse` hands back a raw frame that must be run through `ResponseParser`. This
/// protocol abstracts exactly what the driver needs — "send a request, get a *typed* response back,
/// under an optional delivery-policy elevation" — so the delivery choreography can be unit-tested with
/// a `FakeTandemConnection` (no CoreBluetooth, no hardware). `PumpBLEConnection` adapts the real client.
@MainActor
public protocol TandemPumpConnection: AnyObject {
    var connectionState: TandemConnectionState { get }

    /// Send `message` and await the pump's correlated, parsed response.
    ///
    /// - `signing`: non-nil for a signed message (auth key + the `TimeSinceReset` signing timestamp).
    /// - `allowInsulinDelivery`: MUST be true for any `modifiesInsulinDelivery` message, or the kit
    ///   fails closed before writing.
    /// - `serialized`: true marks a delivery-class transaction — at most one may be in flight.
    ///
    /// Throws `TandemTransportError`. A `.timedOut` / `.connectionLost` raised *after* a delivery write
    /// was issued is the indeterminate case and MUST be treated as uncertain delivery, never as failure.
    func send(_ message: any Message,
              signing: TandemSigning?,
              allowInsulinDelivery: Bool,
              serialized: Bool,
              deadline: TimeInterval) async throws -> any Message

    /// Run `body` with the write policy elevated to allow delivery; the policy is always restored to
    /// read-only on exit (success, throw, or cancellation).
    @discardableResult
    func withDeliveryPolicy<T>(_ body: @MainActor () async throws -> T) async rethrows -> T
}

/// A driver-facing connection state, decoupled from `PumpBLEClient.State`.
public enum TandemConnectionState: Equatable, Sendable {
    case ready          // linked and authenticated; writes possible
    case connecting     // scanning / connecting / discovering
    case disconnected   // was connected, now not
    case unavailable    // radio off / unauthorized / unsupported / unknown
}

/// Per-signed-send material. `authKey` is the per-command HMAC key from pairing; `pumpTimeSinceReset`
/// is a *fresh* `TimeSinceResetResponse.signingTimestamp` (the driver refreshes it before each signed
/// delivery window).
public struct TandemSigning: Equatable, Sendable {
    public var authKey: [UInt8]
    public var pumpTimeSinceReset: UInt32
    public init(authKey: [UInt8], pumpTimeSinceReset: UInt32) {
        self.authKey = authKey
        self.pumpTimeSinceReset = pumpTimeSinceReset
    }
}

/// Transport failures, normalized across `PumpBLEClient.ClientError` and
/// `PumpTransactionCoordinator.TxError`.
public enum TandemTransportError: Error, Equatable {
    case notReady
    /// Deadline elapsed with no response. After a delivery write, this is INDETERMINATE.
    case timedOut
    /// The link dropped mid-transaction. After a delivery write, this is INDETERMINATE.
    case connectionLost
    case cancelled
    /// Another delivery-class transaction is already in flight.
    case busy
    /// The write policy (or the insulin-delivery gate) refused the message before any bytes were sent.
    case writeBlocked
    /// The response frame could not be parsed, or was the wrong type.
    case badResponse(String)

    /// Whether, if this was raised after a delivery write was issued, the outcome is unknowable and
    /// must be handled as uncertain delivery rather than a clean failure.
    public var isIndeterminateAfterWrite: Bool {
        switch self {
        case .timedOut, .connectionLost: return true
        case .notReady, .cancelled, .busy, .writeBlocked, .badResponse: return false
        }
    }
}
