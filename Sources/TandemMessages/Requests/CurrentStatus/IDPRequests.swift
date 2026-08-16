import Foundation

/// Insulin-delivery-profile (IDP) read requests. `ProfileStatusResponse` lists which IDP **ids**
/// exist; these two fetch the details of a given profile by id (NOT slot index):
/// `IDPSettingsRequest` returns the profile's name + segment count + insulin duration / max bolus,
/// and `IDPSegmentRequest` returns one time segment's basal rate / carb ratio / target BG / ISF.
///
/// Ports of `request/currentStatus/IDPSettingsRequest` and `IDPSegmentRequest`. Byte-parity is
/// covered in OracleParityTests.

/// Requests settings for the profile with the given `idpId` (opcode 64 → 65). 1-byte cargo.
public struct IDPSettingsRequest: Message {
    public static let props = MessageProps(opCode: 64, size: 1, type: .request,
                                           characteristic: .currentStatus, responseOpCode: 65)
    public var cargo: [UInt8]
    public private(set) var idpId: Int = 0
    public init() { cargo = [] }
    public init(idpId: Int) {
        self.idpId = idpId
        self.cargo = Bytes.firstByteLittleEndian(idpId)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3)
        cargo = body
        if !body.isEmpty { idpId = Int(body[0]) }
    }
}

/// Requests one time-segment (`segmentIndex`) of the profile with the given `idpId`
/// (opcode 66 → 67). 2-byte cargo: [idpId, segmentIndex].
public struct IDPSegmentRequest: Message {
    public static let props = MessageProps(opCode: 66, size: 2, type: .request,
                                           characteristic: .currentStatus, responseOpCode: 67)
    public var cargo: [UInt8]
    public private(set) var idpId: Int = 0
    public private(set) var segmentIndex: Int = 0
    public init() { cargo = [] }
    public init(idpId: Int, segmentIndex: Int) {
        self.idpId = idpId
        self.segmentIndex = segmentIndex
        self.cargo = [UInt8(idpId & 0xFF), UInt8(segmentIndex & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = raw.count == Self.props.size ? raw : Bytes.dropFirst(raw, 3)
        cargo = body
        if body.count >= 2 { idpId = Int(body[0]); segmentIndex = Int(body[1]) }
    }
}
