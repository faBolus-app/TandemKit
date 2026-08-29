// LiveSession.swift — a thin, real wrapper over `PumpBLEClient` for the Tier-1 hardware harness.
//
// Owns the CoreBluetooth connect + JPAKE pair ONCE per suite (a full 6-digit pair on first connect,
// then quick-pair RESUME on every reconnect), and exposes: signed/typed request→response reads, the
// §1 history-log delivery oracle (cursor → command → stream → assert), the pump's OWN CGM read path,
// and a hex BLE trace. Reuses the proven delegate wiring from TandemBenchHarness/main.swift.
//
// SAFETY: `send` elevates the write policy to the MINIMUM the message's operation-risk requires, always
// via `withWritePolicy` (auto-restores `.readOnly`), and only sets `allowInsulinDelivery` for a delivery
// message. Both delivery walls stay armed; the harness never disables them.

import Foundation
@preconcurrency import CoreBluetooth
import Testing
import TandemMessages
import TandemAuth
import TandemBLE

/// Errors surfaced by the harness. A connect/pair timeout becomes a clean skip at the runner (never a
/// green delivery result) — see `HardwareCaseRunner`.
enum HarnessError: Error, CustomStringConvertible {
    case pumpUnreachable(String)
    case unexpectedResponse(String)
    var description: String {
        switch self {
        case .pumpUnreachable(let s): return "pump unreachable — skipped: \(s)"
        case .unexpectedResponse(let s): return "unexpected response: \(s)"
        }
    }
}

/// One captured BLE frame (for the parity log / post-hoc inspection).
struct TraceFrame: Sendable {
    enum Direction: String, Sendable { case outbound, inbound }
    let direction: Direction
    let characteristic: Characteristic
    let hex: String
}

/// Pump firmware/version identity, captured post-pairing so hardware results are tagged by version and
/// auth scheme. Legacy V1 (16-char) vs JPAKE (6-digit) pumps can differ on capability, txId, and time-set;
/// bench findings are only valid for the version observed. `pumpSoftwareVersion`/`modelNumber` come from
/// PumpVersionResponse when the pump answers it.
struct PumpFirmwareProfile: Sendable, CustomStringConvertible {
    let apiMajor: Int
    let apiMinor: Int
    let isMobi: Bool
    let pairingScheme: PairingCodeType
    let pumpSoftwareVersion: String     // PumpVersionResponse.pumpRev; "" if unread
    let armSoftwareVersion: UInt32      // PumpVersionResponse.armSwVer; 0 if unread
    let modelNumber: UInt32             // PumpVersionResponse.modelNum; 0 if unread

    var apiVersionString: String { "\(apiMajor).\(apiMinor)" }
    var description: String {
        var s = "API \(apiVersionString)\(isMobi ? " (Mobi)" : " (t:slim X2 family)") · pairing=\(pairingScheme.rawValue)"
        if !pumpSoftwareVersion.isEmpty { s += " · pumpSW=\(pumpSoftwareVersion)" }
        if armSoftwareVersion != 0 { s += " · armSW=\(armSoftwareVersion)" }
        if modelNumber != 0 { s += " · model=\(modelNumber)" }
        return s
    }
}

/// One request→response exchange with both transaction ids exposed, for the txId-match probe.
/// `requestTxId` is the byte the client wrote at `request.frame[1]`; `responseTxId` is the pump's byte at
/// `response.frame[1]`. txId-match holds iff the pump echoes the request byte in the response byte.
struct TxExchange: Sendable {
    let requestTxId: UInt8
    let responseFrame: [UInt8]
    /// The pump's echoed txId — `response.frame[1]` (0 if the frame is too short).
    var responseTxId: UInt8 { responseFrame.count > 1 ? responseFrame[1] : 0 }
    /// True when the pump echoed this request's txId in the response (necessary for txId correlation).
    var echoed: Bool { responseTxId == requestTxId }
}

