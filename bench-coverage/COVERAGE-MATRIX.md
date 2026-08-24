# TandemKit bench command-coverage matrix

_Generated 2026-08-24T01:04:21Z · schema v1 · 625 recorded cells across 3 session config(s)._

This matrix accumulates ACROSS bench sessions. Each session fills only the cells its hardware config (pump model × firmware × cartridge × CGM) allows; the rest stay `deferred` (coverable later) or `n/a` (another model's matrix). A delivery cell PASSES only when the pump's OWN history-log read-back equals the requested units.

## Summary (rolled up per model × firmware × command)

| state | count |
|---|---|
| `gap` | 56 |
| `notApplicable` | 32 |
| `deferred` | 46 |
| `untested` | 241 |

## Coverage by session config

| model | firmware | command | lane | best | detail |
|---|---|---|---|---|---|
| mobi | API 3.6 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | MANUAL — activates shelf/storage mode — takes the pump offline; owner decides at the bench, never auto-fired |
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
| mobi | API 3.6 | `BolusPermissionReleaseRequest` | signedWrite | 🚫 `gap` | restore-half of the BolusPermissionRequest reversible pair — recorded when that pair runs behind the saline gate |
| mobi | API 3.6 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CGMGlucoseAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMOORAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMRateAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CGMStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CancelBolusRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CentralChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| mobi | API 3.6 | `CgmHighLowAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CgmOutOfRangeAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CgmRiseFallAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `CgmStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `ChangeControlIQSettingsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `ChangeTimeDateRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
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
| mobi | API 3.6 | `DisconnectPumpRequest` | signedWrite | 🚫 `gap` | MANUAL — force-disconnects the BLE session — drops the link the sweep needs; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `EnterChangeCartridgeModeRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `EnterFillTubingModeRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterChangeCartridgeModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| mobi | API 3.6 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterFillTubingModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| mobi | API 3.6 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state (B variant) — irreversible; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state — irreversible; owner decides at the bench, never auto-fired |
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
| mobi | API 3.6 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | context step inside the EnterFillTubingModeRequest workflow — recorded when that (saline-gated) workflow runs |
| mobi | API 3.6 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| mobi | API 3.6 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `RemoteBgEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `RemoteCarbEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `RenameIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `ResumePumpingRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | MANUAL — undocumented internal test op — effect unknown; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `SetActiveIDPRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SetAutoOffAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only the high/low BG thresholds, NOT the per-reminder enabled/minutes/type the write sets, so a no-op cannot be verified for the functional fields |
| mobi | API 3.6 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | MANUAL — changes the G7 pairing code — disrupts the sensor pairing; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `SetG6TransmitterIdRequest` | signedWrite | 🚫 `gap` | MANUAL — changes the paired CGM transmitter id — disrupts the sensor pairing; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `SetIDPSegmentRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — edits a LIVE basal/delivery profile segment (basal rate, carb ratio, ISF, target); IDPSegment does not expose profileIndex and the operation selector must be MODIFY — a mis-map silently rewrites the dose-path profile, so it is not auto-fired |
| mobi | API 3.6 | `SetIDPSettingsRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — edits live insulin-duration (IOB/dose-path) + carb-entry; IDPSettings does not expose profileIndex and the changeType selector is required — a mis-map silently rewrites a dose-path setting, so it is not auto-fired |
| mobi | API 3.6 | `SetLowInsulinAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `SetMaxBasalLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `SetMaxBolusLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes none of this write's fields (index/enabled/window/days), so a no-op cannot be verified |
| mobi | API 3.6 | `SetModesRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — no read-back exposes the snooze enabled/duration setting, so it is genuinely unrecoverable — cannot be made a verifiable no-op |
| mobi | API 3.6 | `SetPumpSoundsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| mobi | API 3.6 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — the write's 5-byte increment `magic` must EXACTLY match a known QuickBolusIncrement enum and the modeRaw↔magic mapping is not exposed by PumpGlobals; no change-bitmask to guarantee a no-op — echoing could alter the increment |
| mobi | API 3.6 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | MANUAL — switches the CGM sensor type — disrupts the active sensor; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only siteChangeDays, NOT the write's enable/timeOfDay, so a no-op cannot be verified |
| mobi | API 3.6 | `SetSleepScheduleRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — ControlIQSleepSchedule exposes the 6 schedule bytes per slot but NOT the write's trailing `flag` byte, which has no documented semantics and no read-back — re-applying it cannot be proven a no-op (Mobi-only, Control-IQ-sleep-affecting) |
| mobi | API 3.6 | `SetTempRateRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — starts a CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — stops the CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| mobi | API 3.6 | `StopTempRateRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs mobi firmware on API ≥ 99.99 |
| mobi | API 3.6 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `SuspendPumpingRequest` | delivery | • `untested` | exercisable (lane: delivery) |
| mobi | API 3.6 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `UnknownMobiOpcode110Request` | read | • `untested` | exercisable (lane: read) |
| mobi | API 3.6 | `UserInteractionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | MANUAL — activates shelf/storage mode — takes the pump offline; owner decides at the bench, never auto-fired |
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
| tslim | API 2.5 | `BolusPermissionReleaseRequest` | signedWrite | 🚫 `gap` | restore-half of the BolusPermissionRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 2.5 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `CGMGlucoseAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMHardwareInfoRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMOORAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMRateAlertSettingsRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CGMStatusRequest` | read | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CancelBolusRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `CentralChallengeRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 2.5 | `CgmHighLowAlertRequest` | signedWrite | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CgmOutOfRangeAlertRequest` | signedWrite | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CgmRiseFallAlertRequest` | signedWrite | ⏳ `deferred` | needs a CGM-present session (PUMP_CGM_PRESENT=1) |
| tslim | API 2.5 | `CgmStatusV2Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `ChangeControlIQSettingsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `ChangeTimeDateRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
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
| tslim | API 2.5 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterChangeCartridgeModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 2.5 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterFillTubingModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 2.5 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state (B variant) — irreversible; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state — irreversible; owner decides at the bench, never auto-fired |
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
| tslim | API 2.5 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | context step inside the EnterFillTubingModeRequest workflow — recorded when that (saline-gated) workflow runs |
| tslim | API 2.5 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpChallengeRequest` | pairing | • `untested` | exercisable (lane: pairing) |
| tslim | API 2.5 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `RemoteBgEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `RemoteCarbEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `RenameIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `ResumePumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | MANUAL — undocumented internal test op — effect unknown; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `SetActiveIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetAutoOffAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only the high/low BG thresholds, NOT the per-reminder enabled/minutes/type the write sets, so a no-op cannot be verified for the functional fields |
| tslim | API 2.5 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | MANUAL — changes the G7 pairing code — disrupts the sensor pairing; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `SetG6TransmitterIdRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 2.5 | `SetIDPSegmentRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetIDPSettingsRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetLowInsulinAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `SetMaxBasalLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `SetMaxBolusLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes none of this write's fields (index/enabled/window/days), so a no-op cannot be verified |
| tslim | API 2.5 | `SetModesRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — no read-back exposes the snooze enabled/duration setting, so it is genuinely unrecoverable — cannot be made a verifiable no-op |
| tslim | API 2.5 | `SetPumpSoundsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 2.5 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — the write's 5-byte increment `magic` must EXACTLY match a known QuickBolusIncrement enum and the modeRaw↔magic mapping is not exposed by PumpGlobals; no change-bitmask to guarantee a no-op — echoing could alter the increment |
| tslim | API 2.5 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | MANUAL — switches the CGM sensor type — disrupts the active sensor; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only siteChangeDays, NOT the write's enable/timeOfDay, so a no-op cannot be verified |
| tslim | API 2.5 | `SetSleepScheduleRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `SetTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — starts a CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — stops the CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| tslim | API 2.5 | `StopTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 2.5 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `SuspendPumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 2.5 | `UnknownMobiOpcode110Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 2.5 | `UserInteractionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `ActivateShelfModeRequest` | signedWrite | 🚫 `gap` | MANUAL — activates shelf/storage mode — takes the pump offline; owner decides at the bench, never auto-fired |
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
| tslim | API 3.4 | `BolusPermissionReleaseRequest` | signedWrite | 🚫 `gap` | restore-half of the BolusPermissionRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 3.4 | `BolusPermissionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CGMGlucoseAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMHardwareInfoRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMOORAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMRateAlertSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CGMStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `CancelBolusRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CentralChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| tslim | API 3.4 | `CgmHighLowAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CgmOutOfRangeAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CgmRiseFallAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `CgmStatusV2Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `CgmSupportPackageStatusRequest` | read | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `ChangeControlIQSettingsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `ChangeTimeDateRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
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
| tslim | API 3.4 | `ExitChangeCartridgeModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterChangeCartridgeModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 3.4 | `ExitFillTubingModeRequest` | signedWrite | 🚫 `gap` | restore-half of the EnterFillTubingModeRequest reversible pair — recorded when that pair runs behind the saline gate |
| tslim | API 3.4 | `ExtendedBolusStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `ExtendedBolusStatusV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `FactoryResetBRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state (B variant) — irreversible; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `FactoryResetRequest` | signedWrite | 🚫 `gap` | MANUAL — ERASES the pump to factory state — irreversible; owner decides at the bench, never auto-fired |
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
| tslim | API 3.4 | `PrimeTubingSuspendRequest` | signedWrite | 🚫 `gap` | context step inside the EnterFillTubingModeRequest workflow — recorded when that (saline-gated) workflow runs |
| tslim | API 3.4 | `ProfileStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpChallengeRequest` | pairing | ⏳ `deferred` | needs a legacyV1-pairing session |
| tslim | API 3.4 | `PumpFeaturesV1Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpFeaturesV2Request` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpGlobalsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpSettingsRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpVersionBRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `PumpVersionRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `RemindersRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `RemoteBgEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `RemoteCarbEntryRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `RenameIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `ResumePumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SecretMenuRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `SendTipsControlGenericTestRequest` | signedWrite | 🚫 `gap` | MANUAL — undocumented internal test op — effect unknown; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `SetActiveIDPRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetAutoOffAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `SetBgReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only the high/low BG thresholds, NOT the per-reminder enabled/minutes/type the write sets, so a no-op cannot be verified for the functional fields |
| tslim | API 3.4 | `SetDexcomG7PairingCodeRequest` | signedWrite | 🚫 `gap` | MANUAL — changes the G7 pairing code — disrupts the sensor pairing; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `SetG6TransmitterIdRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 3.5 |
| tslim | API 3.4 | `SetIDPSegmentRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetIDPSettingsRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetLowInsulinAlertRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `SetMaxBasalLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `SetMaxBolusLimitRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `SetMissedMealBolusReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes none of this write's fields (index/enabled/window/days), so a no-op cannot be verified |
| tslim | API 3.4 | `SetModesRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetPumpAlertSnoozeRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — no read-back exposes the snooze enabled/duration setting, so it is genuinely unrecoverable — cannot be made a verifiable no-op |
| tslim | API 3.4 | `SetPumpSoundsRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |
| tslim | API 3.4 | `SetQuickBolusSettingsRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — the write's 5-byte increment `magic` must EXACTLY match a known QuickBolusIncrement enum and the modeRaw↔magic mapping is not exposed by PumpGlobals; no change-bitmask to guarantee a no-op — echoing could alter the increment |
| tslim | API 3.4 | `SetSensorTypeRequest` | signedWrite | 🚫 `gap` | MANUAL — switches the CGM sensor type — disrupts the active sensor; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `SetSiteChangeReminderRequest` | signedWrite | 🚫 `gap` | reversible affordance pending — Reminders exposes only siteChangeDays, NOT the write's enable/timeOfDay, so a no-op cannot be verified |
| tslim | API 3.4 | `SetSleepScheduleRequest` | signedWrite | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `SetTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `StartDexcomG6SensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — starts a CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `StopDexcomCGMSensorSessionRequest` | signedWrite | 🚫 `gap` | MANUAL — stops the CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired |
| tslim | API 3.4 | `StopTempRateRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `StreamDataPreflightRequest` | signedWrite | ⏳ `deferred` | needs tslim firmware on API ≥ 99.99 |
| tslim | API 3.4 | `StreamDataReadinessRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `SuspendPumpingRequest` | delivery | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `TempRateRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `TempRateStatusRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `TimeSinceResetRequest` | read | • `untested` | exercisable (lane: read) |
| tslim | API 3.4 | `UnknownMobiOpcode110Request` | read | ➖ `notApplicable` | model-restricted to mobi — covered in a mobi session |
| tslim | API 3.4 | `UserInteractionRequest` | signedWrite | • `untested` | exercisable (lane: signedWrite) |

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
  - `BolusPermissionRequest` (mobi/API 3.6, untested)
  - `BolusPermissionRequest` (tslim/API 2.5, untested)
  - `BolusPermissionRequest` (tslim/API 3.4, untested)
  - `CancelBolusRequest` (mobi/API 3.6, untested)
  - `CancelBolusRequest` (tslim/API 2.5, untested)
  - `CancelBolusRequest` (tslim/API 3.4, untested)
  - `CgmHighLowAlertRequest` (mobi/API 3.6, untested)
  - `CgmHighLowAlertRequest` (tslim/API 3.4, untested)
  - `CgmOutOfRangeAlertRequest` (mobi/API 3.6, untested)
  - `CgmOutOfRangeAlertRequest` (tslim/API 3.4, untested)
  - `CgmRiseFallAlertRequest` (mobi/API 3.6, untested)
  - `CgmRiseFallAlertRequest` (tslim/API 3.4, untested)
  - `ChangeControlIQSettingsRequest` (mobi/API 3.6, untested)
  - `ChangeControlIQSettingsRequest` (tslim/API 2.5, untested)
  - `ChangeControlIQSettingsRequest` (tslim/API 3.4, untested)
  - `ChangeTimeDateRequest` (mobi/API 3.6, untested)
  - `ChangeTimeDateRequest` (tslim/API 2.5, untested)
  - `ChangeTimeDateRequest` (tslim/API 3.4, untested)
  - `PlaySoundRequest` (mobi/API 3.6, untested)
  - `PlaySoundRequest` (tslim/API 2.5, untested)
  - `PlaySoundRequest` (tslim/API 3.4, untested)
  - `RemoteBgEntryRequest` (mobi/API 3.6, untested)
  - `RemoteBgEntryRequest` (tslim/API 2.5, untested)
  - `RemoteBgEntryRequest` (tslim/API 3.4, untested)
  - `RemoteCarbEntryRequest` (mobi/API 3.6, untested)
  - `RemoteCarbEntryRequest` (tslim/API 2.5, untested)
  - `RemoteCarbEntryRequest` (tslim/API 3.4, untested)
  - `SetAutoOffAlertRequest` (mobi/API 3.6, untested)
  - `SetAutoOffAlertRequest` (tslim/API 2.5, untested)
  - `SetAutoOffAlertRequest` (tslim/API 3.4, untested)
  - `SetLowInsulinAlertRequest` (mobi/API 3.6, untested)
  - `SetLowInsulinAlertRequest` (tslim/API 2.5, untested)
  - `SetLowInsulinAlertRequest` (tslim/API 3.4, untested)
  - `SetMaxBasalLimitRequest` (mobi/API 3.6, untested)
  - `SetMaxBasalLimitRequest` (tslim/API 2.5, untested)
  - `SetMaxBasalLimitRequest` (tslim/API 3.4, untested)
  - `SetMaxBolusLimitRequest` (mobi/API 3.6, untested)
  - `SetMaxBolusLimitRequest` (tslim/API 2.5, untested)
  - `SetMaxBolusLimitRequest` (tslim/API 3.4, untested)
  - `SetPumpSoundsRequest` (mobi/API 3.6, untested)
  - `SetPumpSoundsRequest` (tslim/API 2.5, untested)
  - `SetPumpSoundsRequest` (tslim/API 3.4, untested)
  - `UserInteractionRequest` (mobi/API 3.6, untested)
  - `UserInteractionRequest` (tslim/API 2.5, untested)
  - `UserInteractionRequest` (tslim/API 3.4, untested)
- **needs a CGM-present session (PUMP_CGM_PRESENT=1)**
  - `CGMGlucoseAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMHardwareInfoRequest` (tslim/API 2.5, deferred)
  - `CGMOORAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMRateAlertSettingsRequest` (tslim/API 2.5, deferred)
  - `CGMStatusRequest` (tslim/API 2.5, deferred)
  - `CgmHighLowAlertRequest` (tslim/API 2.5, deferred)
  - `CgmOutOfRangeAlertRequest` (tslim/API 2.5, deferred)
  - `CgmRiseFallAlertRequest` (tslim/API 2.5, deferred)
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

## Not auto-fired (manual / owner-judgment at the bench)

- **MANUAL — ERASES the pump to factory state (B variant) — irreversible; owner decides at the bench, never auto-fired**
  - `FactoryResetBRequest` (mobi/API 3.6)
  - `FactoryResetBRequest` (tslim/API 2.5)
  - `FactoryResetBRequest` (tslim/API 3.4)
- **MANUAL — ERASES the pump to factory state — irreversible; owner decides at the bench, never auto-fired**
  - `FactoryResetRequest` (mobi/API 3.6)
  - `FactoryResetRequest` (tslim/API 2.5)
  - `FactoryResetRequest` (tslim/API 3.4)
- **MANUAL — activates shelf/storage mode — takes the pump offline; owner decides at the bench, never auto-fired**
  - `ActivateShelfModeRequest` (mobi/API 3.6)
  - `ActivateShelfModeRequest` (tslim/API 2.5)
  - `ActivateShelfModeRequest` (tslim/API 3.4)
- **MANUAL — changes the G7 pairing code — disrupts the sensor pairing; owner decides at the bench, never auto-fired**
  - `SetDexcomG7PairingCodeRequest` (mobi/API 3.6)
  - `SetDexcomG7PairingCodeRequest` (tslim/API 2.5)
  - `SetDexcomG7PairingCodeRequest` (tslim/API 3.4)
- **MANUAL — changes the paired CGM transmitter id — disrupts the sensor pairing; owner decides at the bench, never auto-fired**
  - `SetG6TransmitterIdRequest` (mobi/API 3.6)
- **MANUAL — force-disconnects the BLE session — drops the link the sweep needs; owner decides at the bench, never auto-fired**
  - `DisconnectPumpRequest` (mobi/API 3.6)
- **MANUAL — starts a CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired**
  - `StartDexcomG6SensorSessionRequest` (mobi/API 3.6)
  - `StartDexcomG6SensorSessionRequest` (tslim/API 2.5)
  - `StartDexcomG6SensorSessionRequest` (tslim/API 3.4)
- **MANUAL — stops the CGM sensor session — disrupts an in-progress sensor; owner decides at the bench, never auto-fired**
  - `StopDexcomCGMSensorSessionRequest` (mobi/API 3.6)
  - `StopDexcomCGMSensorSessionRequest` (tslim/API 2.5)
  - `StopDexcomCGMSensorSessionRequest` (tslim/API 3.4)
- **MANUAL — switches the CGM sensor type — disrupts the active sensor; owner decides at the bench, never auto-fired**
  - `SetSensorTypeRequest` (mobi/API 3.6)
  - `SetSensorTypeRequest` (tslim/API 2.5)
  - `SetSensorTypeRequest` (tslim/API 3.4)
- **MANUAL — undocumented internal test op — effect unknown; owner decides at the bench, never auto-fired**
  - `SendTipsControlGenericTestRequest` (mobi/API 3.6)
  - `SendTipsControlGenericTestRequest` (tslim/API 2.5)
  - `SendTipsControlGenericTestRequest` (tslim/API 3.4)
- **context step inside the EnterFillTubingModeRequest workflow — recorded when that (saline-gated) workflow runs**
  - `PrimeTubingSuspendRequest` (mobi/API 3.6)
  - `PrimeTubingSuspendRequest` (tslim/API 2.5)
  - `PrimeTubingSuspendRequest` (tslim/API 3.4)
- **restore-half of the BolusPermissionRequest reversible pair — recorded when that pair runs behind the saline gate**
  - `BolusPermissionReleaseRequest` (mobi/API 3.6)
  - `BolusPermissionReleaseRequest` (tslim/API 2.5)
  - `BolusPermissionReleaseRequest` (tslim/API 3.4)
- **restore-half of the EnterChangeCartridgeModeRequest reversible pair — recorded when that pair runs behind the saline gate**
  - `ExitChangeCartridgeModeRequest` (mobi/API 3.6)
  - `ExitChangeCartridgeModeRequest` (tslim/API 2.5)
  - `ExitChangeCartridgeModeRequest` (tslim/API 3.4)
- **restore-half of the EnterFillTubingModeRequest reversible pair — recorded when that pair runs behind the saline gate**
  - `ExitFillTubingModeRequest` (mobi/API 3.6)
  - `ExitFillTubingModeRequest` (tslim/API 2.5)
  - `ExitFillTubingModeRequest` (tslim/API 3.4)
- **reversible affordance pending — ControlIQSleepSchedule exposes the 6 schedule bytes per slot but NOT the write's trailing `flag` byte, which has no documented semantics and no read-back — re-applying it cannot be proven a no-op (Mobi-only, Control-IQ-sleep-affecting)**
  - `SetSleepScheduleRequest` (mobi/API 3.6)
- **reversible affordance pending — Reminders exposes none of this write's fields (index/enabled/window/days), so a no-op cannot be verified**
  - `SetMissedMealBolusReminderRequest` (mobi/API 3.6)
  - `SetMissedMealBolusReminderRequest` (tslim/API 2.5)
  - `SetMissedMealBolusReminderRequest` (tslim/API 3.4)
- **reversible affordance pending — Reminders exposes only siteChangeDays, NOT the write's enable/timeOfDay, so a no-op cannot be verified**
  - `SetSiteChangeReminderRequest` (mobi/API 3.6)
  - `SetSiteChangeReminderRequest` (tslim/API 2.5)
  - `SetSiteChangeReminderRequest` (tslim/API 3.4)
- **reversible affordance pending — Reminders exposes only the high/low BG thresholds, NOT the per-reminder enabled/minutes/type the write sets, so a no-op cannot be verified for the functional fields**
  - `SetBgReminderRequest` (mobi/API 3.6)
  - `SetBgReminderRequest` (tslim/API 2.5)
  - `SetBgReminderRequest` (tslim/API 3.4)
- **reversible affordance pending — edits a LIVE basal/delivery profile segment (basal rate, carb ratio, ISF, target); IDPSegment does not expose profileIndex and the operation selector must be MODIFY — a mis-map silently rewrites the dose-path profile, so it is not auto-fired**
  - `SetIDPSegmentRequest` (mobi/API 3.6)
- **reversible affordance pending — edits live insulin-duration (IOB/dose-path) + carb-entry; IDPSettings does not expose profileIndex and the changeType selector is required — a mis-map silently rewrites a dose-path setting, so it is not auto-fired**
  - `SetIDPSettingsRequest` (mobi/API 3.6)
- **reversible affordance pending — no read-back exposes the snooze enabled/duration setting, so it is genuinely unrecoverable — cannot be made a verifiable no-op**
  - `SetPumpAlertSnoozeRequest` (mobi/API 3.6)
  - `SetPumpAlertSnoozeRequest` (tslim/API 2.5)
  - `SetPumpAlertSnoozeRequest` (tslim/API 3.4)
- **reversible affordance pending — the write's 5-byte increment `magic` must EXACTLY match a known QuickBolusIncrement enum and the modeRaw↔magic mapping is not exposed by PumpGlobals; no change-bitmask to guarantee a no-op — echoing could alter the increment**
  - `SetQuickBolusSettingsRequest` (mobi/API 3.6)
  - `SetQuickBolusSettingsRequest` (tslim/API 2.5)
  - `SetQuickBolusSettingsRequest` (tslim/API 3.4)
