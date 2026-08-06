import Foundation
import HealthKit
import LoopKit
import PumpX2Messages

// Delivery + sync members of the PumpManager conformance. The conformance is declared in
// TandemPumpManager.swift; these are additional members of the same type.
extension TandemPumpManager {

    static let readDeadline: TimeInterval = 5
    static let controlDeadline: TimeInterval = 8

    // MARK: Signing

    /// Fetch a fresh `TimeSinceReset` signing timestamp and pair it with the pairing auth key.
    @MainActor
    func freshSigning(_ c: TandemPumpConnection, authKey: [UInt8]) async throws -> TandemSigning {
        let resp = try await c.send(TimeSinceResetRequest(), signing: nil, allowInsulinDelivery: false,
                                    serialized: false, deadline: Self.readDeadline)
        guard let tr = resp as? TimeSinceResetResponse else { throw TandemTransportError.badResponse("TimeSinceReset") }
        return TandemSigning(authKey: authKey, pumpTimeSinceReset: tr.signingTimestamp)
    }

    // MARK: enactBolus

    public func enactBolus(units: Double, activationType: BolusActivationType,
                           completion: @escaping (PumpManagerError?) -> Void) {
        let s = snapshotState()
        guard let connection else { completion(.deviceState(TandemDriverError.notConnected)); return }
        guard let authKey = s.authKey else { completion(.configuration(TandemDriverError.notPaired)); return }
        // Refuse a new delivery while one is in flight or its outcome is unresolved (fail-closed).
        guard s.pendingDose == nil, !s.deliveryUncertain else { completion(.deviceState(TandemDriverError.busy)); return }
        guard units.isFinite, units > 0 else { completion(.configuration(TandemDriverError.invalidDose)); return }
        let totalMu = UInt32(min((units * 1000).rounded(), Double(UInt32.max)))
        // A units-only (no-carb) bolus: FOOD2 only — matches faBolus/TandemBackend's proven encoding.
        let bitmask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)

