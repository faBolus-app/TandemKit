import Foundation

/// Insulin-delivery-profile CRUD (A2). Create/Delete/Rename **modify insulin delivery** (they can
/// change the active profile set); SetIDPSegment/SetIDPSettings edit a profile's parameters
/// (upstream flags them non-insulin). All signed CONTROL; gate behind advanced-control + Mobi and
/// bench-validate the insulin-affecting ones. Ports of the `request/control/*IDP*` classes.

/// Creates a new IDP with a first time-segment (opcode 0xE6 → 0xE7). 35-byte cargo. modInsulin.
public struct CreateIDPRequest: Message {
    public static let props = MessageProps(opCode: 0xE6, size: 35, signed: true, type: .request, characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xE7)
    public var cargo: [UInt8]
    public private(set) var name = ""
    public init() { cargo = [] }
    public init(name: String, firstSegmentProfileCarbRatio: UInt32, firstSegmentProfileStartTime: Int = 0,
                firstSegmentProfileBasalRate: Int, firstSegmentProfileTargetBG: Int, firstSegmentProfileISF: Int,
                profileInsulinDuration: Int, timeSegmentBitmask: Int, bolusSettingsBitmask: Int,
                carbEntry: Int, idpSourceId: Int) {
        self.name = name
        self.cargo = Bytes.combine(
            Bytes.writeString(name, 17),
            Bytes.toUint32(firstSegmentProfileCarbRatio),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileStartTime),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileBasalRate),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileTargetBG),
            Bytes.firstTwoBytesLittleEndian(firstSegmentProfileISF),
            Bytes.firstTwoBytesLittleEndian(profileInsulinDuration),
            [UInt8(timeSegmentBitmask & 0xFF), UInt8(bolusSettingsBitmask & 0xFF)],
            [UInt8(idpSourceId & 0xFF)],
            [UInt8(carbEntry & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Deletes an IDP (opcode 0xAE → 0xAF). 2-byte cargo: idpId + profileIndex. modInsulin.
public struct DeleteIDPRequest: Message {
    public static let props = MessageProps(opCode: 0xAE, size: 2, signed: true, type: .request, characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xAF)
    public var cargo: [UInt8]
    public private(set) var idpId = 0, profileIndex = 0
    public init() { cargo = [] }
    public init(idpId: Int, profileIndex: Int) {
        self.idpId = idpId; self.profileIndex = profileIndex
        self.cargo = [UInt8(idpId & 0xFF), UInt8(profileIndex & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let b = removeSignedRequestHmacBytes(raw); cargo = b
        if b.count >= 2 { idpId = Int(b[0]); profileIndex = Int(b[1]) }
    }
}

/// Renames an IDP (opcode 0xA8 → 0xA9). 19-byte cargo: idpId + profileIndex + 16-char name + 0.
/// modInsulin.
public struct RenameIDPRequest: Message {
    public static let props = MessageProps(opCode: 0xA8, size: 19, signed: true, type: .request, characteristic: .control, modifiesInsulinDelivery: true, responseOpCode: 0xA9)
    public var cargo: [UInt8]
    public private(set) var idpId = 0, profileIndex = 0
    public private(set) var profileName = ""
    public init() { cargo = [] }
    public init(idpId: Int, profileIndex: Int, profileName: String) {
        self.idpId = idpId; self.profileIndex = profileIndex; self.profileName = profileName
        self.cargo = Bytes.combine([UInt8(idpId & 0xFF), UInt8(profileIndex & 0xFF)],
                                   Bytes.writeString(profileName, 16), [0])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets one IDP time-segment's parameters (opcode 0xAA → 0xAB). 17-byte cargo.
public struct SetIDPSegmentRequest: Message {
    public static let props = MessageProps(opCode: 0xAA, size: 17, signed: true, type: .request, characteristic: .control, responseOpCode: 0xAB)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(idpId: Int, profileIndex: Int, segmentIndex: Int, operationId: Int,
                profileStartTime: Int, profileBasalRate: Int, profileCarbRatio: UInt32,
                profileTargetBG: Int, profileISF: Int, idpStatusId: Int) {
        self.cargo = Bytes.combine(
            [UInt8(idpId & 0xFF), UInt8(profileIndex & 0xFF)],
            [UInt8(segmentIndex & 0xFF), UInt8(operationId & 0xFF)],
            Bytes.firstTwoBytesLittleEndian(profileStartTime),
            Bytes.firstTwoBytesLittleEndian(profileBasalRate),
            Bytes.toUint32(profileCarbRatio),
            Bytes.firstTwoBytesLittleEndian(profileTargetBG),
            Bytes.firstTwoBytesLittleEndian(profileISF),
            [UInt8(idpStatusId & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}

/// Sets IDP-level settings — insulin duration, carb entry (opcode 0xAC → 0xAD). 6-byte cargo:
/// idpId + profileIndex + LE uint16 profileInsulinDuration + profileCarbEntry + changeTypeId.
public struct SetIDPSettingsRequest: Message {
    public static let props = MessageProps(opCode: 0xAC, size: 6, signed: true, type: .request, characteristic: .control, responseOpCode: 0xAD)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public init(idpId: Int, profileIndex: Int, profileInsulinDuration: Int, profileCarbEntry: Int, changeTypeId: Int) {
        self.cargo = Bytes.combine([UInt8(idpId & 0xFF), UInt8(profileIndex & 0xFF)],
                                   Bytes.firstTwoBytesLittleEndian(profileInsulinDuration),
                                   [UInt8(profileCarbEntry & 0xFF), UInt8(changeTypeId & 0xFF)])
    }
    public mutating func parse(_ raw: [UInt8]) { cargo = removeSignedRequestHmacBytes(raw) }
}
