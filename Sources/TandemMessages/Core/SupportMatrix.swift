import Foundation

/// Whether a pump answers a command.
///
/// - `supported`: the pump answered it.
/// - `unsupported`: this unit, on this firmware, rejected it (op-77). Only per-unit evidence gives
///   this state: the same command can fail in one place and work in another (HistoryLog failed in a
///   bench sweep yet works on P1).
/// - `untested`: no evidence for this unit yet. When pumps of its class rejected it, the entry is
///   `suspected` as well.
public enum SupportStatus: String, Sendable, Codable, CaseIterable {
    case supported, unsupported, untested
}

/// One pump on one firmware: what per-unit evidence is recorded under. A firmware update starts the
/// unit's evidence over, because the command set comes with the firmware.
public struct PumpUnit: Hashable, Sendable, Codable {
    public let serialNumber: UInt32
    public let armSoftwareVersion: UInt32
    public let mspSoftwareVersion: UInt32

    public init(serialNumber: UInt32, armSoftwareVersion: UInt32, mspSoftwareVersion: UInt32) {
        self.serialNumber = serialNumber
        self.armSoftwareVersion = armSoftwareVersion
        self.mspSoftwareVersion = mspSoftwareVersion
    }

    /// The unit a `PumpVersionResponse` (op-85) describes.
    public init(_ version: PumpVersionResponse) {
        self.init(
            serialNumber: version.serialNum, armSoftwareVersion: version.armSwVer,
            mspSoftwareVersion: version.mspSwVer)
    }
}

/// One observation behind a `SupportEntry`.
public struct SupportEvidence: Sendable, Equatable, Codable {
    public enum Source: String, Sendable, Codable {
        /// A bench run on a real pump.
        case bench
        /// Seen on a phone with a real pump in use.
        case device
        /// A careful probe the app ran, or any reply it recorded.
        case probe
    }

    public enum Scope: Hashable, Sendable, Codable {
        /// This unit on this firmware.
        case unit(PumpUnit)
        /// t:slim X2 pumps reporting this API version (the class P1 or P2 belongs to).
        case tslimAPI(ApiVersion)
    }

    /// What a pump did with the command.
    public enum Result: String, Sendable, Codable {
        case supported, unsupported
        /// An op-77 with the undefined error code (0) followed by a dropped link. P1 answers an
        /// unsupported command this way, but one such drop could be unrelated, so it takes
        /// `strikesToUnsupported` of them, with no answer in between, to make the command unsupported.
        case droppedAfterError
    }

    public let result: Result
    public let source: Source
    public let scope: Scope
    /// Where the observation comes from, for a person reading diagnostics.
    public let note: String
    /// When a probe recorded it; nil for the compiled-in evidence.
    public let recordedAt: Date?

    public init(result: Result, source: Source, scope: Scope, note: String, recordedAt: Date? = nil) {
        self.result = result
        self.source = source
        self.scope = scope
        self.note = note
        self.recordedAt = recordedAt
    }
}

/// What is known about one command on one pump.
public struct SupportEntry: Sendable, Equatable {
    public let status: SupportStatus
    /// Pumps of this unit's class rejected the command, but this unit hasn't been tried: one careful
    /// probe is allowed, and its result is recorded for the unit.
    public let suspected: Bool
    /// Everything behind the status, unit evidence first.
    public let evidence: [SupportEvidence]
}

/// Which commands each pump answers, with the evidence. Replaces the old static minimum-API floor,
/// which blocked 22 commands below API 3.4 on a guess: a pump that lacks a command drops the link
/// after rejecting it, so the app learns per pump instead, at the cost of at most one drop.
///
/// Two kinds of knowledge go in:
/// - compiled in (`classEvidence`): what the bench and the field showed for a class of pump (a t:slim
///   X2 at one API version). A class-level rejection only makes a command `suspected`.
/// - recorded (`recorded`): what this app saw on a specific unit and firmware. The app persists the
///   matrix with the pairing; only this can make a command `unsupported`.
///
/// Signed writes are separate: `allowedSignedWrites` is policy, not evidence. No other signed write
/// is ever sent, and none is ever probed.
public struct SupportMatrix: Sendable, Equatable, Codable {
    /// How many observations are kept per unit and command; older ones add nothing once newer ones
    /// agree, and the matrix is persisted with the pairing.
    public static let observationsKept = 8
    /// How many `droppedAfterError` observations in a row make a command unsupported on a unit. One
    /// leaves it suspected, so it is probed again on a later connection (owner, 2026-10-31: a drop
    /// must not block a command by accident). BAD_OPCODE is the pump saying so, and counts at once.
    public static let strikesToUnsupported = 2