        setBolusEngage(.engaging)
        Task { @MainActor in
            do {
                let signing = try await self.freshSigning(connection, authKey: authKey)
                try await connection.withDeliveryPolicy {
                    // 1. permission → bolus id
                    let permResp = try await connection.send(BolusPermissionRequest(), signing: signing,
                                                              allowInsulinDelivery: false, serialized: true,
                                                              deadline: Self.controlDeadline)
                    guard let perm = permResp as? BolusPermissionResponse, perm.granted else {
                        throw TandemDriverError.denied("bolus permission denied")
                    }
                    let id = perm.bolusId
                    // 2. build + validate BEFORE persisting anything (a validation throw = clean, pre-write).
                    let req = try InitiateBolusRequest(
                        validating: totalMu, bolusID: id, bolusTypeBitmask: bitmask,
                        foodVolume: 0, correctionVolume: 0, bolusCarbs: 0, bolusBG: 0, bolusIOB: 0,
                        extendedVolume: 0, extendedSeconds: 0, extended3: 0)
                    // 3. DURABLY persist the pending dose (with its id) BEFORE the initiate write, so an
                    //    indeterminate outcome after the write is reconcilable and never lost.
                    let start = Date()
                    let pending = TandemUnfinalizedDose(
                        doseType: .bolus, programmedUnits: units, finalizedUnits: nil,
                        startTime: start, duration: units / Tandem.bolusDeliveryUnitsPerSecond,
                        scheduledCertainty: .uncertain, automatic: activationType.isAutomatic,
                        insulinType: nil, bolusId: id,
                        syncIdentifier: TandemUnfinalizedDose.syncIdentifier(pumpSerial: s.pumpSerial, tag: "bolus", id: UInt32(clamping: id)))
                    self.mutate { self.lockedState.pendingDose = pending }
                    // 4. initiate (signed, delivery). ACCEPTED ≠ DELIVERED.
                    let initResp = try await connection.send(req, signing: signing, allowInsulinDelivery: true,
                                                             serialized: true, deadline: Self.controlDeadline)
                    guard let ir = initResp as? InitiateBolusResponse else {
                        // Parsed to an unexpected type after the write went out → indeterminate.
                        throw TandemTransportError.timedOut
                    }
                    // Only a parsed, explicit NACK is a terminal FAILED (never delivered).
                    guard ir.accepted else { throw TandemDriverError.denied("initiate not accepted (nack)") }
                }
                // Accepted and in flight — KNOWN, not uncertain. Report the mutable dose; finalize later
                // (on ensureCurrentPumpData → reconcile), never block-polling to completion here.
                self.setBolusEngage(.stable)
                if let pending = self.snapshotState().pendingDose { self.report(events: [NewPumpEvent(pending)], lastReconciliation: self.lastSync, replacePending: true) }
                completion(nil)
            } catch let e as TandemTransportError where e.isIndeterminateAfterWrite && self.snapshotState().pendingDose != nil {
                // The initiate write was issued (pending persisted) but the outcome is unknown.
                self.mutate { self.lockedState.deliveryUncertain = true }
                self.setBolusEngage(.stable)
                completion(.uncertainDelivery)
            } catch let e as TandemTransportError {
                // Transport error BEFORE the initiate write (e.g. permission timed out) — nothing delivered.
                self.mutate { self.lockedState.pendingDose = nil; self.lockedState.deliveryUncertain = false }
                self.setBolusEngage(.stable)
                completion(.communication(TandemDriverError.transport(e)))
            } catch let e as TandemDriverError {
                // Explicit denial / NACK → clean terminal failure; clear any tentatively-persisted dose.
                self.mutate { self.lockedState.pendingDose = nil; self.lockedState.deliveryUncertain = false }
                self.setBolusEngage(.stable)
                completion(e.asPumpManagerError)
            } catch {
                self.mutate { self.lockedState.pendingDose = nil; self.lockedState.deliveryUncertain = false }
                self.setBolusEngage(.stable)
                completion(.communication(TandemDriverError.protocolError("\(error)")))
            }
        }
    }

    // MARK: cancelBolus

    public func cancelBolus(completion: @escaping (PumpManagerResult<DoseEntry?>) -> Void) {
        let s = snapshotState()
        guard let connection else { completion(.failure(.deviceState(TandemDriverError.notConnected))); return }
        guard let authKey = s.authKey else { completion(.failure(.configuration(TandemDriverError.notPaired))); return }
        guard let pending = s.pendingDose, pending.doseType == .bolus, let bolusId = pending.bolusId else {
            completion(.success(nil)); return // nothing bolusing
        }
        setBolusEngage(.canceling)
        Task { @MainActor in
            do {
                let signing = try await self.freshSigning(connection, authKey: authKey)
                try await connection.withDeliveryPolicy {
                    _ = try await connection.send(CancelBolusRequest(bolusId: bolusId), signing: signing,
                                                  allowInsulinDelivery: true, serialized: true,
                                                  deadline: Self.controlDeadline)
                }
                // A cancel is only a request; the delivered amount still comes from the pump's own record.
                let dose = try await self.readAndFinalize(connection, bolusId: bolusId)
                self.setBolusEngage(.stable)
                completion(.success(dose))
            } catch let e as TandemTransportError where e.isIndeterminateAfterWrite {
                self.mutate { self.lockedState.deliveryUncertain = true }
                self.setBolusEngage(.stable)
                completion(.failure(.uncertainDelivery))
            } catch {
                self.setBolusEngage(.stable)
                completion(.failure(.communication(TandemDriverError.protocolError("\(error)"))))
            }
        }
    }

    /// Read the pump's authoritative last-bolus record for `bolusId` and finalize the pending dose with
    /// its delivered amount. Returns nil (without inventing an amount) if the pump can't confirm it yet.
    @MainActor
    func readAndFinalize(_ c: TandemPumpConnection, bolusId: Int) async throws -> DoseEntry? {
        let resp = try await c.send(LastBolusStatusV2Request(), signing: nil, allowInsulinDelivery: false,
                                    serialized: false, deadline: Self.readDeadline)
        guard let last = resp as? LastBolusStatusV2Response, last.bolusId == bolusId else { return nil }
        return finalizeBolus(bolusId: bolusId, deliveredUnits: last.deliveredUnits)
    }

    /// Finalize the pending bolus with the pump-authoritative delivered amount, clear the uncertain
    /// flag, and report the immutable finalized dose to the host.
    @discardableResult
    func finalizeBolus(bolusId: Int, deliveredUnits: Double) -> DoseEntry? {
        var finalized: TandemUnfinalizedDose?
        mutate {
            if var d = self.lockedState.pendingDose, d.doseType == .bolus, d.bolusId == bolusId {
                d.finalizedUnits = deliveredUnits
                finalized = d
                self.lockedState.pendingDose = nil
            }
            self.lockedState.deliveryUncertain = false
            self.lockedState.lastReconciliation = Date()
        }
        guard let f = finalized else { return nil }
        report(events: [NewPumpEvent(f)], lastReconciliation: snapshotState().lastReconciliation, replacePending: true)
        return DoseEntry(f)
    }

    // MARK: suspend / resume

    public func suspendDelivery(completion: @escaping (Error?) -> Void) {
        controlWrite(engageBasal: .suspending, makeRequest: { SuspendPumpingRequest() },
                     accepted: { ($0 as? SuspendPumpingResponse)?.accepted == true },
                     onAccepted: { self.mutate { self.lockedState.suspended = true } },
                     completion: completion)
    }

    public func resumeDelivery(completion: @escaping (Error?) -> Void) {
        controlWrite(engageBasal: .resuming, makeRequest: { ResumePumpingRequest() },
                     accepted: { ($0 as? ResumePumpingResponse)?.accepted == true },
                     onAccepted: { self.mutate { self.lockedState.suspended = false } },
                     completion: completion)
    }

    private func controlWrite(engageBasal: BasalEngageState,
                              makeRequest: @escaping () -> any Message,
                              accepted: @escaping (any Message) -> Bool,
                              onAccepted: @escaping () -> Void,
                              completion: @escaping (Error?) -> Void) {
        let s = snapshotState()
        guard let connection else { completion(TandemDriverError.notConnected); return }
        guard let authKey = s.authKey else { completion(TandemDriverError.notPaired); return }
        setBasalEngage(engageBasal)
        Task { @MainActor in
            do {
                let signing = try await self.freshSigning(connection, authKey: authKey)
                let resp = try await connection.withDeliveryPolicy {
                    try await connection.send(makeRequest(), signing: signing, allowInsulinDelivery: true,
                                              serialized: true, deadline: Self.controlDeadline)
                }
                guard accepted(resp) else { throw TandemDriverError.denied("command not accepted") }
                onAccepted()
                self.setBasalEngage(.stable)
                completion(nil)
            } catch {
                self.setBasalEngage(.stable)
                completion(error)
            }
        }
    }

    // MARK: enactTempBasal (percent↔U/hr; Mobi-gated on real hardware)

    public func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval,
                               completion: @escaping (PumpManagerError?) -> Void) {
        let s = snapshotState()
        guard let connection else { completion(.deviceState(TandemDriverError.notConnected)); return }
        guard let authKey = s.authKey else { completion(.configuration(TandemDriverError.notPaired)); return }
        let isCancel = duration < 1
        setBasalEngage(isCancel ? .cancelingTempBasal : .engagingTempBasal)
        Task { @MainActor in
            do {
                let signing = try await self.freshSigning(connection, authKey: authKey)
                if isCancel {
                    let resp = try await connection.withDeliveryPolicy {
                        try await connection.send(StopTempRateRequest(), signing: signing, allowInsulinDelivery: true,
                                                  serialized: true, deadline: Self.controlDeadline)
                    }
                    guard (resp as? StopTempRateResponse)?.accepted == true else { throw TandemDriverError.denied("stop temp rate not accepted") }
                    self.mutate { if self.lockedState.pendingDose?.doseType == .tempBasal { self.lockedState.pendingDose = nil } }
                    self.setBasalEngage(.stable)
                    completion(nil)
                    return
                }
                // Convert the requested absolute rate to the achievable Tandem percent-of-scheduled.
                let basalResp = try await connection.send(CurrentBasalStatusRequest(), signing: nil,
                                                          allowInsulinDelivery: false, serialized: false,
                                                          deadline: Self.readDeadline)
                guard let basal = basalResp as? CurrentBasalStatusResponse else { throw TandemDriverError.protocolError("no basal status") }
                let conv = try TandemTempBasalConversion.percent(
                    forUnitsPerHour: unitsPerHour, scheduledUnitsPerHour: basal.currentBasalUnitsPerHour,
                    minPercent: SetTempRateRequest.minPercent, maxPercent: SetTempRateRequest.maxPercent)
                let minutes = min(max(Int((duration / 60).rounded()), SetTempRateRequest.minMinutes), SetTempRateRequest.maxMinutes)
                let resp = try await connection.withDeliveryPolicy {
                    try await connection.send(SetTempRateRequest(minutes: minutes, percent: conv.percent),
                                              signing: signing, allowInsulinDelivery: true, serialized: true,
                                              deadline: Self.controlDeadline)
                }
                guard let tempResp = resp as? SetTempRateResponse, tempResp.accepted else {
                    throw TandemDriverError.denied("temp rate not accepted (temp basal is Mobi-only; rejected on t:slim)")
                }
                // Report the EFFECTIVE achievable rate — never claim the requested rate.
                let start = Date()
                let dose = TandemUnfinalizedDose(
                    doseType: .tempBasal, programmedUnits: conv.effectiveUnitsPerHour, finalizedUnits: nil,
                    startTime: start, duration: TimeInterval(minutes * 60), scheduledCertainty: .certain,
                    automatic: true, insulinType: nil, bolusId: nil,
                    syncIdentifier: TandemUnfinalizedDose.syncIdentifier(pumpSerial: s.pumpSerial, tag: "temp", id: UInt32(clamping: tempResp.tempRateId)))
                self.mutate { self.lockedState.pendingDose = dose }
                self.report(events: [NewPumpEvent(dose)], lastReconciliation: self.lastSync, replacePending: true)
                self.setBasalEngage(.stable)
                completion(nil)
            } catch let e as TandemDriverError {
                self.setBasalEngage(.stable)
                completion(e.asPumpManagerError)
            } catch let e as TandemTempBasalConversion.ConversionError {
                self.setBasalEngage(.stable)
                completion(.configuration(TandemDriverError.protocolError("\(e)")))
            } catch let e as TandemTransportError {
                self.setBasalEngage(.stable)
                completion(.communication(TandemDriverError.transport(e)))
            } catch {
                self.setBasalEngage(.stable)
                completion(.communication(TandemDriverError.protocolError("\(error)")))
            }
        }
    }

    // MARK: syncDeliveryLimits / syncBasalRateSchedule

    public func syncDeliveryLimits(limits deliveryLimits: DeliveryLimits,
                                   completion: @escaping (Result<DeliveryLimits, Error>) -> Void) {
        let s = snapshotState()
        guard let connection else { completion(.failure(TandemDriverError.notConnected)); return }
        guard let authKey = s.authKey else { completion(.failure(TandemDriverError.notPaired)); return }
        Task { @MainActor in
            do {
                let signing = try await self.freshSigning(connection, authKey: authKey)
                try await connection.withDeliveryPolicy {
                    if let maxBolus = deliveryLimits.maximumBolus?.doubleValue(for: .internationalUnit()) {
                        let mu = Int((maxBolus * 1000).rounded())
                        let resp = try await connection.send(SetMaxBolusLimitRequest(maxBolusMilliunits: mu),
                                                             signing: signing, allowInsulinDelivery: false,
                                                             serialized: true, deadline: Self.controlDeadline)
                        guard (resp as? SetMaxBolusLimitResponse)?.accepted == true else {
                            throw TandemDriverError.denied("max bolus limit not accepted (Mobi-only)")
                        }
                    }
                    let unitsPerHour = HKUnit.internationalUnit().unitDivided(by: .hour())
                    if let maxBasal = deliveryLimits.maximumBasalRate?.doubleValue(for: unitsPerHour) {
                        let mu = UInt32(min((maxBasal * 1000).rounded(), Double(UInt32.max)))
                        let resp = try await connection.send(SetMaxBasalLimitRequest(maxHourlyBasalMilliunits: mu),
                                                             signing: signing, allowInsulinDelivery: false,
                                                             serialized: true, deadline: Self.controlDeadline)
                        guard (resp as? SetMaxBasalLimitResponse)?.accepted == true else {
                            throw TandemDriverError.denied("max basal limit not accepted (Mobi-only)")
                        }
                    }
                }
                completion(.success(deliveryLimits)) // echo the applied limits
            } catch {
                completion(.failure(error))
            }
        }
    }

    public func syncBasalRateSchedule(items scheduleItems: [RepeatingScheduleValue<Double>],
                                      completion: @escaping (Result<BasalRateSchedule, Error>) -> Void) {
        // IDP basal-schedule writes are Mobi-gated, multi-segment, and insulin-affecting — not
        // implemented in this first cut. Fail HONESTLY rather than echo a success that never reached the
        // pump (a false success would corrupt the host's model of programmed basal).
        completion(.failure(TandemDriverError.unsupported("basal-schedule write is not implemented in this driver version")))
    }

    // MARK: ensureCurrentPumpData / reconcile / history

    public func ensureCurrentPumpData(completion: ((Date?) -> Void)?) {
        guard let connection else { completion?(self.lastSync); return }
        Task { @MainActor in
            await self.reconcileIndeterminateIfNeeded(connection)
            let now = Date()
            self.mutate { self.lockedState.lastReconciliation = now }
            completion?(now)
        }
    }

    /// If a bolus is pending, ask the pump for its authoritative last-bolus record and finalize when it
    /// matches — closing an indeterminate delivery against pump history. Leaves it pending otherwise.
    @MainActor
    func reconcileIndeterminateIfNeeded(_ c: TandemPumpConnection) async {
        let s = snapshotState()
        guard let pending = s.pendingDose, pending.doseType == .bolus, let bolusId = pending.bolusId else { return }
        do {
            let resp = try await c.send(LastBolusStatusV2Request(), signing: nil, allowInsulinDelivery: false,
                                        serialized: false, deadline: Self.readDeadline)
            if let last = resp as? LastBolusStatusV2Response, last.bolusId == bolusId {
                _ = finalizeBolus(bolusId: bolusId, deliveredUnits: last.deliveredUnits)
            }
        } catch {
            // Still unknown — leave `pendingDose` + `deliveryUncertain` for the next reconcile.
        }
    }

    /// Map decoded pump history-log events to LoopKit dose events and report them. Exposed so tests can
    /// exercise the mapping and a future live history-stream reader can call it directly. Dedup is by the
    /// pump's own ids (see `TandemHistoryMapping`), so re-ingesting a page is a no-op for the host.
    public func ingestHistory(events: [any HistoryLogEvent]) {
        let serial = snapshotState().pumpSerial
        report(events: TandemHistoryMapping.newPumpEvents(from: events, pumpSerial: serial),
               lastReconciliation: lastSync, replacePending: false)
    }
}
