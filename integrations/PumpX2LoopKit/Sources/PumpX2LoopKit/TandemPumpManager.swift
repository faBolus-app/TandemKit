import Foundation
import HealthKit
import LoopKit
import PumpX2Messages

/// A LoopKit `PumpManager` for Tandem pumps, built on PumpX2Kit.
///
/// Follows the LoopKit-ecosystem shape (mirroring OmniBLE): the class declares only `DeviceManager`;
/// `PumpManager` conformance is added in an extension. Mutable state is guarded by a lock so the
/// synchronous protocol getters (`status`, `rawState`, `isOnboarded`) are safe to read from any thread,
/// while transport work is driven through the `@MainActor` `TandemPumpConnection` seam.
///
/// UNVERIFIED — reverse-engineered protocol; NOT for real insulin. The pump is the sole authority on
/// delivered insulin: every reported delivered amount comes from the pump's own record.
public final class TandemPumpManager: DeviceManager {

    // MARK: Identity

    public static let pluginIdentifier = "TandemPumpX2"
    public let localizedTitle = "Tandem (PumpX2Kit)"

    // MARK: Transport + state

    /// Optional: a raw-state restore has no live transport yet (the host wires it separately), so it is
    /// `nil` there and every delivery path fail-closes until a connection is present.
    let connection: TandemPumpConnection?
    private let lock = NSRecursiveLock()
    // Internal (not private) so the delivery extension in Delivery.swift can mutate it — but ONLY ever
    // inside a `mutate { }` closure, which holds `lock`. Never touch it outside `mutate`/`statusLocked`.
    var lockedState: TandemPumpManagerState
    private var bolusEngage: BolusEngageState = .stable
    private var basalEngage: BasalEngageState = .stable

    private final class ObserverBox {
        weak var observer: PumpManagerStatusObserver?
        let queue: DispatchQueue
        init(_ observer: PumpManagerStatusObserver, _ queue: DispatchQueue) { self.observer = observer; self.queue = queue }
    }
    private var observerBoxes: [ObserverBox] = []
    private weak var _delegate: PumpManagerDelegate?

    public var delegateQueue: DispatchQueue!

    public var pumpManagerDelegate: PumpManagerDelegate? {
        get { lock.lock(); defer { lock.unlock() }; return _delegate }
        set { lock.lock(); _delegate = newValue; lock.unlock() }
    }

    /// Designated init from an in-memory state + a connection (the seam the tests inject a fake into).
    public init(state: TandemPumpManagerState, connection: TandemPumpConnection?) {
        self.lockedState = state
        self.connection = connection
        PumpX2LoopKitNotice.logOnce()
    }

    // MARK: DeviceManager

    public required convenience init?(rawState: RawStateValue) {
        guard let state = TandemPumpManagerState(rawValue: rawState) else { return nil }
        // A raw-state restore has no live connection yet; the host wires transport separately. Until
        // then the manager reports status from persisted state and refuses delivery (fail-closed).
        self.init(state: state, connection: nil)
    }

    public var rawState: RawStateValue {
        lock.lock(); defer { lock.unlock() }
        return lockedState.rawValue
    }

    public var isOnboarded: Bool {
        lock.lock(); defer { lock.unlock() }
        return lockedState.isOnboarded
    }

    public var debugDescription: String {
        lock.lock(); defer { lock.unlock() }
        return """
        ## TandemPumpManager
        * onboarded: \(lockedState.isOnboarded)
        * serial: \(lockedState.pumpSerial ?? "nil")
        * suspended: \(lockedState.suspended)
        * pendingDose: \(String(describing: lockedState.pendingDose))
        * deliveryUncertain: \(lockedState.deliveryUncertain)
        * hasConnection: \(connection != nil)
        """
    }

    // MARK: AlertResponder / AlertSoundVendor (no-op: this driver surfaces no LoopKit alerts yet)

    public func acknowledgeAlert(alertIdentifier: Alert.AlertIdentifier, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }
    public func getSoundBaseURL() -> URL? { nil }
    public func getSounds() -> [Alert.Sound] { [] }

    // MARK: State plumbing

    /// Read the current status while the lock is already held.
    private func statusLocked() -> PumpManagerStatus {
        TandemStatusProjection.status(from: lockedState, bolusEngage: bolusEngage, basalEngage: basalEngage, now: Date())
    }

    /// Mutate state and/or engagement under the lock, then notify the delegate + status observers if
    /// anything they observe actually changed. `changes` runs while the lock is held.
    func mutate(_ changes: () -> Void) {
        lock.lock()
        let oldStatus = statusLocked()
        let oldState = lockedState
        changes()
        let newStatus = statusLocked()
        let newState = lockedState
        lock.unlock()

        if oldState != newState {
            let delegate = pumpManagerDelegate
            (delegateQueue ?? .main).async { delegate?.pumpManagerDidUpdateState(self) }
        }
        if oldStatus != newStatus {
            notifyObservers(old: oldStatus, new: newStatus)
        }
    }