    /// Per-unit evidence, newest last.
    public private(set) var recorded: [PumpUnit: [MessageKey: [SupportEvidence]]] = [:]

    public init() {}

    /// What is known about `key` on `unit`, a pump of `model` reporting `apiVersion`. Unit evidence
    /// wins over class evidence; the latest unit observation wins over earlier ones. Class evidence
    /// applies only to a known t:slim X2, since API versions don't name the model.
    public func entry(
        for key: MessageKey, unit: PumpUnit?, model: PumpModel?, apiVersion: ApiVersion?
    ) -> SupportEntry {
        let unitEvidence = unit.flatMap { recorded[$0]?[key] } ?? []
        var classEvidence: [SupportEvidence] = []
        if model == .tslim, let apiVersion {
            classEvidence = (Self.classEvidence[key] ?? []).filter { $0.scope == .tslimAPI(apiVersion) }
        }
        let evidence = unitEvidence.reversed() + classEvidence
        // Strikes count back from the newest observation to the newest definite one.
        let strikes = unitEvidence.reversed().prefix { $0.result == .droppedAfterError }.count
        if strikes >= Self.strikesToUnsupported {
            return SupportEntry(status: .unsupported, suspected: false, evidence: evidence)
        }
        if strikes > 0 {
            return SupportEntry(status: .untested, suspected: true, evidence: evidence)
        }
        if let latest = unitEvidence.last {
            let status: SupportStatus = latest.result == .supported ? .supported : .unsupported
            return SupportEntry(status: status, suspected: false, evidence: evidence)
        }
        if classEvidence.contains(where: { $0.result == .supported }) {
            return SupportEntry(status: .supported, suspected: false, evidence: evidence)
        }
        let suspected = classEvidence.contains { $0.result == .unsupported }
        return SupportEntry(status: .untested, suspected: suspected, evidence: evidence)
    }

    public func entry(
        for message: some Message, unit: PumpUnit?, model: PumpModel?, apiVersion: ApiVersion?
    ) -> SupportEntry {
        entry(for: MessageKey(message), unit: unit, model: model, apiVersion: apiVersion)
    }

    /// Whether `message` may be sent once as a careful probe: an unsigned read with no answer yet
    /// on this unit (untested, suspected or not). When is the connection layer's call: alone, after the
    /// link has held, at most one per connection.
    public func mayProbe(_ message: some Message, unit: PumpUnit?, model: PumpModel?, apiVersion: ApiVersion?) -> Bool {
        guard !message.signed, message.operationRisk == .read else { return false }
        return entry(for: message, unit: unit, model: model, apiVersion: apiVersion).status == .untested
    }

    /// Records what `unit` did with `key`: `.supported` for an answer, `.unsupported` for an op-77
    /// that means the command isn't there (BAD_OPCODE), `.droppedAfterError` for an error 0 that the
    /// link dropped after. Deciding which reply is which is the connection layer's.
    public mutating func record(
        _ result: SupportEvidence.Result, for key: MessageKey, on unit: PumpUnit, note: String, at date: Date = Date()
    ) {
        let evidence = SupportEvidence(result: result, source: .probe, scope: .unit(unit), note: note, recordedAt: date)
        var kept = recorded[unit]?[key] ?? []
        kept.append(evidence)
        recorded[unit, default: [:]][key] = Array(kept.suffix(Self.observationsKept))
    }

