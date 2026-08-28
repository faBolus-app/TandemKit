// HardwareCase.swift — declarative bench-case model + the gated runner.
//
// A case is: preconditions (asserted from pump reads, never assumed) → command → expected read-back.
// The runner enforces preconditions, takes a history cursor, runs the command, then `verify` asserts on
// the pump-authoritative read-back (§1). Cases are values in arrays and run via `@Test(arguments:)`, so
// adding a case is one struct literal.
//
// SKIP, NEVER FAIL. The suite is `@Suite(.enabled(if: HardwareGate.connected))` — with no pump it skips.
// Delivery cases carry `.enabled(if: HardwareGate.delivery)`; CGM cases `.enabled(if: HardwareGate.cgmPresent)`
// — so a config that isn't present shows those cases as SKIPPED (green + recorded), never red, and never
// attempts delivery without a cartridge.
//
// ⚠️ HARDWARE (BLE) CASES CANNOT RUN UNDER `swift test` — confirmed on hardware 2026-08-07.
// `swift test` executes tests inside Apple's `swiftpm-testing-helper`, whose process carries no
// `NSBluetoothAlwaysUsageDescription`, so macOS TCC **aborts the process (SIGABRT) at `startScan()`**
// the instant any case touches CoreBluetooth — a plist on the test bundle can't fix it. So with a real
// pump + `PUMPX2_HARDWARE=1`, this suite crashes rather than pairs; without hardware it cleanly SKIPS
// (which is all any "green" run of it has ever exercised). The WORKING hardware path is the
// `TandemBenchHarness` **executable** (its `probe`/`monitor` commands), which embeds the Bluetooth usage
// string into its Mach-O `__TEXT,__info_plist` via a linker flag (see Package.swift) and is run from an
// interactive GUI Terminal. This target remains valuable as the declarative case MODEL + the no-hardware
// gate proof; driving it against real BLE needs an executable/xctest-host with the usage string.

import Foundation
import Testing
import TandemMessages
import TandemAuth
import TandemBLE

// MARK: - Declarative case model

/// A pump precondition the runner READS and enforces before the command runs.
enum Precondition: Sendable {
    /// Control-IQ closed-loop must be in the expected on/off state (`ControlIQInfoV2Response.closedLoopEnabled`).
    case controlIQ(enabled: Bool)
    /// No bolus currently in progress — the inter-case cleanliness gate (`CurrentBolusStatus.statusId == 0`).
    case idle
    /// A SALINE cartridge is loaded + human-attested (env; a read cannot tell saline from insulin).
    case salineCartridge
    /// At least `units` of (saline) fluid remain in the cartridge (`InsulinStatusResponse`).
    case minRemaining(units: Double)
}

/// A single bench case. `command` performs the exchange and returns a correlation id (bolusId/tempRateId,
/// 0 for a read-only case, or `mobiSkipSentinel` for a correct Mobi-only SKIP). `verify` reads the
/// pump-authoritative record and asserts.
struct HardwareCase: Sendable, CustomTestStringConvertible {
    /// Returned by a command when the case is a correct SKIP on this pump (e.g. temp basal is Mobi-only on
    /// a t:slim X2). `verify` treats it as a no-op, so the case passes green representing the SKIP.
    static let mobiSkipSentinel = -1

    let name: String
    let requiresDelivery: Bool
    let requiresCGM: Bool
    let preconditions: [Precondition]
    let command: @Sendable @MainActor (LiveSession) async throws -> Int
    let verify: @Sendable @MainActor (LiveSession, _ correlationId: Int, _ baselineSeq: UInt32) async throws -> Void

    var testDescription: String { name }
}

// MARK: - Precondition enforcement (read + require, from pump-authoritative reads)

enum Preconditions {
    @MainActor
    static func enforce(_ preconditions: [Precondition], on s: LiveSession) async throws {
        for precondition in preconditions {
            switch precondition {
            case .salineCartridge:
                try #require(
                    HardwareGate.cartridgeLoaded && HardwareGate.salineAttested,
                    "precondition: a SALINE cartridge must be loaded + attested (PUMP_CARTRIDGE_LOADED=1, PUMP_SALINE_ATTESTED=1)"
                )
            case .minRemaining(let units):
                let insulin = try await s.request(InsulinStatusRequest(), expect: InsulinStatusResponse.self)
                try #require(
                    Double(insulin.currentInsulinAmount) >= units,
                    "precondition: need >= \(units)u remaining, pump reports \(insulin.currentInsulinAmount)u")
            case .idle:
                let bolus = try await s.request(CurrentBolusStatusRequest(), expect: CurrentBolusStatusResponse.self)
                try #require(
                    bolus.statusId == 0, "precondition: a bolus is already in progress (statusId \(bolus.statusId))")
            case .controlIQ(let enabled):
                let ciq = try await s.request(ControlIQInfoV2Request(), expect: ControlIQInfoV2Response.self)
                try #require(
                    ciq.closedLoopEnabled == enabled,
                    "precondition: Control-IQ must be \(enabled ? "ON" : "OFF") for this case")
            }
        }
    }
}