@MainActor
final class LiveSession: NSObject, PumpBLEClientDelegate {
    let client = PumpBLEClient()

    private(set) var authKey: [UInt8] = []
    private(set) var signingTimestamp: UInt32 = 0
    private(set) var isPaired = false
    private(set) var trace: [TraceFrame] = []

    /// The pairing scheme in use, decided from the operator's code at pair time: JPAKE (6-digit,
    /// v7.7+) vs legacy V1 (16-char, pre-v7.7). Cases branch on this where the schemes differ.
    private(set) var pairingScheme: PairingCodeType = .short6Char
    /// The pump's firmware/version identity for result tagging — populated by `readFirmwareProfile()`.
    private(set) var firmwareProfile: PumpFirmwareProfile?

    /// CGM readings recovered from the most recent history stream (populated by the delegate).
    private(set) var historyCgmReadings: [CgmHistoryReading] = []

    private var pairingCode = ""
    private var wantConnect = false
    private var derivedSecret: [UInt8] = []
    private var coordinator: (any PairingCoordinating)?
    private var pairedContinuation: CheckedContinuation<Void, Error>?

    // History streaming: stream frames (opcode 129) arrive unsolicited on `.historyLog` and are routed
    // to the delegate (the request/response coordinator only consumes the 61 ack).
    private var collectingHistory = false
    private var historyRecords: [[UInt8]] = []

    override init() {
        super.init()
        client.delegate = self
    }

    // MARK: - Connect + JPAKE pair (once per suite)

