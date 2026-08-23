# TandemKit bench command-coverage matrix

_Generated 2026-08-23T20:57:06Z · schema v1 · 625 recorded cells across 3 session config(s)._

This matrix accumulates ACROSS bench sessions. Each session fills only the cells its hardware config (pump model × firmware × cartridge × CGM) allows; the rest stay `deferred` (coverable later) or `n/a` (another model's matrix). A delivery cell PASSES only when the pump's OWN history-log read-back equals the requested units.

## Summary (rolled up per model × firmware × command)

| state | count |
|---|---|
| `gap` | 95 |
| `notApplicable` | 32 |
| `deferred` | 43 |
| `untested` | 205 |

## Coverage by session config

| model | firmware | command | lane | best | detail |
|---|---|---|---|---|---|
| mobi | API 3.6 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| mobi | API 3.6 | `ActiveAamBitsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `AdditionalBolusRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `AlarmStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `AlertStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ApiVersionRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BasalIQAlertInfoRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BasalIQSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BasalIQStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BasalLimitSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BleSoftwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BolusCalcDataSnapshotRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `BolusPermissionChangeReasonRequest` | read | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `BolusPermissionReleaseRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CGMGlucoseAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMOORAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMRateAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CancelBolusRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `CentralChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| mobi | API 3.6 | `CgmHighLowAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `CgmOutOfRangeAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `CgmRiseFallAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `CgmStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `ChangeControlIQSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `ChangeTimeDateRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `CommonSoftwareInfoRequest` | read | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `ControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ControlIQInfoV1Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ControlIQInfoV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ControlIQSleepScheduleRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CreateHistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CreateIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `CurrentActiveIdpValuesRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentBasalStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentBatteryV1Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentBatteryV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentEGVGuiDataRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CurrentEgvGuiDataV2Request` | read | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `DeleteIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `DisconnectPumpRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| mobi | API 3.6 | `EnterChangeCartridgeModeRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `EnterFillTubingModeRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| mobi | API 3.6 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| mobi | API 3.6 | `FillCannulaRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `GetG6TransmitterHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `GetSavedG7PairingCodeRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `GlobalMaxBolusSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `HighestAamRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `HistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `HistoryLogStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `HomeScreenMirrorRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `IDPSegmentRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `IDPSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `InitiateBolusRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `InsulinStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `Jpake1aRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| mobi | API 3.6 | `Jpake1bRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| mobi | API 3.6 | `Jpake2Request` | pairing | • `untested` | exercisable (lane: pairing) |
| mobi | API 3.6 | `Jpake3SessionKeyRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| mobi | API 3.6 | `Jpake4KeyConfirmationRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| mobi | API 3.6 | `LastBGRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `LastBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `LastBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `LastBolusStatusV3Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `LoadStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `LocalizationRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `MalfunctionStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `NonControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PlaySoundRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| mobi | API 3.6 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `RemoteBgEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `RemoteCarbEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `RenameIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `ResumePumpingRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetActiveIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SetAutoOffAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetG6TransmitterIdRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetIDPSegmentRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetIDPSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetLowInsulinAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetMaxBasalLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetMaxBolusLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetModesRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetPumpSoundsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetSleepScheduleRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `SetTempRateRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| mobi | API 3.6 | `StopTempRateRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `SuspendPumpingRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `UnknownMobiOpcode110Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `UserInteractionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 2.5 | `ActiveAamBitsRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 2.5 | `AdditionalBolusRequest` | delivery | ⏳ `deferred` | needs a cartridge (saline) session on tslim |
| tslim | API 2.5 | `AlarmStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `AlertStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ApiVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BasalIQAlertInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BasalIQSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BasalIQStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BasalLimitSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BleSoftwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BolusCalcDataSnapshotRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `BolusPermissionChangeReasonRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `BolusPermissionReleaseRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `CGMGlucoseAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMHardwareInfoRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMOORAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMRateAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMStatusRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CancelBolusRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `CentralChallengeRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 2.5 | `CgmHighLowAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `CgmOutOfRangeAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `CgmRiseFallAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `CgmStatusV2Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `ChangeControlIQSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `ChangeTimeDateRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `CommonSoftwareInfoRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `ControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ControlIQInfoV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ControlIQInfoV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ControlIQSleepScheduleRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CreateHistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CreateIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `CurrentActiveIdpValuesRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CurrentBasalStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CurrentBatteryV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CurrentBatteryV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CurrentBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `CurrentEGVGuiDataRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CurrentEgvGuiDataV2Request` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `DeleteIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `DisconnectPumpRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 2.5 | `EnterChangeCartridgeModeRequest` | delivery | ⏳ `deferred` | needs a cartridge (saline) session on tslim |
| tslim | API 2.5 | `EnterFillTubingModeRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 2.5 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 2.5 | `FillCannulaRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `GetG6TransmitterHardwareInfoRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `GetSavedG7PairingCodeRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `GlobalMaxBolusSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `HighestAamRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `HistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `HistoryLogStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `HomeScreenMirrorRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `IDPSegmentRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `IDPSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `InitiateBolusRequest` | delivery | ⏳ `deferred` | needs a cartridge (saline) session on tslim |
| tslim | API 2.5 | `InsulinStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `Jpake1aRequest` | pairing | ⏳ `deferred` | needs a session on API ≥ 3.2 (JPAKE firmware) |
| tslim | API 2.5 | `Jpake1bRequest` | pairing | ⏳ `deferred` | needs a session on API ≥ 3.2 (JPAKE firmware) |
| tslim | API 2.5 | `Jpake2Request` | pairing | ⏳ `deferred` | needs a session on API ≥ 3.2 (JPAKE firmware) |
| tslim | API 2.5 | `Jpake3SessionKeyRequest` | pairing | ⏳ `deferred` | needs a session on API ≥ 3.2 (JPAKE firmware) |
| tslim | API 2.5 | `Jpake4KeyConfirmationRequest` | pairing | ⏳ `deferred` | needs a session on API ≥ 3.2 (JPAKE firmware) |
| tslim | API 2.5 | `LastBGRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `LastBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `LastBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `LastBolusStatusV3Request` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 2.5 | `LoadStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `LocalizationRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `MalfunctionStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `NonControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PlaySoundRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpChallengeRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 2.5 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `RemoteBgEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `RemoteCarbEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `RenameIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `ResumePumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetActiveIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetAutoOffAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetG6TransmitterIdRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 2.5 | `SetIDPSegmentRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetIDPSettingsRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetLowInsulinAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetMaxBasalLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetMaxBolusLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetModesRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetPumpSoundsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `SetSleepScheduleRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 2.5 | `StopTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `SuspendPumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `UnknownMobiOpcode110Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `UserInteractionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 3.4 | `ActiveAamBitsRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 3.4 | `AdditionalBolusRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| tslim | API 3.4 | `AlarmStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `AlertStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ApiVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BasalIQAlertInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BasalIQSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BasalIQStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BasalLimitSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BleSoftwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BolusCalcDataSnapshotRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `BolusPermissionChangeReasonRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `BolusPermissionReleaseRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CGMGlucoseAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMOORAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMRateAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CancelBolusRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `CentralChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| tslim | API 3.4 | `CgmHighLowAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `CgmOutOfRangeAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `CgmRiseFallAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `CgmStatusV2Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `ChangeControlIQSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `ChangeTimeDateRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `CommonSoftwareInfoRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `ControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ControlIQInfoV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ControlIQInfoV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ControlIQSleepScheduleRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CreateHistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CreateIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `CurrentActiveIdpValuesRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentBasalStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentBatteryV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentBatteryV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentEGVGuiDataRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CurrentEgvGuiDataV2Request` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `DeleteIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `DisconnectPumpRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 3.4 | `EnterChangeCartridgeModeRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| tslim | API 3.4 | `EnterFillTubingModeRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 3.4 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | destructive command — never auto-fired on a bench pump |
| tslim | API 3.4 | `FillCannulaRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `GetG6TransmitterHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `GetSavedG7PairingCodeRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `GlobalMaxBolusSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `HighestAamRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `HistoryLogRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `HistoryLogStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `HomeScreenMirrorRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `IDPSegmentRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `IDPSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `InitiateBolusRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| tslim | API 3.4 | `InsulinStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `Jpake1aRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 3.4 | `Jpake1bRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 3.4 | `Jpake2Request` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 3.4 | `Jpake3SessionKeyRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 3.4 | `Jpake4KeyConfirmationRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 3.4 | `LastBGRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `LastBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `LastBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `LastBolusStatusV3Request` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 3.4 | `LoadStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `LocalizationRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `MalfunctionStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `NonControlIQIOBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PlaySoundRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| tslim | API 3.4 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `RemoteBgEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `RemoteCarbEntryRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `RenameIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `ResumePumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetActiveIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetAutoOffAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetG6TransmitterIdRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 3.4 | `SetIDPSegmentRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetIDPSettingsRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetLowInsulinAlertRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetMaxBasalLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetMaxBolusLimitRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetModesRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetPumpSoundsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `SetSleepScheduleRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |
| tslim | API 3.4 | `StopTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `SuspendPumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `UnknownMobiOpcode110Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `UserInteractionRequest` | signedWrite | 🚫 `gap` | state-mutating signed write — no auto-fired reversible affordance; drive via the curated `probe` subcommand |

## Still uncovered — and the session config that would cover it

- **exercisable (lane: delivery)**
  - `AdditionalBolusRequest` (mobi/API 3.6, untested)
  - `AdditionalBolusRequest` (tslim/API 3.4, untested)
  - `CreateIDPRequest` (mobi/API 3.6, untested)
  - `DeleteIDPRequest` (mobi/API 3.6, untested)
  - `EnterChangeCartridgeModeRequest` (mobi/API 3.6, untested)
  - `EnterChangeCartridgeModeRequest` (tslim/API 3.4, untested)
  - `EnterFillTubingModeRequest` (mobi/API 3.6, untested)
  - `FillCannulaRequest` (mobi/API 3.6, untested)
  - `InitiateBolusRequest` (mobi/API 3.6, untested)
  - `InitiateBolusRequest` (tslim/API 3.4, untested)
  - `RenameIDPRequest` (mobi/API 3.6, untested)
  - `ResumePumpingRequest` (mobi/API 3.6, untested)
  - `SetActiveIDPRequest` (mobi/API 3.6, untested)
  - `SetModesRequest` (mobi/API 3.6, untested)
  - `SetTempRateRequest` (mobi/API 3.6, untested)
  - `StopTempRateRequest` (mobi/API 3.6, untested)
  - `SuspendPumpingRequest` (mobi/API 3.6, untested)
- **exercisable (lane: pairing)**
  - `CentralChallengeRequest` (tslim/API 2.5, untested)
  - `Jpake1aRequest` (mobi/API 3.6, untested)
  - `Jpake1aRequest` (tslim/API 3.4, untested)
  - `Jpake1bRequest` (mobi/API 3.6, untested)
  - `Jpake1bRequest` (tslim/API 3.4, untested)
  - `Jpake2Request` (mobi/API 3.6, untested)
  - `Jpake2Request` (tslim/API 3.4, untested)
  - `Jpake3SessionKeyRequest` (mobi/API 3.6, untested)
  - `Jpake3SessionKeyRequest` (tslim/API 3.4, untested)
  - `Jpake4KeyConfirmationRequest` (mobi/API 3.6, untested)
  - `Jpake4KeyConfirmationRequest` (tslim/API 3.4, untested)
  - `PumpChallengeRequest` (tslim/API 2.5, untested)
- **exercisable (lane: read)**
  - `ActiveAamBitsRequest` (mobi/API 3.6, untested)
  - `AlarmStatusRequest` (mobi/API 3.6, untested)
  - `AlarmStatusRequest` (tslim/API 2.5, untested)
  - `AlarmStatusRequest` (tslim/API 3.4, untested)
  - `AlertStatusRequest` (mobi/API 3.6, untested)
  - `AlertStatusRequest` (tslim/API 2.5, untested)
  - `AlertStatusRequest` (tslim/API 3.4, untested)
  - `ApiVersionRequest` (mobi/API 3.6, untested)
  - `ApiVersionRequest` (tslim/API 2.5, untested)
  - `ApiVersionRequest` (tslim/API 3.4, untested)
  - `BasalIQAlertInfoRequest` (mobi/API 3.6, untested)
  - `BasalIQAlertInfoRequest` (tslim/API 2.5, untested)
  - `BasalIQAlertInfoRequest` (tslim/API 3.4, untested)
  - `BasalIQSettingsRequest` (mobi/API 3.6, untested)
  - `BasalIQSettingsRequest` (tslim/API 2.5, untested)
  - `BasalIQSettingsRequest` (tslim/API 3.4, untested)
  - `BasalIQStatusRequest` (mobi/API 3.6, untested)
  - `BasalIQStatusRequest` (tslim/API 2.5, untested)
  - `BasalIQStatusRequest` (tslim/API 3.4, untested)
  - `BasalLimitSettingsRequest` (mobi/API 3.6, untested)
  - `BasalLimitSettingsRequest` (tslim/API 2.5, untested)
  - `BasalLimitSettingsRequest` (tslim/API 3.4, untested)
  - `BleSoftwareInfoRequest` (mobi/API 3.6, untested)
  - `BleSoftwareInfoRequest` (tslim/API 2.5, untested)
  - `BleSoftwareInfoRequest` (tslim/API 3.4, untested)
  - `BolusCalcDataSnapshotRequest` (mobi/API 3.6, untested)
  - `BolusCalcDataSnapshotRequest` (tslim/API 2.5, untested)
  - `BolusCalcDataSnapshotRequest` (tslim/API 3.4, untested)
  - `CGMGlucoseAlertSettingsRequest` (mobi/API 3.6, untested)
  - `CGMGlucoseAlertSettingsRequest` (tslim/API 3.4, untested)
  - `CGMHardwareInfoRequest` (mobi/API 3.6, untested)
  - `CGMHardwareInfoRequest` (tslim/API 3.4, untested)
  - `CGMOORAlertSettingsRequest` (mobi/API 3.6, untested)
  - `CGMOORAlertSettingsRequest` (tslim/API 3.4, untested)
  - `CGMRateAlertSettingsRequest` (mobi/API 3.6, untested)
  - `CGMRateAlertSettingsRequest` (tslim/API 3.4, untested)
  - `CGMStatusRequest` (mobi/API 3.6, untested)
  - `CGMStatusRequest` (tslim/API 3.4, untested)
  - `CgmStatusV2Request` (mobi/API 3.6, untested)
  - `ControlIQIOBRequest` (mobi/API 3.6, untested)
  - `ControlIQIOBRequest` (tslim/API 2.5, untested)
  - `ControlIQIOBRequest` (tslim/API 3.4, untested)
  - `ControlIQInfoV1Request` (mobi/API 3.6, untested)
  - `ControlIQInfoV1Request` (tslim/API 2.5, untested)
  - `ControlIQInfoV1Request` (tslim/API 3.4, untested)
  - `ControlIQInfoV2Request` (mobi/API 3.6, untested)
  - `ControlIQInfoV2Request` (tslim/API 2.5, untested)
  - `ControlIQInfoV2Request` (tslim/API 3.4, untested)
  - `ControlIQSleepScheduleRequest` (mobi/API 3.6, untested)
  - `ControlIQSleepScheduleRequest` (tslim/API 2.5, untested)
  - `ControlIQSleepScheduleRequest` (tslim/API 3.4, untested)
  - `CreateHistoryLogRequest` (mobi/API 3.6, untested)
  - `CreateHistoryLogRequest` (tslim/API 2.5, untested)
  - `CreateHistoryLogRequest` (tslim/API 3.4, untested)
  - `CurrentActiveIdpValuesRequest` (mobi/API 3.6, untested)
  - `CurrentActiveIdpValuesRequest` (tslim/API 2.5, untested)
  - `CurrentActiveIdpValuesRequest` (tslim/API 3.4, untested)
  - `CurrentBasalStatusRequest` (mobi/API 3.6, untested)
  - `CurrentBasalStatusRequest` (tslim/API 2.5, untested)
  - `CurrentBasalStatusRequest` (tslim/API 3.4, untested)
  - `CurrentBatteryV1Request` (mobi/API 3.6, untested)
  - `CurrentBatteryV1Request` (tslim/API 2.5, untested)
  - `CurrentBatteryV1Request` (tslim/API 3.4, untested)
  - `CurrentBatteryV2Request` (mobi/API 3.6, untested)
  - `CurrentBatteryV2Request` (tslim/API 2.5, untested)
  - `CurrentBatteryV2Request` (tslim/API 3.4, untested)
  - `CurrentBolusStatusRequest` (mobi/API 3.6, untested)
  - `CurrentBolusStatusRequest` (tslim/API 2.5, untested)
  - `CurrentBolusStatusRequest` (tslim/API 3.4, untested)
  - `CurrentEGVGuiDataRequest` (mobi/API 3.6, untested)
  - `CurrentEGVGuiDataRequest` (tslim/API 3.4, untested)
  - `ExtendedBolusStatusRequest` (mobi/API 3.6, untested)
  - `ExtendedBolusStatusRequest` (tslim/API 2.5, untested)
  - `ExtendedBolusStatusRequest` (tslim/API 3.4, untested)
  - `ExtendedBolusStatusV2Request` (mobi/API 3.6, untested)
  - `ExtendedBolusStatusV2Request` (tslim/API 2.5, untested)
  - `ExtendedBolusStatusV2Request` (tslim/API 3.4, untested)
  - `GetG6TransmitterHardwareInfoRequest` (mobi/API 3.6, untested)
  - `GetG6TransmitterHardwareInfoRequest` (tslim/API 3.4, untested)
  - `GetSavedG7PairingCodeRequest` (mobi/API 3.6, untested)
  - `GetSavedG7PairingCodeRequest` (tslim/API 3.4, untested)
  - `GlobalMaxBolusSettingsRequest` (mobi/API 3.6, untested)
  - `GlobalMaxBolusSettingsRequest` (tslim/API 2.5, untested)
  - `GlobalMaxBolusSettingsRequest` (tslim/API 3.4, untested)
  - `HighestAamRequest` (mobi/API 3.6, untested)
  - `HighestAamRequest` (tslim/API 2.5, untested)
  - `HighestAamRequest` (tslim/API 3.4, untested)
  - `HistoryLogRequest` (mobi/API 3.6, untested)
  - `HistoryLogRequest` (tslim/API 2.5, untested)
  - `HistoryLogRequest` (tslim/API 3.4, untested)
  - `HistoryLogStatusRequest` (mobi/API 3.6, untested)
  - `HistoryLogStatusRequest` (tslim/API 2.5, untested)
  - `HistoryLogStatusRequest` (tslim/API 3.4, untested)
  - `HomeScreenMirrorRequest` (mobi/API 3.6, untested)
  - `HomeScreenMirrorRequest` (tslim/API 2.5, untested)
  - `HomeScreenMirrorRequest` (tslim/API 3.4, untested)
  - `IDPSegmentRequest` (mobi/API 3.6, untested)
  - `IDPSegmentRequest` (tslim/API 2.5, untested)
  - `IDPSegmentRequest` (tslim/API 3.4, untested)
  - `IDPSettingsRequest` (mobi/API 3.6, untested)
  - `IDPSettingsRequest` (tslim/API 2.5, untested)
  - `IDPSettingsRequest` (tslim/API 3.4, untested)
  - `InsulinStatusRequest` (mobi/API 3.6, untested)
  - `InsulinStatusRequest` (tslim/API 2.5, untested)
  - `InsulinStatusRequest` (tslim/API 3.4, untested)
  - `LastBGRequest` (mobi/API 3.6, untested)
  - `LastBGRequest` (tslim/API 2.5, untested)
  - `LastBGRequest` (tslim/API 3.4, untested)
  - `LastBolusStatusRequest` (mobi/API 3.6, untested)
  - `LastBolusStatusRequest` (tslim/API 2.5, untested)
  - `LastBolusStatusRequest` (tslim/API 3.4, untested)
  - `LastBolusStatusV2Request` (mobi/API 3.6, untested)
  - `LastBolusStatusV2Request` (tslim/API 2.5, untested)
  - `LastBolusStatusV2Request` (tslim/API 3.4, untested)
  - `LastBolusStatusV3Request` (mobi/API 3.6, untested)
  - `LoadStatusRequest` (mobi/API 3.6, untested)
  - `LoadStatusRequest` (tslim/API 2.5, untested)
  - `LoadStatusRequest` (tslim/API 3.4, untested)
  - `LocalizationRequest` (mobi/API 3.6, untested)
  - `LocalizationRequest` (tslim/API 2.5, untested)
  - `LocalizationRequest` (tslim/API 3.4, untested)
  - `MalfunctionStatusRequest` (mobi/API 3.6, untested)
  - `MalfunctionStatusRequest` (tslim/API 2.5, untested)
  - `MalfunctionStatusRequest` (tslim/API 3.4, untested)
  - `NonControlIQIOBRequest` (mobi/API 3.6, untested)
  - `NonControlIQIOBRequest` (tslim/API 2.5, untested)
  - `NonControlIQIOBRequest` (tslim/API 3.4, untested)
  - `ProfileStatusRequest` (mobi/API 3.6, untested)
  - `ProfileStatusRequest` (tslim/API 2.5, untested)
  - `ProfileStatusRequest` (tslim/API 3.4, untested)
  - `PumpFeaturesV1Request` (mobi/API 3.6, untested)
  - `PumpFeaturesV1Request` (tslim/API 2.5, untested)
  - `PumpFeaturesV1Request` (tslim/API 3.4, untested)
  - `PumpFeaturesV2Request` (mobi/API 3.6, untested)
  - `PumpFeaturesV2Request` (tslim/API 2.5, untested)
  - `PumpFeaturesV2Request` (tslim/API 3.4, untested)
  - `PumpGlobalsRequest` (mobi/API 3.6, untested)
  - `PumpGlobalsRequest` (tslim/API 2.5, untested)
  - `PumpGlobalsRequest` (tslim/API 3.4, untested)
  - `PumpSettingsRequest` (mobi/API 3.6, untested)
  - `PumpSettingsRequest` (tslim/API 2.5, untested)
  - `PumpSettingsRequest` (tslim/API 3.4, untested)
  - `PumpVersionBRequest` (mobi/API 3.6, untested)
  - `PumpVersionBRequest` (tslim/API 2.5, untested)
  - `PumpVersionBRequest` (tslim/API 3.4, untested)
  - `PumpVersionRequest` (mobi/API 3.6, untested)
  - `PumpVersionRequest` (tslim/API 2.5, untested)
  - `PumpVersionRequest` (tslim/API 3.4, untested)
  - `RemindersRequest` (mobi/API 3.6, untested)
  - `RemindersRequest` (tslim/API 2.5, untested)
  - `RemindersRequest` (tslim/API 3.4, untested)
  - `SecretMenuRequest` (mobi/API 3.6, untested)
  - `SecretMenuRequest` (tslim/API 2.5, untested)
  - `SecretMenuRequest` (tslim/API 3.4, untested)
  - `StreamDataReadinessRequest` (mobi/API 3.6, untested)
  - `StreamDataReadinessRequest` (tslim/API 2.5, untested)
  - `StreamDataReadinessRequest` (tslim/API 3.4, untested)
  - `TempRateRequest` (mobi/API 3.6, untested)
  - `TempRateRequest` (tslim/API 2.5, untested)
  - `TempRateRequest` (tslim/API 3.4, untested)
  - `TempRateStatusRequest` (mobi/API 3.6, untested)
  - `TempRateStatusRequest` (tslim/API 2.5, untested)
  - `TempRateStatusRequest` (tslim/API 3.4, untested)
  - `TimeSinceResetRequest` (mobi/API 3.6, untested)
  - `TimeSinceResetRequest` (tslim/API 2.5, untested)
  - `TimeSinceResetRequest` (tslim/API 3.4, untested)
  - `UnknownMobiOpcode110Request` (mobi/API 3.6, untested)
- **exercisable (lane: signedWrite)**
  - `BolusPermissionReleaseRequest` (mobi/API 3.6, untested)
  - `BolusPermissionReleaseRequest` (tslim/API 2.5, untested)
  - `BolusPermissionReleaseRequest` (tslim/API 3.4, untested)
  - `BolusPermissionRequest` (mobi/API 3.6, untested)
  - `BolusPermissionRequest` (tslim/API 2.5, untested)
  - `BolusPermissionRequest` (tslim/API 3.4, untested)
  - `PlaySoundRequest` (mobi/API 3.6, untested)
  - `PlaySoundRequest` (tslim/API 2.5, untested)
  - `PlaySoundRequest` (tslim/API 3.4, untested)
- **needs a CGM-present session (PUMP_CGM_PRESENT=1)**
  - `CGMGlucoseAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMHardwareInfoRequest` (tslim/API 2.5, deferred)
  - `CGMOORAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMRateAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMStatusRequest` (tslim/API 2.5, deferred)
  - `CurrentEGVGuiDataRequest` (tslim/API 2.5, deferred)
  - `GetG6TransmitterHardwareInfoRequest` (tslim/API 2.5, deferred)
  - `GetSavedG7PairingCodeRequest` (tslim/API 2.5, deferred)
- **needs a cartridge (saline) session on tslim**
  - `AdditionalBolusRequest` (tslim/API 2.5, deferred)
  - `EnterChangeCartridgeModeRequest` (tslim/API 2.5, deferred)
  - `InitiateBolusRequest` (tslim/API 2.5, deferred)
- **needs a legacyV1-pairing session**
  - `CentralChallengeRequest` (mobi/API 3.6, deferred)
  - `CentralChallengeRequest` (tslim/API 3.4, deferred)
  - `PumpChallengeRequest` (mobi/API 3.6, deferred)
  - `PumpChallengeRequest` (tslim/API 3.4, deferred)
- **needs a session on API ≥ 3.2 (JPAKE firmware)**
  - `Jpake1aRequest` (tslim/API 2.5, deferred)
  - `Jpake1bRequest` (tslim/API 2.5, deferred)
  - `Jpake2Request` (tslim/API 2.5, deferred)
  - `Jpake3SessionKeyRequest` (tslim/API 2.5, deferred)
  - `Jpake4KeyConfirmationRequest` (tslim/API 2.5, deferred)
- **needs mobi firmware on API ≥ 99.99**
  - `BolusPermissionChangeReasonRequest` (mobi/API 3.6, deferred)
  - `CgmSupportPackageStatusRequest` (mobi/API 3.6, deferred)
  - `CommonSoftwareInfoRequest` (mobi/API 3.6, deferred)
  - `CurrentEgvGuiDataV2Request` (mobi/API 3.6, deferred)
  - `StreamDataPreflightRequest` (mobi/API 3.6, deferred)
- **needs tslim firmware on API ≥ 3.5**
  - `ActiveAamBitsRequest` (tslim/API 2.5, deferred)
  - `ActiveAamBitsRequest` (tslim/API 3.4, deferred)
  - `DisconnectPumpRequest` (tslim/API 2.5, deferred)
  - `DisconnectPumpRequest` (tslim/API 3.4, deferred)
  - `LastBolusStatusV3Request` (tslim/API 2.5, deferred)
  - `LastBolusStatusV3Request` (tslim/API 3.4, deferred)
  - `SetG6TransmitterIdRequest` (tslim/API 2.5, deferred)
  - `SetG6TransmitterIdRequest` (tslim/API 3.4, deferred)
- **needs tslim firmware on API ≥ 99.99**
  - `BolusPermissionChangeReasonRequest` (tslim/API 2.5, deferred)
  - `BolusPermissionChangeReasonRequest` (tslim/API 3.4, deferred)
  - `CgmSupportPackageStatusRequest` (tslim/API 2.5, deferred)
  - `CgmSupportPackageStatusRequest` (tslim/API 3.4, deferred)
  - `CommonSoftwareInfoRequest` (tslim/API 2.5, deferred)
  - `CommonSoftwareInfoRequest` (tslim/API 3.4, deferred)
  - `CurrentEgvGuiDataV2Request` (tslim/API 2.5, deferred)
  - `CurrentEgvGuiDataV2Request` (tslim/API 3.4, deferred)
  - `StreamDataPreflightRequest` (tslim/API 2.5, deferred)
  - `StreamDataPreflightRequest` (tslim/API 3.4, deferred)
