import Foundation

/// Names for the CGM fields the `cgm` and `snapshot` commands print. The values are pumpX2's enums
/// (`HomeScreenMirrorResponse.CGMAlertIcon` and `CGMTrendIcon`, `CurrentEGVGuiDataResponse.EGVStatus`,
/// `CGMStatusResponse.SessionState`); a value pumpX2 doesn't list prints as `unknown(n)`, never a guess.
public enum BenchCgmNames {
    /// HomeScreenMirror byte 1.
    public static func alertIcon(_ id: Int) -> String {
        let names: [Int: String] = [
            0: "STARTUP_1", 1: "STARTUP_2", 2: "STARTUP_3", 3: "STARTUP_4", 4: "CALIBRATE", 5: "STARTUP_CALIBRATE",
            6: "CHECKMARK_BLOOD_DROP", 7: "ERROR_HIGH_WEDGE", 8: "ERROR_LOW_WEDGE", 11: "REPLACE_SENSOR",
            12: "REPLACE_TRANSMITTER", 13: "OUT_OF_RANGE", 14: "FAILED_SENSOR", 15: "TRIPLE_DASHES", 16: "LOW",
            17: "HIGH", 255: "NO_ERROR"
        ]
        return names[id] ?? "unknown(\(id))"
    }

    /// The alert icon that means the pump shows a number.
    public static let noErrorIcon = 255

    /// HomeScreenMirror byte 0.
    public static func trendIcon(_ id: Int) -> String {
        let names = [
            "NO_ARROW", "ARROW_DOUBLE_UP", "ARROW_UP", "ARROW_UP_RIGHT", "ARROW_FLAT", "ARROW_DOWN_RIGHT", "ARROW_DOWN",
            "ARROW_DOUBLE_DOWN"
        ]
        return names.indices.contains(id) ? names[id] : "unknown(\(id))"
    }

    /// CurrentEGVGuiData byte 6.
    public static func egvStatus(_ id: Int) -> String {
        let names = ["INVALID", "VALID", "LOW", "HIGH", "UNAVAILABLE"]
        return names.indices.contains(id) ? names[id] : "unknown(\(id))"
    }

    /// CGMStatus byte 0.
    public static func sessionState(_ id: Int) -> String {
        let names = ["SESSION_STOPPED", "SESSION_START_PENDING", "SESSION_ACTIVE", "SESSION_STOP_PENDING"]
        return names.indices.contains(id) ? names[id] : "unknown(\(id))"
    }

    /// The case the CGM-icon question is about: the EGV read says there is a reading (VALID, LOW or
    /// HIGH) while the mirror's icon isn't NO_ERROR, so the pump shows a CGM state instead of a number.
    public static func readingDespiteIcon(alertIcon: Int, egvStatus: Int) -> Bool {
        (1...3).contains(egvStatus) && alertIcon != noErrorIcon
    }
}

/// The bolus-calculator snapshot (op 115, 46 bytes), byte by byte. Fields at pumpX2's offsets are
/// named; the bytes pumpX2 doesn't decode (26-36 and 38-45) are printed raw, and `locate` looks in them
/// for the CGM reading and its timestamp. A located offset is a candidate from matching values, not a
/// decode: it holds only once it tracks the EGV read across several readings.
public enum BenchSnapshot {
    public static let size = 46

    public struct Field: Sendable, Equatable {
        public let offset: Int
        public let width: Int
        public let name: String
    }

    /// pumpX2's `BolusCalcDataSnapshotResponse.parse` layout.
    public static let fields: [Field] = [
        Field(offset: 0, width: 1, name: "isUnacked"),
        Field(offset: 1, width: 2, name: "correctionFactor"),
        Field(offset: 3, width: 4, name: "iob (milliunits)"),
        Field(offset: 7, width: 2, name: "cartridgeRemainingInsulin"),
        Field(offset: 9, width: 2, name: "targetBg"),
        Field(offset: 11, width: 2, name: "isf"),
        Field(offset: 13, width: 1, name: "carbEntryEnabled"),
        Field(offset: 14, width: 4, name: "carbRatio (x1000)"),
        Field(offset: 18, width: 2, name: "maxBolusAmount (milliunits)"),
        Field(offset: 20, width: 4, name: "maxBolusHourlyTotal"),
        Field(offset: 24, width: 1, name: "maxBolusEventsExceeded"),
        Field(offset: 25, width: 1, name: "maxIobEventsExceeded"),
        Field(offset: 37, width: 1, name: "isAutopopAllowed")
    ]

    /// The bytes the bench questions are about.
    public static let keyOffsets = [0, 13, 24, 25, 37]

    /// Offsets with no pumpX2 field.
    public static var undecodedOffsets: [Int] {
        var covered = Set<Int>()
        for f in fields { covered.formUnion(f.offset..<(f.offset + f.width)) }
        return (0..<size).filter { !covered.contains($0) }
    }

    /// One line per pumpX2 field, then the undecoded bytes as raw runs.
    public static func lines(_ cargo: [UInt8]) -> [String] {
        guard cargo.count >= size else { return ["snapshot is \(cargo.count) bytes, expected \(size)"] }
        var out: [String] = []
        for f in fields {
            let bytes = Array(cargo[f.offset..<(f.offset + f.width)])
            let value = littleEndian(bytes)
            let mark = keyOffsets.contains(f.offset) ? " <-" : ""
            out.append("[\(f.offset)\(f.width > 1 ? "-\(f.offset + f.width - 1)" : "")] \(f.name) = \(value)\(mark)")
        }
        for run in runs(undecodedOffsets) {
            let hex = run.map { String(format: "%02x", cargo[$0]) }.joined(separator: " ")
            out.append("[\(run.first!)-\(run.last!)] not decoded by pumpX2: \(hex)")
        }
        return out
    }

