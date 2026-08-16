import Foundation

/// Request vs. response. Opcodes are even/odd pairs by convention (request even, response odd).
/// Port of `com.jwoglom.pumpx2.pump.messages.MessageType`.
public enum MessageType: String, Sendable {
    case request
    case response

    public static func fromOpcodeBestEffort(_ opcode: Int) -> MessageType {
        opcode % 2 == 0 ? .request : .response
    }
}