    /// Scan → connect → JPAKE pair (full 6-digit on first connect). Throws on timeout so a case SKIPS
    /// cleanly rather than false-passing.
    func connectAndPair(code: String, timeout: TimeInterval = 30) async throws {
        guard !code.isEmpty else { throw HarnessError.pumpUnreachable("PUMP_PAIRING_CODE not set") }
        pairingCode = code
        wantConnect = true
        let timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            if let cont = pairedContinuation {
                pairedContinuation = nil
                cont.resume(throwing: HarnessError.pumpUnreachable("connect/pair timed out after \(Int(timeout))s"))
            }
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pairedContinuation = cont
            client.startScan()
        }
    }

    /// Drive pairing from the operator's code (`PairingAuth.detectType`). Pairing messages pass the
    /// `.readOnly` interlock. JPAKE (6-digit): full pair first, quick-pair RESUME on reconnect.
    /// Legacy V1 (16-char): full CentralChallenge→PumpChallenge; reconnect re-runs the challenge silently.
    private func beginPairing() {
        do {
            let scheme = PairingAuth.detectType(pairingCode)
            pairingScheme = scheme
            let coord: any PairingCoordinating
            switch scheme {
            case .short6Char:
                coord = derivedSecret.isEmpty
                    ? try PairingCoordinator(pairingCode: pairingCode)          // full 6-digit pair
                    : PairingCoordinator(resumeDerivedSecret: derivedSecret)    // quick-pair resume
            case .long16Char:
                coord = try LegacyPairingCoordinator(pairingCode: pairingCode)  // full re-challenge, no resume
            }
            coord.onSendRequest = { [weak self] msg in
                guard let self else { return }
                self.recordOutgoing(msg, key: [], ts: 0, deliver: false)
                _ = try? self.client.send(msg)
            }
            coord.onError = { [weak self] error in self?.finishPairing(.failure(error)) }
            coord.onPaired = { [weak self] key, _ in
                guard let self else { return }
                self.authKey = key
                // Only JPAKE carries a resume secret; V1 re-runs the full challenge on reconnect.
                if let jpake = coord as? PairingCoordinator { self.derivedSecret = jpake.derivedSecret }
                self.isPaired = true
                self.finishPairing(.success(()))
            }
            coordinator = coord
            coord.start()
        } catch {
            finishPairing(.failure(error))
        }
    }

    private func finishPairing(_ result: Result<Void, Error>) {
        guard let cont = pairedContinuation else { return }   // reconnect re-pair has no awaiter → no-op
        pairedContinuation = nil
        cont.resume(with: result)
    }

    /// Simulate a link drop and let the client reconnect + resume pairing via public API only.
    /// `disconnect` fail-closes write policy to `.readOnly`; rescan rediscovers and resumes.
    /// Reconnect ladder timing is unit-covered; hardware confirms the pump re-advertises and resume completes.
    func simulateLinkDrop() {
        isPaired = false
        coordinator = nil
        client.disconnect()   // fail-closes policy → .readOnly
        client.startScan()    // rediscover → reconnect → resume-pair
    }

    /// Wait until the client is `.ready` AND re-paired (resume complete), or throw a clean skip.
    func waitUntilReady(timeout: TimeInterval) async throws {
        try await waitFor({ self.client.state == .ready && self.isPaired }, timeout: timeout)
    }

    // MARK: - Signed / typed request→response

    /// Read the pump time and cache the signing timestamp (== currentTime, offset 0 — Responses.swift:
    /// `signingTimestamp` is `currentTime`, the gotcha that makes signed writes work).
    func refreshSigningTime() async throws {
        signingTimestamp = try await request(TimeSinceResetRequest(), expect: TimeSinceResetResponse.self).currentTime
    }

    /// Read + cache the pump's firmware/version identity so results can be tagged by pump version +
    /// auth scheme (see `PumpFirmwareProfile`). ApiVersion is required; PumpVersion is best-effort
    /// (a legacy/older pump may not answer it — tolerated, never a false failure).
    @discardableResult
    func readFirmwareProfile() async throws -> PumpFirmwareProfile {
        if let firmwareProfile { return firmwareProfile }
        let api = try await request(ApiVersionRequest(), expect: ApiVersionResponse.self)
        let ver = try? await request(PumpVersionRequest(), expect: PumpVersionResponse.self)
        let profile = PumpFirmwareProfile(
            apiMajor: api.majorVersion, apiMinor: api.minorVersion, isMobi: api.isMobi,
            pairingScheme: pairingScheme, pumpSoftwareVersion: ver?.pumpRev ?? "",
            armSoftwareVersion: ver?.armSwVer ?? 0, modelNumber: ver?.modelNum ?? 0)
        firmwareProfile = profile
        return profile
    }

    /// Send `message` (optionally signed, optionally awaiting the correlated reply) and record the frame.
    /// Write policy is elevated to the minimum `operationRisk` requires, always restored to `.readOnly`.
    /// `deliver == true` arms `allowInsulinDelivery` for delivery-class messages.
    @discardableResult
    func send(_ message: Message, awaitReply: Bool = true, deliver: Bool = false,
              deadline: TimeInterval = 15) async throws -> [UInt8] {
        let signed = message.signed
        let key = signed ? authKey : []
        let ts = signed ? signingTimestamp : 0
        recordOutgoing(message, key: key, ts: ts, deliver: deliver)
        let policy = Self.minimumPolicy(for: message.operationRisk)
        let serialized = (message.operationRisk == .delivery)   // delivery-class: at most one in flight
        return try await client.withWritePolicy(policy) {
            if awaitReply {
                return try await self.client.sendAwaitingResponse(
                    message, authenticationKey: key, pumpTimeSinceReset: ts,
                    allowInsulinDelivery: deliver, deadline: deadline, serialized: serialized)
            } else {
                _ = try self.client.send(message, authenticationKey: key,
                                         pumpTimeSinceReset: ts, allowInsulinDelivery: deliver)
                return []
            }
        }
    }

    /// Send `request` and parse its reply as `R` (reply is on the request's characteristic for every
    /// message the harness uses).
    @discardableResult
    func request<M: Message, R: Message>(_ request: M, expect: R.Type, deliver: Bool = false,
                                         deadline: TimeInterval = 15) async throws -> R {
        let frame = try await send(request, deliver: deliver, deadline: deadline)
        return try parse(frame, on: request.characteristic, as: R.self)
    }

    private func parse<R: Message>(_ frame: [UInt8], on ch: Characteristic, as: R.Type) throws -> R {
        let parsed = try ResponseParser.parse(frame: frame, characteristic: ch)
        guard let typed = parsed.message as? R else {
            throw HarnessError.unexpectedResponse("expected \(R.self), got opcode \(parsed.opCode) on \(ch.name)")
        }
        return typed
    }

    /// Read-only exchange exposing both request and response txIds for the txId-match probe.
    /// Throws on mutating messages — the probe must never pipeline delivery commands. Write policy stays `.readOnly`.
    func exchangeCapturingTxId(_ message: Message, deadline: TimeInterval = 15) async throws -> TxExchange {
        guard message.operationRisk == .read else {
            throw HarnessError.unexpectedResponse("txId probe is READ-ONLY; refusing \(type(of: message)) (risk \(message.operationRisk))")
        }
        guard let responseOpCode = message.props.responseOpCode else {
            throw HarnessError.unexpectedResponse("no responseOpCode for \(type(of: message))")
        }
        var requestTxId: UInt8 = 0
        let frame = try await client.withWritePolicy(.readOnly) {
            try await self.client.transactions.perform(
                expectedResponseOn: message.characteristic, opCode: responseOpCode,
                deadline: deadline, serialized: false
            ) {
                let txId = try self.client.send(message)   // unsigned read; returns the wire txId
                requestTxId = txId
                let hex = (try? Packetize.packetize(message, txId: txId).map { Hex.encode($0.build()) }.joined()) ?? ""
                self.trace.append(TraceFrame(direction: .outbound, characteristic: message.characteristic, hex: hex))
                return txId
            }
        }
        trace.append(TraceFrame(direction: .inbound, characteristic: message.characteristic, hex: Hex.encode(frame)))
        return TxExchange(requestTxId: requestTxId, responseFrame: frame)
    }

    /// The minimum `WritePolicy` that authorizes a message of the given risk. Never grants more than the
    /// op needs; `withWritePolicy` restores `.readOnly` immediately after.
    static func minimumPolicy(for risk: OperationRisk) -> PumpBLEClient.WritePolicy {
        switch risk {
        case .read:        return .readOnly
        case .benign:      return .allowBenignControl
        case .settings:    return .allowNonDelivery
        case .destructive: return .allowDestructive
        case .delivery:    return .allowDelivery
        }
    }

    // MARK: - History-log oracle (the C4 authoritative delivery read-back)

    /// The available history-log range + cursor. Take the `lastSequenceNum` BEFORE a command so only the
    /// records that command produced (strictly greater seqNum) are streamed — this also isolates cases.
    func historyStatus() async throws -> HistoryLogStatusResponse {
        try await request(HistoryLogStatusRequest(), expect: HistoryLogStatusResponse.self)
    }

    /// The cursor baseline (`lastSequenceNum`).
    func historyCursor() async throws -> UInt32 { try await historyStatus().lastSequenceNum }

    /// Stream up to `count` records starting at `from` and return typed events (HistoryLogRequest 60→61;
    /// records arrive as `HistoryLogStreamResponse` frames on `.historyLog`). CGM readings from the same
    /// frames are captured into `historyCgmReadings`.
    func streamHistory(from: UInt32, count: Int) async throws -> [any HistoryLogEvent] {
        historyRecords.removeAll()
        historyCgmReadings.removeAll()
        collectingHistory = true
        defer { collectingHistory = false }
        let n = min(max(count, 1), 255)
        _ = try await send(HistoryLogRequest(startLog: from, numberOfLogs: n))   // awaits the 61 ack
        // The stream frames are unsolicited (opcode 129) → collected by the delegate. There may legitimately
        // be fewer than `n` records in the log, so tolerate an incomplete read.
        try await waitFor({ self.historyRecords.count >= n }, timeout: 12, allowIncomplete: true)
        return historyRecords.map { HistoryLogParser.parse(record: $0) }
    }

    /// Stream the most recent `count` records (tail read) — used for CGM-history assertions where the
    /// records of interest predate the baseline cursor.
    func recentHistory(count: Int) async throws -> [any HistoryLogEvent] {
        let st = try await historyStatus()
        let n = UInt32(min(max(count, 1), 255))
        let start = st.lastSequenceNum >= n ? st.lastSequenceNum - n + 1 : st.firstSequenceNum
        return try await streamHistory(from: start, count: count)
    }

    /// The authoritative delivered-units record for a bolus id: `BolusCompletedHistoryLog` (typeId 20)
    /// with `insulinDelivered` == the physical dose (C4 ground truth; HistoryLogEvents.swift:238-260).
    func bolusCompleted(bolusId: Int, since seq: UInt32) async throws -> BolusCompletedHistoryLog? {
        try await streamHistory(from: seq, count: 255)
            .compactMap { $0 as? BolusCompletedHistoryLog }
            .first { $0.bolusId == bolusId }
    }

    // MARK: - Helpers

    private func waitFor(_ condition: @escaping @MainActor () -> Bool,
                         timeout: TimeInterval, allowIncomplete: Bool = false) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                if allowIncomplete { return }
                throw HarnessError.pumpUnreachable("condition not met within \(Int(timeout))s")
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func recordOutgoing(_ m: Message, key: [UInt8], ts: UInt32, deliver: Bool) {
        let hex = (try? Packetize.packetize(m, authenticationKey: key, txId: 0,
                                            pumpTimeSinceReset: ts,
                                            actionsAffectingInsulinDeliveryEnabled: deliver)
            .map { Hex.encode($0.build()) }.joined()) ?? ""
        trace.append(TraceFrame(direction: .outbound, characteristic: m.characteristic, hex: hex))
    }

    // MARK: - PumpBLEClientDelegate

    func pumpClient(_ client: PumpBLEClient, didChange state: PumpBLEClient.State) {
        // Resume scanning once Bluetooth is powered on (mirrors TandemBenchHarness/main.swift).
        if state == .idle, wantConnect, !isPaired { client.startScan() }
    }

    func pumpClient(_ client: PumpBLEClient, didDiscover peripheral: CBPeripheral, rssi: Int) {
        client.connect(peripheral)
    }

    func pumpClientDidBecomeReady(_ client: PumpBLEClient) {
        beginPairing()
    }

    func pumpClient(_ client: PumpBLEClient, didReceiveFrame frame: [UInt8], on characteristic: Characteristic) {
        trace.append(TraceFrame(direction: .inbound, characteristic: characteristic, hex: Hex.encode(frame)))
        switch characteristic {
        case .authorization:
            // Validate the frame CRC-16 before the coordinator parses it inline (it bypasses
            // ResponseParser's CRC check) — a corrupted pairing reply must not advance the handshake.
            guard frame.count >= 5,
                  Bytes.calculateCRC16(Array(frame[0..<(frame.count - 2)])) == Array(frame[(frame.count - 2)...])
            else { return }
            coordinator?.handle(frame: frame)
        case .historyLog:
            guard collectingHistory,
                  let parsed = try? ResponseParser.parse(frame: frame, characteristic: .historyLog),
                  let stream = parsed.message as? HistoryLogStreamResponse else { return }
            historyRecords.append(contentsOf: stream.records)
            historyCgmReadings.append(contentsOf: stream.cgmReadings)
        default:
            break
        }
    }

    func pumpClient(_ client: PumpBLEClient, didError error: Error) {
        // A fault before pairing completes surfaces as a clean skip via the pending continuation.
        finishPairing(.failure(error))
    }
}
