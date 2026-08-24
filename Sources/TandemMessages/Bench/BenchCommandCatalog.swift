import Foundation

// BenchCommandCatalog — the PURE, testable command surface for the saline-bench coverage harness.
//
// This file is transport-free and platform-free (no CoreBluetooth): every fact about a command is
// DERIVED from that command's existing `MessageProps` (opcode, `modifiesInsulinDelivery`, `signed`,
// `supportedDevices`, `minApi`, characteristic, operation-risk). Nothing here composes or alters dose
// bytes — it only READS the static metadata the messages already declare, so it cannot perturb the
// cliparser byte-parity baseline. The one deliberately-curated safety input is
// `benchExercisableSignedWrites` (which signed non-delivery writes the coverage runner may auto-fire);
// everything else is derived so the classification does not rot as messages are added.
//
// The catalog + classification live here so the coverage runner (an executable that CANNOT be unit-
// tested — CoreBluetooth aborts under `swift test`) is a thin driver over logic that IS unit-tested.

/// How the bench harness can drive a command.
public enum BenchLane: String, Sendable, Codable, CaseIterable {
    /// Read / status / query. No saline; verified by a typed response parse. Always bench-safe.
    case read
    /// Signed control that does NOT modify insulin delivery (settings, benign, destructive). Only a
    /// small curated allowlist is auto-fired as an accept/NACK probe; the rest are recorded as GAPs.
    case signedWrite
    /// Modifies insulin delivery (`modifiesInsulinDelivery: true`). Bench-safe only behind the saline
    /// cartridge + `PUMPX2_DELIVER_SALINE` gate; verified by the pump's OWN history-log read-back.
    case delivery
    /// Pairing-handshake message (AUTHORIZATION characteristic). Not sent standalone — exercised
    /// implicitly when the session pairs, so coverage is attributed by pairing scheme.
    case pairing
}

/// The pairing scheme a handshake message belongs to (and that a session negotiates).
public enum BenchPairingScheme: String, Sendable, Codable, CaseIterable {
    /// EC-JPAKE 6-digit numeric PIN (software v7.7+ / API 3.2+).
    case jpake
    /// Legacy V1 16-char CentralChallenge→PumpChallenge (pre-v7.7).
    case legacyV1
}

/// Immutable, pure per-command metadata derived from `MessageProps`. This is the answer to
/// deliverable #1 ("per-command prerequisite metadata") for every enumerated command.
public struct BenchCommand: Sendable, Equatable {
    /// The Swift type name of the request (e.g. "InitiateBolusRequest").
    public let name: String
    public let opCode: UInt8
    public let characteristic: Characteristic
    public let messageType: MessageType
    public let signed: Bool
    /// `modifiesInsulinDelivery` from props — the single source of truth for "is this a delivery op".
    public let modifiesDelivery: Bool
    public let risk: OperationRisk
    /// The pump families this command is legal on. `supportedDevices ?? all` (nil props = every model).
    public let applicablePumpModels: [PumpModel]
    /// The negotiated-API floor, if the message declares one (`minApi`).
    public let minApi: ApiVersion?
    /// A cartridge must be present to fully exercise (and history-log-verify) this command. Derived:
    /// every delivery op needs a cartridge to actually dispense and to read back a delivered amount.
    public let requiresCartridge: Bool
    /// A CGM sensor must be present to exercise this command's glucose/sensor path. Derived from the
    /// command name (CGM/EGV/Dexcom/sensor/transmitter/G6/G7 family) — conservative and self-maintaining.
    public let requiresCGM: Bool
    /// The lane the harness drives this command through.
    public let lane: BenchLane
    /// For `lane == .pairing`, which scheme this message belongs to; else nil.
    public let pairingScheme: BenchPairingScheme?

    /// Whether the coverage runner may AUTO-FIRE this command in the current-lane sense (a safety gate,
    /// distinct from prerequisite gating). Reads and delivery (behind the saline gate) are auto-fireable;
    /// a signed non-delivery write is auto-fired only if it is on the curated `benchExercisableSignedWrites`
    /// allowlist; pairing is exercised implicitly. Destructive commands are NEVER auto-fired.
    public var isAutoFireable: Bool {
        switch lane {
        case .read: return true
        case .delivery: return true               // still gated on saline+cartridge by `plan`
        case .pairing: return true                // implicit on connect
        case .signedWrite: return BenchCommandCatalog.benchExercisableSignedWrites.contains(name)
        }
    }
}

/// The enumerated command surface + the pure derivation from `MessageProps`.
public enum BenchCommandCatalog {

