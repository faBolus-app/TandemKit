import Foundation
import TandemMessages

/// The pump's feature sets, as the `features` diagnostic reads them.
///
/// From API 2.5 the pump answers PumpFeaturesV2 (0xA0 → 0xA1) one set at a time, chosen by a one-byte
/// index; below 2.5 there is only the legacy PumpFeaturesV1 (78 → 79), whose 64-bit mask uses the main
/// set's bit positions. Every name here is pumpX2's (`PumpFeaturesV2Response` and
/// `PumpFeaturesV1Response.PumpFeatureType`); a set bit with no pumpX2 name is printed by position only.
/// Whether a t:slim sets any given bit, and what each one gates on the pump, is what the bench records.
public enum BenchFeatureSet: Int, CaseIterable, Sendable {
    case main = 0
    case controlIQPro = 1
    case control = 2
    case controlIQ = 3
    case dexcom = 4
    case abbott = 5
    case secondary = 6

    /// pumpX2's `SupportedFeatureIndex` name.
    public var name: String {
        switch self {
        case .main: return "MAIN_FEATURES"
        case .controlIQPro: return "CONTROL_IQ_PRO_FEATURES"
        case .control: return "CONTROL_FEATURES"
        case .controlIQ: return "CONTROL_IQ_FEATURES"
        case .dexcom: return "DEXCOM_FEATURES"
        case .abbott: return "ABBOTT_FEATURES"
        case .secondary: return "SECONDARY_FEATURES"
        }
    }

    /// The order the diagnostic reads them in by default: the sets the remote-bolus and CGM decisions
    /// need first, because on an API 2.5 pump a set the firmware lacks can draw an op-77 and cost the
    /// link (and the first op-77 a probe draws ends probing for that connection).
    public static let defaultOrder: [BenchFeatureSet] = [.main, .control, .dexcom]
    /// The rest, read only when asked (`features all`), after the default ones.
    public static let extraOrder: [BenchFeatureSet] = [.abbott, .secondary, .controlIQ, .controlIQPro]

    /// Bit position → pumpX2's name for this set.
    public var bitNames: [Int: String] {
        switch self {
        case .main: return BenchFeatureSet.mainBits
        case .controlIQPro:
            return [
                0: "BLE_CONTROL", 1: "GUI_CHANGES", 2: "RANGE_CHANGES", 3: "NVM_PARAM", 4: "EXTENDED_BOLUS_DURATION",
                5: "AUTO_BOLUS"
            ]
        case .control:
            return [
                0: "CHANGE_CARTRIDGE_CONTROL", 1: "BASAL_DELIVERY_CONTROL", 2: "STANDARD_BOLUS_CONTROL",
                3: "EXTENDED_BOLUS_CONTROL", 4: "TEMP_RATE_CONTROL", 5: "CGM_CONTROL", 6: "AAM_CONTROL",
                7: "SHELF_MODE_CONTROL", 8: "IDP_CONTROL", 9: "LED_PATTERN_CONTROL", 10: "UNREGISTER_CONTROL",
                11: "PUMP_TIME_CONTROL", 12: "PLGS_CONTROL", 13: "TZ_CONTROL", 14: "REMINDER_SETTINGS_CONTROL",
                15: "ALERT_SETTINGS_CONTROL", 16: "ANNUM_CONTROL", 17: "AAM_NOTIFY_ME_ON_CONTROL",
                18: "PUMP_GLOBAL_SETTINGS_CONTROL", 19: "FACTORY_CONFIG_CONTROL", 20: "SNOOZE_SETTINGS_CONTROL",
                21: "UPDATED_SETTINGS_QE_CONTROL", 22: "FIND_MY_PUMP_CONTROL", 23: "BOLUS_OVERFLOW_CONTROL",
                24: "PREFLIGHT_CONTROL", 25: "USER_INTERACTION_CONTROL", 26: "BLOOD_GLUCOSE_ENTRY_CONTROL",
                27: "HLOG_CREATOR_CONTROL", 28: "FEATURE_MANAGEMENT", 29: "MOBI_RESEARCH_PUMP",
                30: "TIPS_CONTROL_GENERIC_TEST"
            ]
        case .controlIQ:
            return [
                0: "TIMED_EXERCISE", 8: "CONTROL_IQ_VERSION_ONE_FIVE", 9: "TEMP_RATE_ENABLED",
                11: "EXTENDED_BOLUS_ENABLED"
            ]
        case .dexcom:
            return [0: "G5_CGM", 1: "G6_CGM", 2: "G7_CGM", 3: "AUTO_CAL", 4: "DISABLE_GRAPH_SMOOTHING"]
        case .abbott:
            return [0: "IS_FSL2"]
        case .secondary:
            return [0: "BASELINE_PROFILES", 1: "MULTI_CGM", 2: "BLE_TDU"]
        }
    }