    /// Snapshot the state under the lock for read-only use in async transport code.
    func snapshotState() -> TandemPumpManagerState {
        lock.lock(); defer { lock.unlock() }
        return lockedState
    }

    func setBolusEngage(_ e: BolusEngageState) { mutate { self.bolusEngage = e } }
    func setBasalEngage(_ e: BasalEngageState) { mutate { self.basalEngage = e } }

    private func notifyObservers(old: PumpManagerStatus, new: PumpManagerStatus) {
        lock.lock()
        observerBoxes.removeAll { $0.observer == nil }
        let boxes = observerBoxes
        lock.unlock()
        for box in boxes {
            if let observer = box.observer {
                box.queue.async { observer.pumpManager(self, didUpdate: new, oldStatus: old) }
            }
        }
    }

    /// Route dose events to the host. `NewPumpEvent` dedups by `raw` (see `TandemHistoryMapping`).
    func report(events: [NewPumpEvent], lastReconciliation: Date?, replacePending: Bool) {
        guard !events.isEmpty else { return }
        let delegate = pumpManagerDelegate
        (delegateQueue ?? .main).async {
            delegate?.pumpManager(self, hasNewPumpEvents: events, lastReconciliation: lastReconciliation,
                                  replacePendingEvents: replacePending) { _ in }
        }
    }
}

// MARK: - PumpManager (non-delivery members; delivery lives in Delivery.swift)

extension TandemPumpManager: PumpManager {

    // Onboarding-supported ranges (Tandem t:slim X2 / Mobi).
    public static var onboardingMaximumBasalScheduleEntryCount: Int { 16 }
    public static var onboardingSupportedBasalRates: [Double] { Array(stride(from: 0.0, through: 15.0, by: 0.05)) }
    public static var onboardingSupportedBolusVolumes: [Double] { Array(stride(from: 0.05, through: 25.0, by: 0.05)) }
    public static var onboardingSupportedMaximumBolusVolumes: [Double] { Array(stride(from: 1.0, through: 25.0, by: 1.0)) }

    public var supportedBasalRates: [Double] { Self.onboardingSupportedBasalRates }
    public var supportedBolusVolumes: [Double] { Self.onboardingSupportedBolusVolumes }
    public var supportedMaximumBolusVolumes: [Double] { Self.onboardingSupportedMaximumBolusVolumes }
    public var maximumBasalScheduleEntryCount: Int { Self.onboardingMaximumBasalScheduleEntryCount }
    public var minimumBasalScheduleEntryDuration: TimeInterval { 30 * 60 } // 30 minutes

    // The pump does not emit basal-profile-start events into LoopKit in this first cut (basal history is
    // not reconstructed into U/hr doses — see DoseMapping); the host reconstructs basal from the schedule.
    public var pumpRecordsBasalProfileStartEvents: Bool { false }
    public var pumpReservoirCapacity: Double { 300 }

    public var lastSync: Date? {
        lock.lock(); defer { lock.unlock() }
        return lockedState.lastReconciliation
    }

    public var status: PumpManagerStatus {
        lock.lock(); defer { lock.unlock() }
        return statusLocked()
    }

    public func addStatusObserver(_ observer: PumpManagerStatusObserver, queue: DispatchQueue) {
        lock.lock(); defer { lock.unlock() }
        guard !observerBoxes.contains(where: { $0.observer === observer }) else { return }
        observerBoxes.append(ObserverBox(observer, queue))
    }

    public func removeStatusObserver(_ observer: PumpManagerStatusObserver) {
        lock.lock(); defer { lock.unlock() }
        observerBoxes.removeAll { $0.observer === observer || $0.observer == nil }
    }

    public func setMustProvideBLEHeartbeat(_ mustProvideBLEHeartbeat: Bool) {
        // The Tandem pump provides no CGM heartbeat; nothing to bridge. No-op by design.
    }

    public func createBolusProgressReporter(reportingOn dispatchQueue: DispatchQueue) -> DoseProgressReporter? {
        if case .inProgress(let dose) = status.bolusState {
            return TandemDoseProgressEstimator(dose: dose, pumpManager: self, reportingQueue: dispatchQueue)
        }
        return nil
    }

    public func estimatedDuration(toBolus units: Double) -> TimeInterval {
        units / Tandem.bolusDeliveryUnitsPerSecond
    }
}

/// Tandem hardware constants used for estimates.
enum Tandem {
    /// Approximate standard-bolus delivery rate. Used only to estimate a dose's `endDate`; the
    /// authoritative delivered amount always comes from the pump, never from this estimate.
    static let bolusDeliveryUnitsPerSecond: Double = 0.025
}