    /// The set of signed NON-delivery writes the coverage runner may auto-fire, DERIVED from the
    /// reversible-affordance catalog (every one with a wired, self-reversing `.drivable` affordance) so it
    /// GROWS automatically as affordances are added — no hand-maintained list to rot. It now spans the
    /// captureReapply settings writes (read→re-apply the SAME value→verify unchanged) and the benign
    /// accept/NACK probes (permission pair, sound, remote entries, user-interaction, cancel-with-no-bolus).
    /// Every OTHER signed non-delivery write is still a GAP: `.manualOnly` (destructive / irreversible /
    /// session-disrupting — owner-only) or `.bespokePending` (reversible but its generic driver is not yet
    /// wired). See `BenchAffordanceCatalog` for the per-command strategy + the runbook exceptions.
    public static let benchExercisableSignedWrites: Set<String> =
        Set(BenchAffordanceCatalog.drivableSignedWrites.map { $0.command })

    /// Case-insensitive name tokens that mark a command as CGM/glucose-dependent (`requiresCGM`). New
    /// CGM-family commands that follow the naming convention auto-classify, so this does not rot.
    static let cgmNameTokens = ["cgm", "egv", "dexcom", "sensor", "transmitter", "g6", "g7"]

    /// Pure predicate: does this command name denote a CGM/glucose-dependent op?
    public static func requiresCGM(name: String) -> Bool {
        let lower = name.lowercased()
        return cgmNameTokens.contains { lower.contains($0) }
    }

    /// Derive a `BenchCommand` from a name + its static `MessageProps`. This is the pure classifier the
    /// unit tests exercise directly.
    public static func descriptor(name: String, props: MessageProps) -> BenchCommand {
        let lane: BenchLane
        var scheme: BenchPairingScheme? = nil
        if props.characteristic == .authorization {
            lane = .pairing
            scheme = name.contains("Jpake") ? .jpake : .legacyV1
        } else if props.modifiesInsulinDelivery {
            lane = .delivery
        } else if props.signed || props.characteristic == .control {
            lane = .signedWrite
        } else {
            lane = .read
        }
        return BenchCommand(
            name: name,
            opCode: props.opCode,
            characteristic: props.characteristic,
            messageType: props.type,
            signed: props.signed,
            modifiesDelivery: props.modifiesInsulinDelivery,
            risk: props.operationRisk,
            applicablePumpModels: props.supportedDevices ?? PumpModel.allCases,
            minApi: props.minApi,
            requiresCartridge: props.modifiesInsulinDelivery,
            requiresCGM: requiresCGM(name: name),
            lane: lane,
            pairingScheme: scheme
        )
    }

    /// Derive a descriptor straight from a message metatype (name via `String(describing:)`, props static).
    public static func descriptor(for type: any Message.Type) -> BenchCommand {
        descriptor(name: String(describing: type), props: type.props)
    }