    /// The main set's names, shared by PumpFeaturesV1's 64-bit mask.
    public static let mainBits: [Int: String] = [
        0: "DEXCOM_G5_SUPPORTED", 1: "DEXCOM_G6_SUPPORTED", 2: "BASAL_IQ_SUPPORTED", 10: "CONTROL_IQ_SUPPORTED",
        16: "WOMBAT_SUPPORTED", 18: "BASAL_LIMIT_SUPPORTED", 23: "CONTROL_IQ_PRO_SUPPORTED", 25: "AUTO_POP_SUPPORTED",
        28: "BLE_PUMP_CONTROL_SUPPORTED", 29: "PUMP_SETTINGS_IN_IDP_GUI_SUPPORTED"
    ]

    /// Main bit 28: the remote-control bit, the one a remote bolus is to be gated on.
    public static let blePumpControlBit = 28
    /// Main bit 10: Control-IQ support, which picks the IOB read.
    public static let controlIQBit = 10
}

/// One set bit, named when pumpX2 names it.
public struct BenchFeatureBit: Sendable, Equatable {
    public let position: Int
    public let name: String?
}

/// A decoded feature reply.
public struct BenchFeatureReport: Sendable, Equatable {
    public let set: BenchFeatureSet
    public let bitmask: UInt64
    public let bits: [BenchFeatureBit]

    public init(set: BenchFeatureSet, bitmask: UInt64) {
        self.set = set
        self.bitmask = bitmask
        let names = set.bitNames
        bits = (0..<64).filter { bitmask & (UInt64(1) << UInt64($0)) != 0 }
            .map { BenchFeatureBit(position: $0, name: names[$0]) }
    }

    /// A PumpFeaturesV2 reply, decoded by the library, for the set it names; nil when the pump echoed an
    /// index pumpX2 doesn't name.
    public init?(_ reply: PumpFeaturesV2Response) {
        guard let set = BenchFeatureSet(rawValue: reply.supportedFeatureIndexId) else { return nil }
        self.init(set: set, bitmask: UInt64(UInt32(truncatingIfNeeded: reply.pumpFeaturesBitmask)))
    }

    /// The set bits of a mask from an index with no names: `bit 7`, one per line.
    public static func positionLines(_ bitmask: UInt64) -> [String] {
        (0..<64).filter { bitmask & (UInt64(1) << UInt64($0)) != 0 }.map { "bit \($0)" }
    }

    public func isSet(_ position: Int) -> Bool { bitmask & (UInt64(1) << UInt64(position)) != 0 }

    /// The set bits, one per line: `bit 28  BLE_PUMP_CONTROL_SUPPORTED`, or `bit 7  (no pumpX2 name)`.
    public var lines: [String] {
        if bits.isEmpty { return ["no bits set"] }
        return bits.map { "bit \($0.position)  \($0.name ?? "(no pumpX2 name)")" }
    }

    /// The two bits the remote-bolus gate and the choice of IOB read rest on, stated whether set or clear. Only for the main set
    /// (from PumpFeaturesV2 index 0, or PumpFeaturesV1 below API 2.5).
    public var callouts: [String] {
        guard set == .main else {
            if set == .control {
                return [
                    "note: control-set bit 28 is FEATURE_MANAGEMENT (\(isSet(28) ? "set" : "clear")); "
                        + "the remote-control bit is main-set bit 28"
                ]
            }
            return []
        }
        let control = BenchFeatureSet.blePumpControlBit
        let ciq = BenchFeatureSet.controlIQBit
        return [
            "MAIN bit \(control) BLE_PUMP_CONTROL_SUPPORTED: \(isSet(control) ? "SET" : "CLEAR")",
            "MAIN bit \(ciq) CONTROL_IQ_SUPPORTED: \(isSet(ciq) ? "SET" : "CLEAR")"
        ]
    }
}