    /// Every offset, inside the bytes pumpX2 doesn't decode, where the snapshot holds `reading` as a
    /// uint16 LE or `timestamp` as a uint32 LE. (A decoded field that happens to hold the same number,
    /// a target BG of 120 against a reading of 120, is not a candidate.)
    public static func locate(reading: Int, timestamp: UInt32, in cargo: [UInt8]) -> (reading: [Int], timestamp: [Int])
    {
        let free = Set(undecodedOffsets)
        func candidates(width: Int, matches: (Int) -> Bool) -> [Int] {
            guard cargo.count >= width else { return [] }
            return (0...(cargo.count - width)).filter { i in (i..<(i + width)).allSatisfy(free.contains) && matches(i) }
        }
        let readingAt =
            reading > 0 ? candidates(width: 2) { Int(littleEndian(Array(cargo[$0..<($0 + 2)]))) == reading } : []
        let timestampAt =
            timestamp > 0
            ? candidates(width: 4) { UInt32(littleEndian(Array(cargo[$0..<($0 + 4)]))) == timestamp } : []
        return (readingAt, timestampAt)
    }

    /// The offsets found in every sample: what survives as a candidate.
    public static func consistent(_ samples: [[Int]]) -> [Int] {
        guard var common = samples.first.map(Set.init) else { return [] }
        for s in samples.dropFirst() { common.formIntersection(s) }
        return common.sorted()
    }

    static func littleEndian(_ bytes: [UInt8]) -> UInt64 {
        bytes.enumerated().reduce(0) { $0 | UInt64($1.element) << UInt64(8 * $1.offset) }
    }

    static func runs(_ offsets: [Int]) -> [[Int]] {
        var out: [[Int]] = []
        for o in offsets {
            if let last = out.last?.last, last + 1 == o {
                out[out.count - 1].append(o)
            } else {
                out.append([o])
            }
        }
        return out
    }
}

/// HomeScreenMirror (op 57, 9 bytes) byte by byte, with pumpX2's icon enums
/// (`HomeScreenMirrorResponse`): what the pump's home screen shows, for the suspended-pump,
/// Control-IQ-state and status-icon questions as well as the CGM ones.
public enum BenchMirror {
    public static let size = 9

    static func named(_ id: Int, _ names: [Int: String]) -> String { names[id] ?? "unknown(\(id))" }

    public static func statusIcon0(_ id: Int) -> String {
        named(id, [0: "AAM", 1: "CGM_TRANSMITTER", 4: "CGM_TRANSMITTER_OOR", 200: "HIDE_ICON"])
    }

    public static func statusIcon1(_ id: Int) -> String { named(id, [0: "AAM", 1: "BLOOD_DROP", 200: "HIDE_ICON"]) }

    public static func bolusIcon(_ id: Int) -> String {
        named(
            id,
            [
                0: "BOLUS", 1: "AUTO_BOLUS", 2: "BLACK_LOCK_SECURITY_PIN", 3: "GREY_LOCK_SECURITY_PIN_CGM_GRAPH_ACTIVE",
                200: "HIDE_ICON"
            ])
    }

    public static func basalIcon(_ id: Int) -> String {
        named(
            id,
            [
                0: "BASAL", 1: "ZERO_BASAL", 2: "TEMP_RATE", 3: "ZERO_TEMP_RATE", 4: "SUSPEND",
                5: "HYPO_SUSPEND_BASAL_IQ",
                6: "INCREASE_BASAL", 7: "ATTENUATED_BASAL", 200: "HIDE"
            ])
    }

    public static func apControlState(_ id: Int) -> String {
        named(
            id,
            [
                0: "STATE_GRAY", 1: "STATE_GRAY_RED_BIQ_CIQ_BASAL_SUSPENDED", 2: "STATE_GRAY_BLUE_CIQ_INCREASE_BASAL",
                3: "STATE_GRAY_ORANGE_CIQ_ATTENUATION_BASAL", 200: "HIDE_ICON"
            ])
    }

    /// One line per byte, at pumpX2's offsets.
    public static func lines(_ cargo: [UInt8]) -> [String] {
        guard cargo.count >= size else { return ["mirror is \(cargo.count) bytes, expected \(size)"] }
        let b = cargo.map(Int.init)
        return [
            "[0] trend icon \(b[0]) \(BenchCgmNames.trendIcon(b[0]))",
            "[1] CGM alert icon \(b[1]) \(BenchCgmNames.alertIcon(b[1]))",
            "[2] status icon 0 \(b[2]) \(statusIcon0(b[2]))",
            "[3] status icon 1 \(b[3]) \(statusIcon1(b[3]))",
            "[4] bolus icon \(b[4]) \(bolusIcon(b[4]))",
            "[5] basal icon \(b[5]) \(basalIcon(b[5]))",
            "[6] Control-IQ state \(b[6]) \(apControlState(b[6]))",
            "[7] remaining-insulin plus icon \(b[7] != 0)",
            "[8] cgmDisplayData \(b[8] != 0)"
        ]
    }
}