    /// The full enumerated command surface: every request type under `Sources/TandemMessages/Requests`.
    /// Adding a new request means adding it here once; the count regression test guards against omissions.
    public static let messageTypes: [any Message.Type] = [
        // ── Authentication / pairing (AUTHORIZATION characteristic) ──────────────────────────────
        CentralChallengeRequest.self, PumpChallengeRequest.self,
        Jpake1aRequest.self, Jpake1bRequest.self, Jpake2Request.self,
        Jpake3SessionKeyRequest.self, Jpake4KeyConfirmationRequest.self,

        // ── CurrentStatus reads (empty-cargo status/query reads + version/history/IDP) ───────────
        ControlIQIOBRequest.self, NonControlIQIOBRequest.self, InsulinStatusRequest.self,
        CurrentBatteryV2Request.self, CurrentBasalStatusRequest.self, HomeScreenMirrorRequest.self,
        PumpVersionRequest.self, TimeSinceResetRequest.self, CurrentBolusStatusRequest.self,
        LastBolusStatusV2Request.self, ControlIQInfoV2Request.self, LastBGRequest.self,
        CurrentEgvGuiDataV2Request.self, PumpGlobalsRequest.self, PumpSettingsRequest.self,
        BolusCalcDataSnapshotRequest.self, AlertStatusRequest.self, AlarmStatusRequest.self,
        MalfunctionStatusRequest.self, ProfileStatusRequest.self, CurrentActiveIdpValuesRequest.self,
        GlobalMaxBolusSettingsRequest.self, BasalLimitSettingsRequest.self, ControlIQInfoV1Request.self,
        PumpFeaturesV1Request.self, LoadStatusRequest.self, ExtendedBolusStatusV2Request.self,
        CGMStatusRequest.self, CgmStatusV2Request.self, CGMHardwareInfoRequest.self,
        CurrentBatteryV1Request.self, CurrentEGVGuiDataRequest.self, ExtendedBolusStatusRequest.self,
        LastBolusStatusRequest.self, LastBolusStatusV3Request.self, TempRateRequest.self,
        TempRateStatusRequest.self, RemindersRequest.self, ControlIQSleepScheduleRequest.self,
        BasalIQStatusRequest.self, BasalIQSettingsRequest.self, BasalIQAlertInfoRequest.self,
        CGMGlucoseAlertSettingsRequest.self, CGMRateAlertSettingsRequest.self, CGMOORAlertSettingsRequest.self,
        BleSoftwareInfoRequest.self, GetG6TransmitterHardwareInfoRequest.self, GetSavedG7PairingCodeRequest.self,
        HighestAamRequest.self, LocalizationRequest.self, PumpVersionBRequest.self,
        SecretMenuRequest.self, UnknownMobiOpcode110Request.self,
        HistoryLogStatusRequest.self, HistoryLogRequest.self, ApiVersionRequest.self,
        IDPSettingsRequest.self, IDPSegmentRequest.self,
        BolusPermissionChangeReasonRequest.self, CgmSupportPackageStatusRequest.self,
        CommonSoftwareInfoRequest.self, CreateHistoryLogRequest.self, StreamDataReadinessRequest.self,
        PumpFeaturesV2Request.self, ActiveAamBitsRequest.self,

        // ── Control writes (CONTROL characteristic; signed) ──────────────────────────────────────
        // Bolus / permission
        BolusPermissionRequest.self, BolusPermissionReleaseRequest.self, InitiateBolusRequest.self,
        CancelBolusRequest.self, AdditionalBolusRequest.self,
        // Remote entry (benign metadata)
        RemoteCarbEntryRequest.self, RemoteBgEntryRequest.self,
        // Suspend / resume (Mobi-only delivery)
        SuspendPumpingRequest.self, ResumePumpingRequest.self,
        // Cartridge / tubing / cannula
        EnterChangeCartridgeModeRequest.self, ExitChangeCartridgeModeRequest.self,
        EnterFillTubingModeRequest.self, ExitFillTubingModeRequest.self,
        FillCannulaRequest.self, PrimeTubingSuspendRequest.self,
        // Dangerous / destructive
        ActivateShelfModeRequest.self, DisconnectPumpRequest.self,
        FactoryResetRequest.self, FactoryResetBRequest.self,
        UserInteractionRequest.self, StreamDataPreflightRequest.self, SendTipsControlGenericTestRequest.self,
        // CGM alert config + Control-IQ + additional-bolus settings
        CgmHighLowAlertRequest.self, CgmOutOfRangeAlertRequest.self, CgmRiseFallAlertRequest.self,
        ChangeControlIQSettingsRequest.self, SetG6TransmitterIdRequest.self,
        // Modes / active IDP (Mobi-only delivery)
        SetModesRequest.self, SetActiveIDPRequest.self,
        // Limits
        SetMaxBolusLimitRequest.self, SetMaxBasalLimitRequest.self,
        // CGM control
        StartDexcomG6SensorSessionRequest.self, StopDexcomCGMSensorSessionRequest.self,
        SetSensorTypeRequest.self, SetDexcomG7PairingCodeRequest.self,
        // Temp rate (Mobi-only delivery)
        SetTempRateRequest.self, StopTempRateRequest.self,
        // Alert settings
        SetLowInsulinAlertRequest.self, SetAutoOffAlertRequest.self,
        // IDP CRUD (Mobi-only; several are delivery-class)
        CreateIDPRequest.self, DeleteIDPRequest.self, RenameIDPRequest.self,
        SetIDPSegmentRequest.self, SetIDPSettingsRequest.self,
        // Reminders
        SetBgReminderRequest.self, SetSiteChangeReminderRequest.self, SetMissedMealBolusReminderRequest.self,
        SetPumpAlertSnoozeRequest.self, SetQuickBolusSettingsRequest.self, SetSleepScheduleRequest.self,
        // Sounds / time
        PlaySoundRequest.self, SetPumpSoundsRequest.self, ChangeTimeDateRequest.self,
    ]

    /// The full derived catalog, one `BenchCommand` per enumerated request type.
    public static let all: [BenchCommand] = messageTypes.map { descriptor(for: $0) }

    /// Name → metatype, for the runner to instantiate a lane-`read` command via its no-arg `init()`.
    static let typesByName: [String: any Message.Type] = {
        var map: [String: any Message.Type] = [:]
        for t in messageTypes { map[String(describing: t)] = t }
        return map
    }()

