import Foundation

// BenchCoverageMatrix — the PURE, testable, resumable coverage model for the saline-bench harness.
//
// A bench session can only fill the cells its CURRENT hardware config allows (which pump model +
// firmware, cartridge present?, CGM present?). Coverage therefore accumulates ACROSS sessions run
// whenever the owner can obtain a given config. This file models that: a persistent matrix keyed by
// (pump model × firmware/SW × cartridge-state × CGM-state × command), a pure classifier that decides
// each cell's disposition for a given session config, and a merge that folds a new session's results
// into the accumulated matrix without ever letting a "can't test here" placeholder clobber a real result.
//
// Nothing here touches the wire. File I/O (load/save JSON) lives in the executable; this stays pure so
// `swift test` can prove the classification + merge + "what's left" reporting without CoreBluetooth.

// MARK: - Session configuration (the axes)

/// The hardware config of ONE bench session — the axes the matrix is keyed on.
public struct BenchSessionConfig: Sendable, Equatable {
    public var model: PumpModel
    public var apiVersion: ApiVersion
    /// A human/firmware tag (e.g. "SW7.6 (API 2.5)") — distinguishes old vs new t:slim X2 in the matrix.
    public var firmwareLabel: String
    public var pairingScheme: BenchPairingScheme
    public var cartridgePresent: Bool
    public var cgmPresent: Bool
    /// Human attestation that the loaded cartridge is SALINE (never insulin, never on a body).
    public var salineAttested: Bool
    /// `PUMPX2_DELIVER_SALINE=1` — the only flag that unblocks a delivery write.
    public var deliveryEnabled: Bool

    public init(
        model: PumpModel, apiVersion: ApiVersion, firmwareLabel: String,
        pairingScheme: BenchPairingScheme, cartridgePresent: Bool, cgmPresent: Bool,
        salineAttested: Bool, deliveryEnabled: Bool
    ) {
        self.model = model
        self.apiVersion = apiVersion
        self.firmwareLabel = firmwareLabel
        self.pairingScheme = pairingScheme
        self.cartridgePresent = cartridgePresent
        self.cgmPresent = cgmPresent
        self.salineAttested = salineAttested
        self.deliveryEnabled = deliveryEnabled
    }

    /// Stable model token for keys/labels (`PumpModel` has no rawValue).
    public var modelName: String { BenchSessionConfig.name(for: model) }
    public static func name(for model: PumpModel) -> String {
        switch model {
        case .tslim: return "tslim"
        case .mobi: return "mobi"
        }
    }

    /// A one-line human label for this session's config.
    public var label: String {
        "\(modelName) · \(firmwareLabel) · \(pairingScheme.rawValue) · "
            + "cart=\(cartridgePresent ? "yes" : "no") · cgm=\(cgmPresent ? "yes" : "no")"
            + (deliveryEnabled && salineAttested ? " · saline-deliver" : "")
    }
}

// MARK: - Cell state + planned disposition

/// The state of one matrix cell (one command in one config).
public enum BenchCellState: String, Sendable, Codable, CaseIterable {
    /// Exercised and confirmed (typed response parsed / history-log read-back matched the request).
    case pass
    /// Exercised and the check FAILED (wrong/absent response, or delivered != requested).
    case fail
    /// No safe harness affordance in this lane (e.g. a destructive command) — recorded, never auto-fired.
    case gap
    /// Not valid for this session's pump model — belongs to another model's matrix, never coverable here.
    case notApplicable
    /// Prerequisites unmet THIS session but coverable in a future session with the right config.
    case deferred
    /// Planned exercisable, but not yet run (a fresh planned cell before the runner drives it).
    case untested
}

/// The pure classifier's verdict for one (command, config) pair.
public enum BenchPlan: Sendable, Equatable {
    case exercise(BenchLane)
    case gap(String)
    case notApplicable(String)
    case deferred(String)

    /// The initial cell state this disposition implies (before the runner records a real result).
    public var initialState: BenchCellState {
        switch self {
        case .exercise: return .untested
        case .gap: return .gap
        case .notApplicable: return .notApplicable
        case .deferred: return .deferred
        }
    }

    public var note: String {
        switch self {
        case .exercise(let lane): return "exercisable (lane: \(lane.rawValue))"
        case .gap(let r), .notApplicable(let r), .deferred(let r): return r
        }
    }
}

// MARK: - The pure classifier

public enum BenchCoverage {

