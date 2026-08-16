import Foundation

/// CGM-session control commands (A2). All are signed CONTROL-characteristic writes but do **not**
/// dispense/stop insulin, so `modifiesInsulinDelivery` stays false. Ports of
/// `request/control/{StartDexcomG6SensorSession,StopDexcomCGMSensorSession,SetSensorType,
/// SetDexcomG7PairingCode}Request`. Byte-parity covered in OracleParityTests.

/// Starts a Dexcom G6 sensor session with the 4-digit `sensorCode` (opcode 0xB2 → 0xB3).
public struct StartDexcomG6SensorSessionRequest: Message {
    public static let props = MessageProps(
        opCode: 0xB2, size: 2, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xB3)
    public var cargo: [UInt8]
    public private(set) var sensorCode: Int = 0
    public init() { cargo = [] }
    public init(sensorCode: Int) {
        self.sensorCode = sensorCode
        self.cargo = Bytes.firstTwoBytesLittleEndian(sensorCode)
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 2 { sensorCode = Bytes.readShort(body, 0) }
    }
}

/// Stops the active Dexcom CGM sensor session (opcode 0xB4 → 0xB5). Empty cargo.
public struct StopDexcomCGMSensorSessionRequest: Message {
    public static let props = MessageProps(
        opCode: 0xB4, size: 0, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xB5)
    public var cargo: [UInt8]
    public init() { cargo = [] }
    public mutating func parse(_ raw: [UInt8]) { cargo = [] }
}

/// Sets the CGM sensor type (opcode 0xC0 → 0xC1). 1-byte cargo. `cgmSensorType` per upstream
/// CgmSensorType enum (e.g. 0 = none, G6/G7/FSL variants).
public struct SetSensorTypeRequest: Message {
    public static let props = MessageProps(
        opCode: 0xC0, size: 1, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xC1)
    public var cargo: [UInt8]
    public private(set) var cgmSensorType: Int = 0
    public init() { cargo = [] }
    public init(cgmSensorType: Int) {
        self.cgmSensorType = cgmSensorType
        self.cargo = [UInt8(cgmSensorType & 0xFF)]
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if !body.isEmpty { cgmSensorType = Int(body[0]) }
    }
}

/// Sets the Dexcom G7 pairing code (opcode 0xFC → 0xFD). 8-byte cargo: LE uint16 code + 6 zero pad.
public struct SetDexcomG7PairingCodeRequest: Message {
    public static let props = MessageProps(
        opCode: 0xFC, size: 8, signed: true, type: .request,
        characteristic: .control, responseOpCode: 0xFD)
    public var cargo: [UInt8]
    public private(set) var pairingCode: Int = 0
    public init() { cargo = [] }
    public init(pairingCode: Int) {
        self.pairingCode = pairingCode
        self.cargo = Bytes.combine(Bytes.firstTwoBytesLittleEndian(pairingCode), [UInt8](repeating: 0, count: 6))
    }
    public mutating func parse(_ raw: [UInt8]) {
        let body = removeSignedRequestHmacBytes(raw)
        cargo = body
        if body.count >= 2 { pairingCode = Bytes.readShort(body, 0) }
    }
}
