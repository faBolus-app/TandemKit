import Foundation

/// Tracks the next transaction id (0–255, wrapping) shared across a session.
/// Port of `com.jwoglom.pumpx2.pump.messages.TransactionId`.
public final class TransactionId {
    private var value: UInt8 = 0

    public init(start: UInt8 = 0) { self.value = start }

    /// Returns the current id then increments (wrapping at 256), matching upstream semantics.
    public func nextThenIncrement() -> UInt8 {
        defer { value = value &+ 1 }
        return value
    }

    public var current: UInt8 { value }
}
