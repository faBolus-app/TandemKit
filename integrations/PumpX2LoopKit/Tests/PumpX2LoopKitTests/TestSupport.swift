import Foundation
import HealthKit
import LoopKit
import PumpX2Messages
@testable import PumpX2LoopKit

// MARK: - Fake transport

/// An injectable `TandemPumpConnection` for unit tests — no CoreBluetooth, no hardware. Scripts typed
/// responses per outgoing message and can simulate a mid-transaction failure (timeout / disconnect).
@MainActor
final class FakeTandemConnection: TandemPumpConnection {
    var connectionState: TandemConnectionState = .ready
    /// Returns the response for an outgoing message, or throws a `TandemTransportError` to simulate a
    /// transport failure at that step.
    var onSend: ((any Message) throws -> any Message)?
    private(set) var sent: [any Message] = []
    private(set) var deliveryPolicyEntries = 0

    func send(_ message: any Message, signing: TandemSigning?, allowInsulinDelivery: Bool,
              serialized: Bool, deadline: TimeInterval) async throws -> any Message {
        sent.append(message)
        guard let onSend else { throw TandemTransportError.notReady }
        return try onSend(message)
    }

    func withDeliveryPolicy<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        deliveryPolicyEntries += 1
        return try await body()
    }
}

// MARK: - Response + history cargo builders (little-endian, mirroring the readers)

enum Fixture {
    static func f32le(_ v: Float) -> [UInt8] {
        withUnsafeBytes(of: v.bitPattern.littleEndian) { Array($0) }
    }
    static func put(_ c: inout [UInt8], _ off: Int, _ bytes: [UInt8]) {
        for (i, b) in bytes.enumerated() { c[off + i] = b }
    }

    static func timeSinceReset(currentTime: UInt32 = 1000, sinceReset: UInt32 = 1000) -> TimeSinceResetResponse {
        TimeSinceResetResponse(cargo: Bytes.toUint32(currentTime) + Bytes.toUint32(sinceReset))
    }
    static func bolusPermission(granted: Bool, bolusId: Int) -> BolusPermissionResponse {
        BolusPermissionResponse(cargo: [granted ? 0 : 1] + Bytes.firstTwoBytesLittleEndian(bolusId) + [0, 0, 0])
    }
    static func initiate(accepted: Bool, bolusId: Int) -> InitiateBolusResponse {
        InitiateBolusResponse(cargo: [accepted ? 0 : 1] + Bytes.firstTwoBytesLittleEndian(bolusId) + [0, 0, 0])
    }
    /// deliveredUnits and requestedUnits in units (converted to milliunits on the wire).
    static func lastBolusV2(bolusId: Int, deliveredUnits: Double, requestedUnits: Double) -> LastBolusStatusV2Response {
        var c = [UInt8](repeating: 0, count: 24)
        c[0] = 0
        put(&c, 1, Bytes.firstTwoBytesLittleEndian(bolusId))
        put(&c, 5, Bytes.toUint32(0))                                           // timestamp
        put(&c, 9, Bytes.toUint32(UInt32((deliveredUnits * 1000).rounded())))   // deliveredVolume mU
        put(&c, 20, Bytes.toUint32(UInt32((requestedUnits * 1000).rounded())))  // requestedVolume mU
        return LastBolusStatusV2Response(cargo: c)
    }
    static func currentBasal(currentUnitsPerHour: Double) -> CurrentBasalStatusResponse {
        let mu = UInt32((currentUnitsPerHour * 1000).rounded())
        return CurrentBasalStatusResponse(cargo: Bytes.toUint32(mu) + Bytes.toUint32(mu) + [0])
    }