    /// A ready-to-send instance of a lane-`read` command (empty cargo). Returns nil for a name that is not
    /// a known read — the runner never fabricates a parameterized delivery/write instance this way.
    public static func makeReadInstance(_ name: String) -> Message? {
        guard let cmd = all.first(where: { $0.name == name }), cmd.lane == .read,
              let type = typesByName[name] else { return nil }
        return type.init()
    }

    // MARK: - Empirically firmware-unsupported commands (bench-observed op-77 rejections)
    //
    // Some commands a pump's firmware does NOT implement answer with an op-77 ErrorResponse and then DROP
    // the BLE link (validated on hardware: a legacy API-2.5 t:slim). That is a firmware-CAPABILITY signal,
    // not a defect in the command — so the coverage classifier records these `deferred` (coverable on a
    // firmware that accepts them) and, crucially, the runner NEVER SENDS one to a firmware known to reject
    // it, so a single sweep is not torn down by a cascade of reject→disconnect→re-pair cycles that
    // eventually exhausts the reconnect ladder.
    //
    // This table is BENCH-LAYER ONLY and deliberately NOT `MessageProps.minApi`: an op-77 on ONE pump is an
    // empirical fact for THAT (model, firmware), not a proven monotonic API floor for the whole fleet (e.g.
    // Basal-IQ ops are feature-gated, not version-gated), and `minApi` feeds the SHIPPING send-gate
    // (`isSupported(onModel:apiVersion:)`) — which must not shift on a single bench observation. Each entry
    // is a pure FACT: "on <model> at API ≤ <maxApiInclusive>, <command> answered op-77 on the saline bench."
    public struct BenchFirmwareUnsupported: Sendable {
        public let model: PumpModel
        /// Inclusive API ceiling this observation applies to (a pump at or below this API rejects the command).
        public let maxApiInclusive: ApiVersion
        public let commands: Set<String>
        /// Where/when this was observed — carried into the matrix note so nothing is asserted without provenance.
        public let provenance: String
    }

    /// Commands empirically observed to op-77 + drop-link on a given (model, firmware ≤ api). Grows as bench
    /// sessions on other configs surface more; keep each entry a measured fact, never a guess.
    public static let benchObservedUnsupported: [BenchFirmwareUnsupported] = [
        BenchFirmwareUnsupported(
            model: .tslim, maxApiInclusive: .v2_5,
            commands: [
                "LoadStatusRequest", "ExtendedBolusStatusV2Request", "TempRateStatusRequest",
                "BasalIQStatusRequest", "BasalIQSettingsRequest", "BasalIQAlertInfoRequest",
                "BleSoftwareInfoRequest", "SecretMenuRequest", "HistoryLogRequest", "IDPSettingsRequest",
            ],
            provenance: "op-77 reject observed on the tslim API 2.5 saline bench, 2026-08-23 (T-1)"),
    ]

    /// If `command` is bench-observed to be rejected on `model` at `api`, return a note explaining why it is
    /// deferred; else nil. Pure + unit-tested; consulted by `BenchCoverage.plan` so the runner never sends a
    /// firmware-rejecting opcode (which would op-77 + tear down the link).
    public static func firmwareUnsupportedNote(command: String, model: PumpModel, api: ApiVersion) -> String? {
        for entry in benchObservedUnsupported
            where entry.model == model && api <= entry.maxApiInclusive && entry.commands.contains(command) {
            return "bench-observed op-77 reject on \(BenchSessionConfig.name(for: model)) API ≤ "
                + "\(entry.maxApiInclusive.major).\(entry.maxApiInclusive.minor) — deferred pending a firmware "
                + "that accepts it (\(entry.provenance))"
        }
        return nil
    }

    // MARK: - Convenience slices (used by tests + the runner's summary)

    /// Every delivery-class command (`modifiesInsulinDelivery: true`). Per prior research this is exactly
    /// 14: 3 UNIVERSAL + 11 Mobi-only.
    public static var deliveryCommands: [BenchCommand] { all.filter { $0.modifiesDelivery } }

    /// The 11 Mobi-only delivery commands — the ones a Mobi bench session is REQUIRED to cover.
    public static var mobiOnlyDeliveryCommands: [BenchCommand] {
        deliveryCommands.filter { $0.applicablePumpModels == [.mobi] }
    }

    /// The 3 universal delivery commands (drivable on both t:slim and Mobi).
    public static var universalDeliveryCommands: [BenchCommand] {
        deliveryCommands.filter { $0.applicablePumpModels.contains(.tslim) && $0.applicablePumpModels.contains(.mobi) }
    }
}