    /// Forgets what this app recorded about `key` on `unit`, so the next request for it is a probe
    /// again. For a developer setting that retests a command (owner, 2026-10-31); the compiled-in class
    /// evidence stays.
    public mutating func forget(_ key: MessageKey, on unit: PumpUnit) {
        recorded[unit]?[key] = nil
        if recorded[unit]?.isEmpty == true { recorded[unit] = nil }
    }

    // MARK: Signed writes

    /// The only signed writes TandemKit sends, on any pump: the remote-bolus family P1 accepts on API
    /// 2.5, InitiateBolus, and DismissNotification (op-184). The other signed writes P1 was sent each
    /// drew op-77 and a dropped link. Everything else
    /// signed is refused before a byte is built, whatever the pump's API version.
    public static let allowedSignedWrites: Set<MessageKey> = [
        MessageKey(BolusPermissionRequest.self),
        MessageKey(InitiateBolusRequest.self),
        MessageKey(CancelBolusRequest.self),
        MessageKey(RemoteCarbEntryRequest.self),
        MessageKey(RemoteBgEntryRequest.self),
        MessageKey(DismissNotificationRequest.self)
    ]

    public static func isAllowedSignedWrite(_ message: some Message) -> Bool {
        !message.signed || allowedSignedWrites.contains(MessageKey(message))
    }

    // MARK: Compiled-in evidence

    /// P1: t:slim X2, API 2.5, legacy pairing, no cartridge, no CGM. P2: t:slim X2, API 4.0, JPAKE.
    static let p1 = SupportEvidence.Scope.tslimAPI(.v2_5)
    static let p2 = SupportEvidence.Scope.tslimAPI(ApiVersion(major: 4, minor: 0))