    static func bolusCompleted(pumpTimeSec: UInt32, sequenceNum: UInt32, bolusId: Int,
                               deliveredUnits: Float, requestedUnits: Float) -> BolusCompletedHistoryLog {
        var c = [UInt8](repeating: 0, count: 26)
        put(&c, 0, Bytes.firstTwoBytesLittleEndian(BolusCompletedHistoryLog.typeId))
        put(&c, 2, Bytes.toUint32(pumpTimeSec))
        put(&c, 6, Bytes.toUint32(sequenceNum))
        put(&c, 10, Bytes.firstTwoBytesLittleEndian(1))       // completionStatusId
        put(&c, 12, Bytes.firstTwoBytesLittleEndian(bolusId))
        put(&c, 14, f32le(0))                                 // iob
        put(&c, 18, f32le(deliveredUnits))
        put(&c, 22, f32le(requestedUnits))
        return BolusCompletedHistoryLog(cargo: c)
    }
    static func pumpingSuspended(pumpTimeSec: UInt32, sequenceNum: UInt32) -> PumpingSuspendedHistoryLog {
        var c = [UInt8](repeating: 0, count: 26)
        put(&c, 0, Bytes.firstTwoBytesLittleEndian(PumpingSuspendedHistoryLog.typeId))
        put(&c, 2, Bytes.toUint32(pumpTimeSec))
        put(&c, 6, Bytes.toUint32(sequenceNum))
        return PumpingSuspendedHistoryLog(cargo: c)
    }
}

// MARK: - Capturing delegate

/// Minimal `PumpManagerDelegate` that records the events the driver reports.
final class CapturingPumpManagerDelegate: PumpManagerDelegate {
    var newEvents: [NewPumpEvent] = []
    var lastReconciliations: [Date?] = []

    // PumpManagerDelegate
    func pumpManager(_ pumpManager: PumpManager, hasNewPumpEvents events: [NewPumpEvent],
                     lastReconciliation: Date?, replacePendingEvents: Bool,
                     completion: @escaping (Error?) -> Void) {
        newEvents.append(contentsOf: events)
        lastReconciliations.append(lastReconciliation)
        completion(nil)
    }
    func pumpManagerBLEHeartbeatDidFire(_ pumpManager: PumpManager) {}
    func pumpManagerMustProvideBLEHeartbeat(_ pumpManager: PumpManager) -> Bool { false }
    func pumpManagerWillDeactivate(_ pumpManager: PumpManager) {}
    func pumpManagerPumpWasReplaced(_ pumpManager: PumpManager) {}
    func pumpManager(_ pumpManager: PumpManager, didUpdatePumpRecordsBasalProfileStartEvents pumpRecordsBasalProfileStartEvents: Bool) {}
    func pumpManager(_ pumpManager: PumpManager, didError error: PumpManagerError) {}
    func pumpManager(_ pumpManager: PumpManager, didReadReservoirValue units: Double, at date: Date,
                     completion: @escaping (Result<(newValue: ReservoirValue, lastValue: ReservoirValue?, areStoredValuesContinuous: Bool), Error>) -> Void) {}
    func pumpManager(_ pumpManager: PumpManager, didAdjustPumpClockBy adjustment: TimeInterval) {}
    func pumpManagerDidUpdateState(_ pumpManager: PumpManager) {}
    func pumpManager(_ pumpManager: PumpManager, didRequestBasalRateScheduleChange basalRateSchedule: BasalRateSchedule, completion: @escaping (Error?) -> Void) {}
    func startDateToFilterNewPumpEvents(for manager: PumpManager) -> Date { .distantPast }
    var detectedSystemTimeOffset: TimeInterval = 0
    var automaticDosingEnabled: Bool = false

    // PumpManagerStatusObserver
    func pumpManager(_ pumpManager: PumpManager, didUpdate status: PumpManagerStatus, oldStatus: PumpManagerStatus) {}

    // DeviceManagerDelegate
    func deviceManager(_ manager: DeviceManager, logEventForDeviceIdentifier deviceIdentifier: String?,
                       type: DeviceLogEntryType, message: String, completion: ((Error?) -> Void)?) {}

    // AlertIssuer
    func issueAlert(_ alert: Alert) {}
    func retractAlert(identifier: Alert.Identifier) {}

    // PersistedAlertStore
    func doesIssuedAlertExist(identifier: Alert.Identifier, completion: @escaping (Swift.Result<Bool, Error>) -> Void) {}
    func lookupAllUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {}
    func lookupAllUnacknowledgedUnretracted(managerIdentifier: String, completion: @escaping (Swift.Result<[PersistedAlert], Error>) -> Void) {}
    func recordRetractedAlert(_ alert: Alert, at date: Date) {}
}