// MARK: - Shared session (one pairing for the whole suite)

/// One shared, JPAKE-paired session for the whole suite: the human-confirmed pair (H1) happens once; each
/// case takes a fresh history cursor for isolation. The suite is `.serialized`, so `shared()` is entered
/// one call at a time — a plain lazy is sufficient and Sendable-clean (everything stays on the main actor).
@MainActor
enum SharedSession {
    private static var instance: LiveSession?

    static func shared() async throws -> LiveSession {
        if let instance { return instance }
        let session = LiveSession()
        try await session.connectAndPair(code: HardwareGate.pairingCode)
        instance = session
        return session
    }
}

// MARK: - Runner

/// The Tier-1 hardware suite. Whole-suite gate = a reachable, paired pump (RUNNABLE NOW: no cartridge, no
/// CGM). Delivery / CGM cases carry their own runtime gate, so an absent config shows them as SKIPPED.
@Suite(.enabled(if: HardwareGate.connected), .serialized)
@MainActor
struct TandemHardwareTests {

    /// Read-only + pairing/reconnect + capability discovery — runs in EVERY config (this is the
    /// "runnable now" subset the owner can execute today with no cartridge and no CGM).
    @Test(arguments: BenchCases.readOnlyCases)
    func readOnly(_ testCase: HardwareCase) async throws { try await Self.run(testCase) }

    /// Delivery (saline) cases — SKIP unless a cartridge is loaded, saline is attested, and delivery is
    /// explicitly enabled. Never attempts delivery without a cartridge.
    @Test(.enabled(if: HardwareGate.delivery), arguments: BenchCases.deliveryCases)
    func delivery(_ testCase: HardwareCase) async throws { try await Self.run(testCase) }

    /// The pump's OWN CGM read path — SKIP unless a sensor is connected (PUMP_CGM_PRESENT=1).
    @Test(.enabled(if: HardwareGate.cgmPresent), arguments: BenchCases.cgmReadCases)
    func cgm(_ testCase: HardwareCase) async throws { try await Self.run(testCase) }

    @MainActor
    static func run(_ testCase: HardwareCase) async throws {
        let session = try await SharedSession.shared()
        try await Preconditions.enforce(testCase.preconditions, on: session)
        let baseline = try await session.historyCursor()
        let correlationId = try await testCase.command(session)
        try await testCase.verify(session, correlationId, baseline)
    }
}

// MARK: - Opt-in no-cartridge edge case (its own suite + flag; never dispenses)

/// OPT-IN: drive a bolus command through BOTH software walls with NO cartridge loaded and record that the
/// pump rejects it (permission refused, or initiate not accepted, or — defensively — no delivery record
/// ever appears). Gated by `PUMPX2_NO_CARTRIDGE_BOLUS_PROBE=1` AND `!cartridgeLoaded`, so it can never run
/// by accident and can never dispense.
@Suite(.enabled(if: HardwareGate.noCartridgeBolusProbe), .serialized)
@MainActor
struct NoCartridgeBolusProbeTests {
    @Test func bolusWithoutCartridgeIsRejected() async throws {
        let s = LiveSession()
        try await s.connectAndPair(code: HardwareGate.pairingCode)
        try await s.refreshSigningTime()
        let baseline = try await s.historyCursor()

        // Wall 1 + signed permission (elevates to `.allowNonDelivery` for the signed request, then restores).
        let permission = try await s.request(BolusPermissionRequest(), expect: BolusPermissionResponse.self)
        guard permission.granted else {
            // The pump refusing permission without a cartridge is itself a valid rejection.
            #expect(!permission.granted, "pump refused bolus permission without a cartridge (expected)")
            return
        }

        // Wall 2: `.allowDelivery` + `allowInsulinDelivery`. The command goes out; we RECORD the response.
        let mask = InitiateBolusRequest.typeBitmask(hasCarbs: false, hasCorrection: false, isExtended: false)
        let req = try InitiateBolusRequest(validating: 100, bolusID: permission.bolusId, bolusTypeBitmask: mask)  // 0.10u
        let initiate = try await s.request(req, expect: InitiateBolusResponse.self, deliver: true)

        if initiate.accepted {
            // The invariant that actually matters: no delivery was recorded (no saline to move).
            let completed = try await s.bolusCompleted(bolusId: permission.bolusId, since: baseline)
            #expect(
                completed == nil,
                "SAFETY: a no-cartridge bolus produced a delivery record (id \(permission.bolusId)) — investigate")
        } else {
            #expect(!initiate.accepted, "pump rejected the no-cartridge initiate (expected; status \(initiate.status))")
        }
    }
}