    /// Decide how `cmd` is disposed in session `cfg`. This is the heart of deliverable #2's "compute
    /// whether prerequisites are met in this config" — pure, deterministic, unit-tested.
    public static func plan(for cmd: BenchCommand, in cfg: BenchSessionConfig) -> BenchPlan {
        // Pairing is exercised implicitly when the session pairs; attribute by scheme (+ API floor).
        if cmd.lane == .pairing {
            if let floor = cmd.minApi, cfg.apiVersion < floor {
                return .deferred("needs a session on API ≥ \(floor.major).\(floor.minor) (JPAKE firmware)")
            }
            if let scheme = cmd.pairingScheme, scheme != cfg.pairingScheme {
                return .deferred("needs a \(scheme.rawValue)-pairing session")
            }
            return .exercise(.pairing)
        }

        // Model gate: a command not legal for this model is N/A here (covered in that model's sessions).
        guard cmd.applicablePumpModels.contains(cfg.model) else {
            let models = cmd.applicablePumpModels.map { BenchSessionConfig.name(for: $0) }.joined(separator: "/")
            return .notApplicable("model-restricted to \(models) — covered in a \(models) session")
        }
        // API floor: right model but this session's firmware is too old — coverable on newer firmware.
        if let floor = cmd.minApi, cfg.apiVersion < floor {
            return .deferred("needs \(cfg.modelName) firmware on API ≥ \(floor.major).\(floor.minor)")
        }

        switch cmd.lane {
        case .read:
            if cmd.requiresCGM && !cfg.cgmPresent {
                return .deferred("needs a CGM-present session (PUMP_CGM_PRESENT=1)")
            }
            return .exercise(.read)

        case .signedWrite:
            // Consult the reversible-affordance catalog: a signed write is exercisable only when the runner
            // has a wired, self-reversing driver for it (captureReapply / benignProbe). Everything else is a
            // documented GAP — `.manualOnly` (destructive / irreversible / owner-only) or `.bespokePending`
            // (reversible but its generic driver isn't wired), or the restore-half of a delivery pair.
            guard let aff = BenchAffordanceCatalog.affordance(for: cmd.name) else {
                return .gap("state-mutating signed write — no classified affordance; drive via the `probe` subcommand")
            }
            switch aff.driveability {
            case .manual(let reason):
                return .gap("MANUAL — \(reason); owner decides at the bench, never auto-fired")
            case .pending(let reason):
                return .gap("reversible affordance pending — \(reason)")
            case .viaPrimaryPair(let primary):
                return .gap(
                    "restore-half of the \(primary) reversible pair — recorded when that pair runs behind the saline gate"
                )
            case .drivable:
                if cmd.requiresCGM && !cfg.cgmPresent {
                    return .deferred("needs a CGM-present session (PUMP_CGM_PRESENT=1)")
                }
                return .exercise(.signedWrite)
            }

        case .delivery:
            if !cfg.cartridgePresent {
                return .deferred("needs a cartridge (saline) session on \(cfg.modelName)")
            }
            if !(cfg.salineAttested && cfg.deliveryEnabled) {
                return .deferred(
                    "needs a saline-attested delivery session "
                        + "(PUMP_SALINE_ATTESTED=1 + PUMPX2_DELIVER_SALINE=1)")
            }
            if cmd.requiresCGM && !cfg.cgmPresent {
                return .deferred("needs a CGM-present session (PUMP_CGM_PRESENT=1)")
            }
            return .exercise(.delivery)

        case .pairing:
            return .exercise(.pairing)  // unreachable (handled above); keeps the switch exhaustive
        }
    }

    /// Produce the full set of planned cells for a session — every catalog command classified for `cfg`,
    /// in its INITIAL state (untested/gap/notApplicable/deferred). The runner then upgrades the
    /// `untested` cells to pass/fail as it exercises them.
    public static func planSession(_ cfg: BenchSessionConfig, timestamp: String) -> [BenchCoverageCell] {
        BenchCommandCatalog.all.map { cmd in
            let p = plan(for: cmd, in: cfg)
            return BenchCoverageCell(
                model: cfg.modelName, firmware: cfg.firmwareLabel,
                cartridge: cfg.cartridgePresent, cgm: cfg.cgmPresent,
                command: cmd.name, lane: cmd.lane, state: p.initialState,
                note: p.note, session: cfg.label, timestamp: timestamp)
        }
    }
}

// MARK: - Cells + the persistent matrix

/// One recorded matrix cell — a command's coverage in one config, plus provenance.
public struct BenchCoverageCell: Sendable, Codable, Equatable {
    public var model: String
    public var firmware: String
    public var cartridge: Bool
    public var cgm: Bool
    public var command: String
    public var lane: BenchLane
    public var state: BenchCellState
    public var note: String
    public var session: String
    public var timestamp: String

