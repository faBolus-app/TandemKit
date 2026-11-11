import Foundation
import TandemMessages

/// LastBolusStatusV3 (0xBA → 0xBB) without the library's Mobi tag, so the bench can ask a t:slim.
///
/// The library tags `LastBolusStatusV3Request` Mobi-only and says the tag stands until a capture
/// shows a t:slim answering it; the link refuses a tagged read to any other model. This copy has the
/// same opcode, characteristic and empty cargo (the same bytes, checked against the library type in
/// the tests), so the link treats it as the same command: the support matrix and its careful probing
/// apply as they would. It lives here, in a package no app links, so lifting the tag can't reach one.
public struct BenchLastBolusStatusV3Request: Message {
    public static let props = MessageProps(
        opCode: LastBolusStatusV3Request.props.opCode, size: 0, type: .request, characteristic: .currentStatus,
        responseOpCode: LastBolusStatusV3Request.props.responseOpCode)
    public var cargo: [UInt8] = []
    public init() {}
    public mutating func parse(_ raw: [UInt8]) { cargo = raw }
}
