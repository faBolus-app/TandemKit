// HardwareGate.swift — env-driven gates for the Tier-1 hardware bench harness.
//
// SKIP, NEVER FAIL. Absence of a pump / config flag => the relevant suite or test is SKIPPED (green),
// exactly like the oracle gate `@Suite(.enabled(if: OracleRunner.isAvailable))`
// (`OracleParityTests`). A no-hardware checkout and CI stay green.
//
// SAFETY: the two delivery software walls are NOT touched here — they stay armed at all times
//   (1) `PumpBLEClient.writePolicy` defaults to `.readOnly`
//   (2) the `actionsAffectingInsulinDeliveryEnabled` gate in `Packetize.packetize`
// The harness only ELEVATES a policy for the exact op that needs it, scoped by `withWritePolicy`
// (auto-restores `.readOnly`), and only sets `allowInsulinDelivery` for a delivery-class message.
//
// TWO CONFIGURATION AXES the owner selects by env (both skip-not-fail when a config isn't present):
//   • Cartridge axis — PUMP_CARTRIDGE_LOADED absent = NO cartridge (what the owner has now): only
//     read-only / no-delivery cases run; every delivery case SKIPS. Delivery is enabled only when
//     PUMP_CARTRIDGE_LOADED=1 + PUMP_SALINE_ATTESTED=1 + PUMPX2_DELIVER_SALINE=1.
//   • CGM axis — PUMP_CGM_PRESENT absent = NO CGM (current): pump EGV reads are expected empty/stale
//     and CGM-dependent *app* behavior is out of scope for the pump. PUMP_CGM_PRESENT=1 = a sensor is
//     connected: the CGM read cases run and assert the pump's OWN CGM path reflects a live reading.

import Foundation

/// All env gates for the hardware harness. Every gate is fail-closed: a missing flag disables the
/// corresponding cases (skip), never a false pass.
enum HardwareGate {
    private static func flag(_ key: String) -> Bool {
        ProcessInfo.processInfo.environment[key] == "1"
    }
    private static func value(_ key: String) -> String {
        ProcessInfo.processInfo.environment[key] ?? ""
    }

    /// The 6-digit (or 16-char legacy) pairing code read off the pump screen (H1). Required for any
    /// hardware run; empty => the whole suite skips.
    static var pairingCode: String { value("PUMP_PAIRING_CODE") }

    /// Connectivity gate. Read-only + pairing/reconnect + all reads + capability discovery. Requires a
    /// reachable pump (PUMPX2_HARDWARE=1) and a pairing code. This is the "RUNNABLE NOW" gate — true even
    /// with NO cartridge and NO CGM.
    static var connected: Bool { flag("PUMPX2_HARDWARE") && !pairingCode.isEmpty }

    /// Cartridge axis: a cartridge is physically loaded. Absent => no delivery case may run.
    static var cartridgeLoaded: Bool { flag("PUMP_CARTRIDGE_LOADED") }

    /// Human attestation (on the pump's own screens / t:connect, not the app) that the loaded cartridge
    /// is SALINE — never real insulin, never on a body.
    static var salineAttested: Bool { flag("PUMP_SALINE_ATTESTED") }

    /// CGM axis: a sensor is connected to the pump. Absent => CGM read cases skip; EGV reads are expected
    /// empty/stale.
    static var cgmPresent: Bool { flag("PUMP_CGM_PRESENT") }

    /// Delivery gate (the strictest). A delivery case runs ONLY when connected AND a cartridge is loaded
    /// AND saline is attested AND the explicit deliver flag is set. This is precisely why "never attempt
    /// delivery without a cartridge" holds: no cartridge => `delivery` is false => every delivery case
    /// skips.
    static var delivery: Bool {
        connected && cartridgeLoaded && salineAttested && flag("PUMPX2_DELIVER_SALINE")
    }

    /// OPT-IN no-cartridge rejection probe (its own flag, so it never runs by accident). Deliberately
    /// requires that NO cartridge is loaded — it drives a bolus command through BOTH software walls and
    /// records the pump's rejection; because a cartridge is guaranteed absent it can never dispense.
    static var noCartridgeBolusProbe: Bool {
        connected && flag("PUMPX2_NO_CARTRIDGE_BOLUS_PROBE") && !cartridgeLoaded
    }
}