    /// Class-level evidence by command. Sources: the T-1 bench matrix on P1 (2026-08-23/24, kept on
    /// the `archive/experimental/2026-10-31` tag), the 2026-08-07 P1 probe, and the old app's use of P2
    /// (with a cartridge, and its 2026-08-29 diagnostics export, which listed a read as rejected after
    /// any error, not only BAD_OPCODE).
    static let classEvidence: [MessageKey: [SupportEvidence]] = {
        var e: [MessageKey: [SupportEvidence]] = [:]
        func add(
            _ types: [any Message.Type], _ result: SupportEvidence.Result, _ source: SupportEvidence.Source,
            _ scope: SupportEvidence.Scope, _ note: String
        ) {
            for t in types {
                let key = MessageKey(characteristic: t.props.characteristic, opCode: t.props.opCode)
                e[key, default: []].append(SupportEvidence(result: result, source: source, scope: scope, note: note))
            }
        }

        // P1, reads that answered in the T-1 sweep.
        add(
            [
                AlarmStatusRequest.self, AlertStatusRequest.self, ApiVersionRequest.self,
                BasalLimitSettingsRequest.self, BolusCalcDataSnapshotRequest.self, ControlIQIOBRequest.self,
                ControlIQInfoV1Request.self, ControlIQInfoV2Request.self, ControlIQSleepScheduleRequest.self,
                CurrentActiveIdpValuesRequest.self, CurrentBasalStatusRequest.self, CurrentBatteryV1Request.self,
                CurrentBatteryV2Request.self, CurrentBolusStatusRequest.self, ExtendedBolusStatusRequest.self,
                GlobalMaxBolusSettingsRequest.self, HighestAamRequest.self, HistoryLogStatusRequest.self,
                HomeScreenMirrorRequest.self, InsulinStatusRequest.self, LastBGRequest.self,
                LastBolusStatusRequest.self, LastBolusStatusV2Request.self, LocalizationRequest.self,
                MalfunctionStatusRequest.self, NonControlIQIOBRequest.self, ProfileStatusRequest.self,
                PumpFeaturesV1Request.self, PumpFeaturesV2Request.self, PumpGlobalsRequest.self,
                PumpSettingsRequest.self, PumpVersionBRequest.self, PumpVersionRequest.self,
                RemindersRequest.self, TempRateRequest.self, TimeSinceResetRequest.self
            ], .supported, .bench, p1, "answered in the T-1 bench sweep on P1")
        // P1, CGM reads that answered with no sensor paired.
        add(
            [
                CGMStatusRequest.self, CGMHardwareInfoRequest.self, CGMGlucoseAlertSettingsRequest.self,
                CGMRateAlertSettingsRequest.self, CGMOORAlertSettingsRequest.self, CurrentEGVGuiDataRequest.self
            ], .supported, .bench, p1, "answered on P1 with no CGM sensor paired (T-1)")
        // HistoryLog drew op-77 once in the T-1 sweep, but the app reads it on P1, and settling a bolus
        // from history depends on it: never pre-marked unsupported or suspected.
        add([HistoryLogRequest.self], .supported, .device, p1, "read by the app on P1")
        // P1, reads that drew op-77 and a link drop in the T-1 sweep.
        add(
            [
                LoadStatusRequest.self, ExtendedBolusStatusV2Request.self, TempRateStatusRequest.self,
                BasalIQStatusRequest.self, BasalIQSettingsRequest.self, BasalIQAlertInfoRequest.self,
                BleSoftwareInfoRequest.self, SecretMenuRequest.self, IDPSettingsRequest.self,
                IDPSegmentRequest.self, CreateHistoryLogRequest.self, StreamDataReadinessRequest.self
            ], .unsupported, .bench, p1, "op-77 and a link drop in the T-1 bench sweep on P1")
        add(
            [GetG6TransmitterHardwareInfoRequest.self, GetSavedG7PairingCodeRequest.self], .unsupported, .bench, p1,
            "op-77 and a link drop on P1 with no CGM sensor paired; may differ with one")
        add(
            [CurrentEgvGuiDataV2Request.self], .unsupported, .device, p1,
            "op-77 and a link drop on P1; it caused the old app's reconnect loop")

        // P1, signed writes. Accepted: the remote-bolus family. BolusPermission was accepted but not
        // granted, because P1 has no cartridge.
        add(
            [
                BolusPermissionRequest.self, CancelBolusRequest.self, RemoteCarbEntryRequest.self,
                RemoteBgEntryRequest.self
            ],
            .supported, .bench, p1, "signed write accepted on P1")
        // Rejected with op-77 and a drop. Not allowed anyway; kept so the evidence is in one place.
        add(
            [
                PlaySoundRequest.self, UserInteractionRequest.self, ChangeControlIQSettingsRequest.self,
                SetMaxBolusLimitRequest.self, SetMaxBasalLimitRequest.self, SetLowInsulinAlertRequest.self,
                SetAutoOffAlertRequest.self, SetPumpSoundsRequest.self, ChangeTimeDateRequest.self
            ], .unsupported, .bench, p1, "signed write rejected on P1: op-77 and a link drop")
        add(
            [SetModesRequest.self, SetTempRateRequest.self], .unsupported, .bench, p1,
            "signed write rejected on P1 in the 2026-08-07 probe (upstream marks it Mobi-only)")

        // P2, from the old app in use.
        add(
            [
                BolusPermissionRequest.self, InitiateBolusRequest.self, CancelBolusRequest.self,
                RemoteCarbEntryRequest.self, RemoteBgEntryRequest.self, DismissNotificationRequest.self
            ],
            .supported, .device, p2, "used by the old app on P2 with a cartridge")
        add(
            [HistoryLogStatusRequest.self, HistoryLogRequest.self], .supported, .device, p2,
            "settled boluses from history on P2")
        add(
            [LastBolusStatusV2Request.self], .unsupported, .device, p2,
            "op-77 on P2, so a completed bolus can't be settled from it")
        add(
            [
                LoadStatusRequest.self, InsulinStatusRequest.self, HomeScreenMirrorRequest.self,
                CurrentBatteryV2Request.self
            ],
            .unsupported, .device, p2,
            "listed as rejected by the old app on P2, which rejected a read on any error; unconfirmed")
        return e
    }()
}
