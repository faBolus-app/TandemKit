import Foundation
import LoopKit

/// Driver-level errors, mapped to LoopKit `PumpManagerError` at the boundary.
public enum TandemDriverError: LocalizedError, Equatable {
    case notPaired
    case notConnected
    case busy
    case invalidDose
    case denied(String)
    case protocolError(String)
    case unsupported(String)
    case transport(TandemTransportError)

    public var errorDescription: String? {
        switch self {
        case .notPaired: return "The pump is not paired."
        case .notConnected: return "No live connection to the pump."
        case .busy: return "A delivery is already in progress or its outcome is unresolved."
        case .invalidDose: return "The requested dose is not valid."
        case .denied(let why): return "The pump rejected the command: \(why)"
        case .protocolError(let why): return "Pump communication error: \(why)"
        case .unsupported(let what): return "Not supported by this driver: \(what)"
        case .transport(let t): return "Transport error: \(t)"
        }
    }

    /// Map to the appropriate LoopKit `PumpManagerError`. A transport error raised after a delivery
    /// write is surfaced as `.uncertainDelivery` so the host's own reconciliation stays correct.
    var asPumpManagerError: PumpManagerError {
        switch self {
        case .notPaired, .invalidDose, .unsupported: return .configuration(self)
        case .notConnected, .busy, .denied: return .deviceState(self)
        case .protocolError: return .communication(self)
        case .transport(let t): return t.isIndeterminateAfterWrite ? .uncertainDelivery : .communication(self)
        }
    }
}
