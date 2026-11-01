import Foundation
import Testing
@testable import TandemMessages

/// Field-level decode parity for every registered history-log type: random records go to the
/// oracle (`cliparser historylog`, whose output lists every field of the decoded Java object) and to
/// `HistoryLogParser`, and every Swift stored property must equal the Java field of the same name.
/// This is what catches an offset or width that differs from upstream, which a class-name check on
/// a zeroed record can't.
@Suite(.enabled(if: OracleRunner.isAvailable)) struct HistoryLogFieldParityTests {
    static let recordsPerType = 32

    static var typeIds: [Int] { HistoryLogParser.factories.keys.sorted() }

    @Test(arguments: typeIds)
    func fieldsMatchOracle(typeId: Int) throws {
        var rng = SplitMix64(seed: UInt64(typeId))
        var compared = 0
        for n in 0..<Self.recordsPerType {
            var rec = (0..<26).map { _ in UInt8(truncatingIfNeeded: rng.next()) }
            // Header: the typeId with a random high nibble (the parser masks to 12 bits).
            rec[0] = UInt8(typeId & 0xFF)
            rec[1] = UInt8((typeId >> 8) & 0x0F) | (rec[1] & 0xF0)
            // Half the records keep small values in every byte so enum-like fields hit real values.
            if n % 2 == 0 { for i in 10..<26 { rec[i] &= 0x07 } }
            // Keep the delimiters of Java's toString, and the tab and newline that end the oracle's
            // line, out of string fields, so every field parses.
            for i in 10..<26 where Array(",=[]{}\t\n\r".utf8).contains(rec[i]) { rec[i] = 0x41 }
            let oracle = try OracleRunner.parseHistoryLog(hex: Hex.encode(rec))
            let javaFields = Self.fields(fromToString: oracle.description)
            let event = HistoryLogParser.parse(record: rec)
            #expect(oracle.className == String(describing: type(of: event)))
            // Every Java field is ported, except upstream's enum views of a raw field Swift keeps.
            let swiftNames = Set(Mirror(reflecting: event).children.compactMap(\.label))
            let javaOnly = Set(javaFields.keys).subtracting(swiftNames)
            let allowed = Self.upstreamEnumViews[oracle.className] ?? []
            #expect(javaOnly.isSubset(of: allowed), "\(oracle.className) lacks upstream fields \(javaOnly.subtracting(allowed).sorted())")
            for child in Mirror(reflecting: event).children {
                guard let name = child.label, name != "cargo" else { continue }
                guard let java = javaFields[name] else {
                    Issue.record("\(type(of: event)).\(name) has no Java field of that name (java: \(javaFields.keys.sorted()))")
                    continue
                }
                if !Self.equal(swift: child.value, java: java) {
                    Issue.record("\(type(of: event)).\(name): swift=\(child.value) java=\(java) record=\(Hex.encode(rec))")
                }
                compared += 1
            }
        }
        #expect(compared > 0)
    }

    /// Java fields that are an enum decoded from a raw field Swift already has (`alertId`,
    /// `currentPcmId`, …). The display meaning of those enums is left to the app.
    static let upstreamEnumViews: [String: Set<String>] = [
        "BolexCompletedHistoryLog": ["completionStatus"],
        "CgmAlertAckDexHistoryLog": ["alert"],
        "CgmAlertAckHistoryLog": ["alert"],
        "CgmAlertActivatedDexHistoryLog": ["alert"],
        "CgmAlertActivatedFsl2HistoryLog": ["alert"],
        "CgmAlertActivatedHistoryLog": ["alert"],
        "CgmAlertClearedDexHistoryLog": ["alert"],
        "CgmAlertClearedFsl2HistoryLog": ["alert"],
        "CgmAlertClearedHistoryLog": ["alert"],
        "ControlIQPcmChangeHistoryLog": ["currentPcm", "previousPcm"],
        "DexcomG6CGMHistoryLog": ["cgmDataTypes", "egvInfo", "glucoseValueStatus"],
        "DexcomG7CGMHistoryLog": ["algorithmState", "cgmDataType", "egvInfo", "glucoseValueStatus"]
    ]

    /// `Name[a=1,b={1,2},c=X]` -> ["a": "1", "b": "{1,2}", "c": "X"], splitting only at top level.
    static func fields(fromToString s: String) -> [String: String] {
        guard let open = s.firstIndex(of: "["), s.last == "]" else { return [:] }
        let body = s[s.index(after: open)..<s.index(before: s.endIndex)]
        var out: [String: String] = [:]
        var depth = 0
        var current = ""
        func flush() {
            if let eq = current.firstIndex(of: "=") {
                out[String(current[..<eq])] = String(current[current.index(after: eq)...])
            }
            current = ""
        }
        for ch in body {
            switch ch {
            case "{", "[": depth += 1
            case "}", "]": depth -= 1
            case "," where depth == 0:
                flush()
                continue
            default: break
            }
            current.append(ch)
        }
        flush()
        return out
    }

    /// Upstream reads many one-byte fields as a signed Java `byte` (`raw[n]` with no `& 0xFF`); the
    /// Swift port reads the same byte unsigned. Those are the same bits, so a Java value in -128...-1
    /// matches a Swift value 256 higher. Nothing else is allowed to differ.
    static func equal(swift: Any, java: String) -> Bool {
        switch swift {
        case let v as Bool: return String(v) == java
        case let v as Float: return Float(java).map { $0 == v || ($0.isNaN && v.isNaN) } ?? false
        case let v as Double: return Double(java).map { $0 == v || ($0.isNaN && v.isNaN) } ?? false
        case let v as any BinaryInteger:
            guard let j = Int64(java) else { return false }
            return Int64(v) == j || ((-128)...(-1) ~= j && Int64(v) == j + 256)
        case let v as [UInt8]:
            // Java prints a byte[] as signed values: {1,-2,…}.
            let java = java.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
            let values = java.isEmpty ? [] : java.split(separator: ",").compactMap { Int8($0) }
            return values.map { UInt8(bitPattern: $0) } == v
        default: return String(describing: swift) == java
        }
    }
}

struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