    public init(
        model: String, firmware: String, cartridge: Bool, cgm: Bool, command: String,
        lane: BenchLane, state: BenchCellState, note: String, session: String, timestamp: String
    ) {
        self.model = model
        self.firmware = firmware
        self.cartridge = cartridge
        self.cgm = cgm
        self.command = command
        self.lane = lane
        self.state = state
        self.note = note
        self.session = session
        self.timestamp = timestamp
    }

    /// The composite key this cell occupies in the matrix (the five axes).
    public var key: String {
        BenchCoverageMatrix.key(model: model, firmware: firmware, cartridge: cartridge, cgm: cgm, command: command)
    }
}

/// The accumulated, resumable coverage matrix. Codable so the executable can persist it as JSON between
/// sessions; the merge + reporting are pure and unit-tested.
public struct BenchCoverageMatrix: Sendable, Codable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int
    /// keyed by `key(model:firmware:cartridge:cgm:command:)`.
    public var cells: [String: BenchCoverageCell]

    public init(
        schemaVersion: Int = BenchCoverageMatrix.currentSchemaVersion,
        cells: [String: BenchCoverageCell] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.cells = cells
    }

    public static func key(model: String, firmware: String, cartridge: Bool, cgm: Bool, command: String) -> String {
        "\(model)|\(firmware)|cart:\(cartridge ? 1 : 0)|cgm:\(cgm ? 1 : 0)|\(command)"
    }

    // MARK: merge precedence

    /// Whether a REAL result (a run happened) — pass/fail — outranks any planned placeholder.
    private static func isReal(_ s: BenchCellState) -> Bool { s == .pass || s == .fail }

    /// Informational rank among PLACEHOLDER states (gap > notApplicable > deferred > untested).
    private static func placeholderRank(_ s: BenchCellState) -> Int {
        switch s {
        case .gap: return 3
        case .notApplicable: return 2
        case .deferred: return 1
        default: return 0  // untested
        }
    }

    /// Should `new` replace `old` at the same key? A real result always beats a placeholder (so a
    /// "can't-test-here" cell from a wrong-config session can never overwrite a genuine PASS/FAIL);
    /// between two real results the LATEST timestamp wins (a later FAIL surfaces a regression, a later
    /// PASS records a fix); between two placeholders the more-informative one wins, then latest.
    public static func shouldReplace(_ old: BenchCoverageCell, with new: BenchCoverageCell) -> Bool {
        let newReal = isReal(new.state), oldReal = isReal(old.state)
        if newReal != oldReal { return newReal }  // real beats placeholder
        if newReal && oldReal { return new.timestamp >= old.timestamp }
        let rn = placeholderRank(new.state), ro = placeholderRank(old.state)
        if rn != ro { return rn > ro }
        return new.timestamp >= old.timestamp
    }

    /// Fold one cell in, respecting precedence.
    public mutating func record(_ cell: BenchCoverageCell) {
        if let existing = cells[cell.key] {
            if BenchCoverageMatrix.shouldReplace(existing, with: cell) { cells[cell.key] = cell }
        } else {
            cells[cell.key] = cell
        }
    }

    public mutating func record(_ newCells: [BenchCoverageCell]) { for c in newCells { record(c) } }

    /// Accumulate another matrix (e.g. a prior session's saved file) into this one, respecting precedence.
    public func merging(_ other: BenchCoverageMatrix) -> BenchCoverageMatrix {
        var out = self
        for c in other.cells.values { out.record(c) }
        return out
    }

    // MARK: reporting ("what's left, and which config covers it")

    /// A per-(model × firmware × command) coverage roll-up across the cartridge/CGM sub-axes.
    public struct Rollup: Sendable, Equatable {
        public var model: String
        public var firmware: String
        public var command: String
        public var lane: BenchLane
        /// The strongest state seen for this command in this (model,firmware) across cart/cgm variants.
        public var best: BenchCellState
        /// The most actionable note (for a not-yet-covered command, WHICH config would cover it).
        public var note: String
    }

    /// Roll each command up to (model, firmware): covered if ANY cart/cgm variant PASSED; otherwise the
    /// best remaining disposition + the note that says which session config would cover it.
    public func rollups() -> [Rollup] {
        var byTriple: [String: [BenchCoverageCell]] = [:]
        for c in cells.values {
            byTriple["\(c.model)|\(c.firmware)|\(c.command)", default: []].append(c)
        }
        return byTriple.values.map { group in
            // Best (strongest) cell: pass > fail > gap > notApplicable > deferred > untested.
            let ranked = group.sorted { rank($0.state) > rank($1.state) }
            let top = ranked[0]
            return Rollup(
                model: top.model, firmware: top.firmware, command: top.command,
                lane: top.lane, best: top.state, note: top.note)
        }.sorted { ($0.model, $0.firmware, $0.command) < ($1.model, $1.firmware, $1.command) }
    }

    /// "Most coverage/progress" ordering for rolling cart/CGM variants up to one status. A command that is
    /// exercisable in an AVAILABLE config (`untested`/`fail`) is more progressed than one that needs a
    /// config not present in this roll-up (`deferred`), which in turn beats a non-coverable `gap`/`n/a`.
    private func rank(_ s: BenchCellState) -> Int {
        switch s {
        case .pass: return 6
        case .fail: return 5
        case .untested: return 4
        case .deferred: return 3
        case .gap: return 2
        case .notApplicable: return 1
        }
    }

    /// Commands still needing a real PASS (excludes N/A and GAP, which are not "coverable-but-missing"):
    /// everything DEFERRED, FAIL, or UNTESTED, with the note that says which config to run.
    public func remaining() -> [Rollup] {
        rollups().filter { $0.best == .deferred || $0.best == .fail || $0.best == .untested }
    }

    // MARK: Markdown rendering (human-readable artifact)

    public func renderMarkdown(generatedAt: String) -> String {
        let rolls = rollups()
        var out = ""
        out += "# TandemKit bench command-coverage matrix\n\n"
        out += "_Generated \(generatedAt) · schema v\(schemaVersion) · \(cells.count) recorded cells "
        out += "across \(Set(cells.values.map { "\($0.model)|\($0.firmware)" }).count) session config(s)._\n\n"
        out += "This matrix accumulates ACROSS bench sessions. Each session fills only the cells its "
        out += "hardware config (pump model × firmware × cartridge × CGM) allows; the rest stay "
        out += "`deferred` (coverable later) or `n/a` (another model's matrix). A delivery cell PASSES "
        out += "only when the pump's OWN history-log read-back equals the requested units.\n\n"

        // Summary counts.
        var counts: [BenchCellState: Int] = [:]
        for r in rolls { counts[r.best, default: 0] += 1 }
        out += "## Summary (rolled up per model × firmware × command)\n\n"
        out += "| state | count |\n|---|---|\n"
        for s in BenchCellState.allCases where (counts[s] ?? 0) > 0 {
            out += "| `\(s.rawValue)` | \(counts[s]!) |\n"
        }
        out += "\n"

        // Per-config detail table.
        out += "## Coverage by session config\n\n"
        out += "| model | firmware | command | lane | best | detail |\n"
        out += "|---|---|---|---|---|---|\n"
        for r in rolls {
            out += "| \(r.model) | \(r.firmware) | `\(r.command)` | \(r.lane.rawValue) "
            out += "| \(symbol(r.best)) `\(r.best.rawValue)` | \(escape(r.note)) |\n"
        }
        out += "\n"

        // What remains, grouped by the config that would cover it.
        let rem = remaining()
        out += "## Still uncovered — and the session config that would cover it\n\n"
        if rem.isEmpty {
            out += "_Nothing coverable is outstanding: every applicable command has a PASS "
            out += "(remaining items, if any, are `gap` = no safe affordance, or `n/a` for this model)._\n"
        } else {
            var byNote: [String: [Rollup]] = [:]
            for r in rem { byNote[r.note, default: []].append(r) }
            for note in byNote.keys.sorted() {
                out += "- **\(escape(note))**\n"
                for r in byNote[note]!.sorted(by: { $0.command < $1.command }) {
                    out += "  - `\(r.command)` (\(r.model)/\(r.firmware), \(r.best.rawValue))\n"
                }
            }
        }

        // GAP cells — commands with NO safe auto-fire affordance. These are NOT "coverable-but-missing"
        // (so they are excluded from `remaining()`), but they are documented here so a manual/destructive
        // command is never silently dropped: the owner decides each at the bench.
        let gaps = rolls.filter { $0.best == .gap }
        out += "\n## Not auto-fired (manual / owner-judgment at the bench)\n\n"
        if gaps.isEmpty {
            out += "_No gap cells — every applicable command has an auto-fired affordance._\n"
        } else {
            var byNote: [String: [Rollup]] = [:]
            for g in gaps { byNote[g.note, default: []].append(g) }
            for note in byNote.keys.sorted() {
                out += "- **\(escape(note))**\n"
                for g in byNote[note]!.sorted(by: { $0.command < $1.command }) {
                    out += "  - `\(g.command)` (\(g.model)/\(g.firmware))\n"
                }
            }
        }
        return out
    }

    private func symbol(_ s: BenchCellState) -> String {
        switch s {
        case .pass: return "✅"
        case .fail: return "❌"
        case .gap: return "🚫"
        case .notApplicable: return "➖"
        case .deferred: return "⏳"
        case .untested: return "•"
        }
    }
    private func escape(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }
}
