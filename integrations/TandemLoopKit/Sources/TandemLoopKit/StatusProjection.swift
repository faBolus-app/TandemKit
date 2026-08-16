import Foundation
import HealthKit
import LoopKit

/// Transient, in-memory command engagement — drives the transitional `bolusState`/`basalDeliveryState`
/// cases while a command is being issued. Not persisted (a relaunch is never mid-command).
public enum BolusEngageState: Equatable { case stable, engaging, canceling }
public enum BasalEngageState: Equatable { case stable, suspending, resuming, engagingTempBasal, cancelingTempBasal }

/// Projects `TandemPumpManagerState` + engagement into a LoopKit `PumpManagerStatus`. Pure and
/// synchronous so it can be read from any thread (under the manager's lock) and unit-tested directly.
public enum TandemStatusProjection {

    public static func device(serial: String?, firmwareVersion: String?) -> HKDevice {
        HKDevice(
            name: "Tandem",
            manufacturer: "Tandem Diabetes Care",
            model: "t:slim X2 / Mobi",
            hardwareVersion: nil,
            firmwareVersion: firmwareVersion,
            softwareVersion: nil,
            localIdentifier: serial,
            udiDeviceIdentifier: nil
        )
    }

    public static func status(from state: TandemPumpManagerState,
                              bolusEngage: BolusEngageState,
                              basalEngage: BasalEngageState,
                              now: Date) -> PumpManagerStatus {
        PumpManagerStatus(
            timeZone: state.timeZone,
            device: device(serial: state.pumpSerial, firmwareVersion: nil),
            pumpBatteryChargeRemaining: state.batteryPercent.map { Double($0) / 100.0 },
            basalDeliveryState: basalDeliveryState(from: state, engage: basalEngage, now: now),
            bolusState: bolusState(from: state, engage: bolusEngage),
            insulinType: nil, // the pump does not report insulin brand
            deliveryIsUncertain: state.deliveryUncertain
        )
    }

    static func bolusState(from state: TandemPumpManagerState, engage: BolusEngageState) -> PumpManagerStatus.BolusState {
        switch engage {
        case .engaging: return .initiating
        case .canceling: return .canceling
        case .stable:
            if let d = state.pendingDose, d.doseType == .bolus, d.isMutable() {
                return .inProgress(DoseEntry(d))
            }
            return .noBolus
        }
    }

    static func basalDeliveryState(from state: TandemPumpManagerState, engage: BasalEngageState, now: Date) -> PumpManagerStatus.BasalDeliveryState {
        switch engage {
        case .suspending: return .suspending
        case .resuming: return .resuming
        case .engagingTempBasal: return .initiatingTempBasal
        case .cancelingTempBasal: return .cancelingTempBasal
        case .stable:
            if let d = state.pendingDose, d.doseType == .tempBasal, d.isMutable() {
                return .tempBasal(DoseEntry(d))
            }
            let at = state.lastReconciliation ?? now
            return state.suspended ? .suspended(at) : .active(at)
        }
    }
}
