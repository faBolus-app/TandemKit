import Foundation

/// Empty-cargo status-read requests on the CURRENT_STATUS characteristic. These are the
/// read-only messages the host/harness sends to poll pump state; each has no parameters and
/// a paired response at `opCode + 1`. Ports of the corresponding
/// `request/currentStatus/*Request` classes.
///
/// Byte-parity with the oracle is covered in OracleParityTests.
public protocol EmptyCurrentStatusRequest: Message {
    init(emptyCargo: Void)
}

public extension EmptyCurrentStatusRequest {
    init() { self.init(emptyCargo: ()) }
    mutating func parse(_ raw: [UInt8]) {
        // Request messages are only serialized; empty cargo is expected.
        if raw.isEmpty { return }
        precondition(raw.count == Self.props.size)
        cargo = Bytes.dropFirst(raw, 3)
    }
}

/// Generates an empty-cargo CURRENT_STATUS request type. `op` is the request opcode; the
/// response opcode is `op &+ 1` by the even/odd convention.
private func statusProps(_ op: UInt8) -> MessageProps {
    MessageProps(opCode: op, size: 0, type: .request,
                 characteristic: .currentStatus, responseOpCode: op &+ 1)
}

// Each type is a thin struct: opcode + empty cargo. `init(emptyCargo:)` satisfies the
// protocol extension's `init()`.
public struct ControlIQIOBRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(108)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct NonControlIQIOBRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(38)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct InsulinStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(36)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CurrentBatteryV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x90) // -112
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CurrentBasalStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(40)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct HomeScreenMirrorRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(56)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct PumpVersionRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(84)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct TimeSinceResetRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(54)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CurrentBolusStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(44)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct LastBolusStatusV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xA4) // -92
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct ControlIQInfoV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xB2) // -78
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct LastBGRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(50)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CurrentEgvGuiDataV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xC0) // -64; response 0xC1 (193). V2 (newer firmware)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct PumpGlobalsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(86)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct PumpSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(82)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct BolusCalcDataSnapshotRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(114)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct AlertStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(68)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct AlarmStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(70)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct MalfunctionStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(118)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}

// A1 read batch: profile overview + safety limits (all empty-cargo CURRENT_STATUS reads).
public struct ProfileStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(62)               // response 63
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CurrentActiveIdpValuesRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x96)             // -106; response 0x97 (151)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct GlobalMaxBolusSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x8C)             // -116; response 0x8D (141)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct BasalLimitSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x8A)             // -118; response 0x8B (139)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct ControlIQInfoV1Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(104)              // response 105
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct PumpFeaturesV1Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(78)               // response 79
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct LoadStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(20)               // response 21
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct ExtendedBolusStatusV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xB6)             // -74; response 0xB7 (183)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CGMStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(80)               // response 81
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CgmStatusV2Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xBE)             // -66; response 0xBF (191)
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}
public struct CGMHardwareInfoRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(96)               // response 97
    public var cargo: [UInt8] = []
    public init(emptyCargo: Void = ()) { self.cargo = [] }
}

// Remaining empty-cargo reads (software info, Basal-IQ, CGM alert-settings reads, misc).
public struct CurrentBatteryV1Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(52); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct CurrentEGVGuiDataRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(34); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct ExtendedBolusStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(46); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct LastBolusStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(48); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct LastBolusStatusV3Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xBA); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct TempRateRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(42); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct TempRateStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(30); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct RemindersRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(88); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct ControlIQSleepScheduleRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(106); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct BasalIQStatusRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(112); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct BasalIQSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(98); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct BasalIQAlertInfoRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(102); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct CGMGlucoseAlertSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(90); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct CGMRateAlertSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(92); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct CGMOORAlertSettingsRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(94); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct BleSoftwareInfoRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x88); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct GetG6TransmitterHardwareInfoRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xC4); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct GetSavedG7PairingCodeRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(116); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct HighestAamRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(120); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct LocalizationRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xA6); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct PumpVersionBRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0x84); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct SecretMenuRequest: EmptyCurrentStatusRequest {
    public static let props = statusProps(0xBC); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
public struct UnknownMobiOpcode110Request: EmptyCurrentStatusRequest {
    public static let props = statusProps(110); public var cargo: [UInt8] = []; public init(emptyCargo: Void = ()) { cargo = [] }
}
