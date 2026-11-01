import Testing
@testable import TandemMessages

/// Each notification id's upstream identifier matches the oracle: alerts and alarms through the
/// status responses (the oracle lists the identifier of every set bit), CGM alerts through the CGM
/// alert history log (which carries `CGMAlert.fromId(alertId)`).
@Suite(.enabled(if: OracleRunner.isAvailable)) struct NotificationIdentifierParityTests {
    /// The identifiers the oracle prints for a status response with only `bit` set.
    private func oracleIdentifiers(opCode: UInt8, bit: Int) throws -> [String] {
        let cargo = Bytes.toUint64(UInt64(1) << UInt64(bit))
        let body: [UInt8] = [opCode, 3, UInt8(cargo.count)] + cargo
        let packet = [0, 3] + body + Bytes.calculateCRC16(body)
        let (out, _) = try OracleServer.shared.call(["parse", Hex.encode(packet)])
        let line = try #require(out.split(separator: "\n").last(where: { $0.contains("[") }))
        let list = try #require(line.range(of: "=["), "no list in \(line)")
        let end = try #require(line[list.upperBound...].firstIndex(of: "]"))
        let names = line[list.upperBound..<end]
        return names.isEmpty ? [] : names.components(separatedBy: ", ")
    }

    @Test func alertIdentifiersMatchOracle() throws {
        for bit in 0..<64 {
            let oracle = try oracleIdentifiers(opCode: AlertStatusResponse.props.opCode, bit: bit)
            #expect(oracle == AlertStatusResponse.identifiers[bit].map { [$0.constant] } ?? [], "alert \(bit)")
        }
    }

    @Test func alarmIdentifiersMatchOracle() throws {
        for bit in 0..<64 {
            let oracle = try oracleIdentifiers(opCode: AlarmStatusResponse.props.opCode, bit: bit)
            #expect(oracle == AlarmStatusResponse.identifiers[bit].map { [$0.constant] } ?? [], "alarm \(bit)")
        }
    }

    @Test func cgmAlertIdentifiersMatchOracle() throws {
        for id in 0..<64 {
            var rec = [UInt8](repeating: 0, count: 26)
            rec[0] = UInt8(CgmAlertActivatedHistoryLog.typeId)
            rec[10] = UInt8(id)
            let oracle = try OracleRunner.parseHistoryLog(hex: Hex.encode(rec))
            let fields = HistoryLogFieldParityTests.fields(fromToString: oracle.description)
            let expected = CGMAlertStatusResponse.identifiers[id]?.constant ?? "<null>"  // how ToStringBuilder prints null
            #expect(fields["alert"] == expected, "CGM alert \(id)")
        }
    }

    /// Decoded notifications carry the identifier; the display title is unchanged.
    @Test func decodedNotificationCarriesItsIdentifier() {
        let n = AlarmStatusResponse(cargo: Bytes.toUint64(1 << 5)).notifications
        #expect(n.count == 1)
        #expect(n.first?.identifier == NotificationIdentifier("CARTRIDGE_ALARM_P2", "Alarm_P2"))
    }
}
