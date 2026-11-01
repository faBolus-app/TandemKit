import Foundation
import TandemMessages

/// The connection state machine: a pure transition function. It owns every piece of link state
/// (`LinkState`); the driver only performs the effects and feeds back what happened.
///
/// The connection lifecycle follows pumpx2's `TandemBluetoothHandler` and `TandemPump`: discover the
/// pump service, subscribe to the characteristics the pump has (skipping missing ones),
/// authenticate, then send only ApiVersion, PumpVersion and TimeSinceReset. What pumpx2 doesn't
/// have is written here from the pump facts: the request queue with one request in flight and txId
/// matching, the op-77 classification, careful probing, the reconnect ladder and
/// the telemetry.
public enum LinkReducer {
    /// Applies `input` at `now`. The state comes back changed, with the effects to perform in order.
    /// `date` is the wall-clock time, used only to stamp support evidence for people reading it.
    /// `jitter` is a random number in `0..<1` the driver draws for each input, so the backoff can vary
    /// while the transition stays a function of its inputs.
    public static func reduce(_ state: LinkState, _ input: LinkInput, now: LinkTime, date: Date, jitter: Double = 0)
        -> (LinkState, [LinkEffect])
    {
        let step = Step(state: state, now: now, date: date, jitter: jitter)
        step.apply(input)
        return (step.state, step.effects)
    }

    /// The reads sent after authenticating, in order (pumpx2 `TandemPump.onPumpConnected`).
    static func handshakeReads() -> [any Message] {
        [ApiVersionRequest(), PumpVersionRequest(), TimeSinceResetRequest()]
    }

    /// Characteristics a connection can't work without: authentication and status replies. The rest
    /// may be missing on older firmware.
    static let requiredCharacteristics: Set<Characteristic> = [.authorization, .currentStatus]
}

/// One transition in progress. A class, so the transition's inputs (`now`, `date`, `config`) are
/// constants that can be read while `state` is being changed.
private final class Step {
    var state: LinkState
    let now: LinkTime
    let date: Date
    let jitter: Double
    let config: LinkConfiguration
    var effects: [LinkEffect] = []

    init(state: LinkState, now: LinkTime, date: Date, jitter: Double) {
        self.state = state
        self.now = now
        self.date = date
        self.jitter = jitter
        self.config = state.config
    }

    func apply(_ input: LinkInput) {
        catchUp()
        switch input {
        case .connect(let target, let matrix): connect(target, matrix)
        case .scanForPairing: scanForPairing()
        case .stop: stop()
        case .appActive(let active): appActive(active)
        case .submit(let request): submit(request)
        case .cancel(let id): cancel(id)
        case .retest(let key): retest(key)
        case .power(let power): powerChanged(power)
        case .restored(let peripherals): state.restored = peripherals
        case .discovered(let id, let name, let rssi): discovered(id, name, rssi)
        case .peripheralUnavailable(let id): peripheralUnavailable(id)
        case .connected(let id, let name): connected(id, name)
        case .connectFailed(let id, _): connectFailed(id)
        case .disconnected(let id, let error): disconnected(id, error)
        case .characteristicsDiscovered(let present): characteristicsDiscovered(present)
        case .subscription(let characteristic, let isNotifying, let failed):
            subscription(characteristic, isNotifying: isNotifying, failed: failed)
        case .deviceInformation(let modelNumber): state.connection?.identity.modelNumber = modelNumber
        case .notified(let characteristic, let bytes): notified(characteristic, bytes)
        case .writeFailed(let characteristic, let txId): writeFailed(characteristic, txId: txId)
        case .authenticationRequest(let message): authenticationRequest(message)
        case .authenticated(let key, let derivedSecret): authenticated(key: key, derivedSecret: derivedSecret)
        case .authenticationFailed(let rejected): authenticationFailed(rejected: rejected)
        case .timerFired(let timer): timerFired(timer)
        }
    }

    /// Timers don't fire while iOS has the app suspended. A settle window or hold window that ended
    /// while suspended is applied first, as of when it ended, so what happened after it (a drop an hour
    /// later) isn't read as happening inside it.
    func catchUp() {
        if let until = state.connection?.settleUntil, until <= now { settleWindowPassed() }
        if state.phase == .ready, let connection = state.connection, connection.heldAt == nil,
            let readyAt = connection.readyAt, now - readyAt >= config.holdWindow
        {
            holdReached(at: readyAt + config.holdWindow)
        }
    }

    // MARK: Effects

    func emit(_ event: LinkEvent) { effects.append(.emit(event)) }
    func transport(_ command: TransportCommand) { effects.append(.transport(command)) }
    func startTimer(_ timer: LinkTimer, after seconds: Double) {
        effects.append(.startTimer(timer, after: seconds))
    }
    func cancelTimer(_ timer: LinkTimer) { effects.append(.cancelTimer(timer)) }

    func setPhase(_ phase: LinkPhase) {
        guard phase != state.phase else { return }
        state.phase = phase
        emit(.phase(phase))
    }

    func complete(_ id: RequestID, _ result: RequestResult) {
        cancelTimer(.request(id))
        effects.append(.complete(id, result))
    }

    // MARK: Caller

    func connect(_ target: PumpTarget, _ matrix: SupportMatrix) {
        state.support = matrix
        state.wantsPairingScan = false
        if let model = target.model, !config.supportedModels.contains(model) {
            stopEverything(reason: .requested)
            state.target = target
            setPhase(.failed(.unsupportedModel(model)))
            return
        }
        // Already connected or reconnecting to this pump: take the new credentials and matrix, and keep
        // the link and the ladder, so calling connect again can't skip the backoff.
        if state.target?.peripheralID == target.peripheralID {
            switch state.phase {
            case .idle, .failed, .exhausted, .scanning(forPairing: true): break
            default:
                state.target = target
                return
            }
        }
        stopEverything(reason: .requested)
        state.target = target
        state.ladder = ReconnectLadder()
        startConnecting()
    }

    func scanForPairing() {
        stopEverything(reason: .requested)
        state.target = nil
        state.ladder = ReconnectLadder()
        state.wantsPairingScan = true
        guard state.power == .poweredOn else {
            setPhase(.waitingForBluetooth)
            return
        }
        transport(.scan)
        startTimer(.scan, after: config.scanTimeout)
        setPhase(.scanning(forPairing: true))
    }

    func stop() {
        stopEverything(reason: .requested)
        state.target = nil
        state.wantsPairingScan = false
        setPhase(.idle)
    }

    /// Closes the connection, stops scanning and cancels the ladder's timers.
    func stopEverything(reason: DisconnectReason) {
        if let id = state.connection?.peripheralID {
            closeConnection(reason)
            transport(.cancelConnection(id))
        } else if state.phase == .connecting, let id = state.target?.peripheralID {
            transport(.cancelConnection(id))  // the pending connect
        }
        if case .scanning = state.phase { transport(.stopScan) }
        cancelTimer(.scan)
        cancelTimer(.backoff)
    }

    func appActive(_ active: Bool) {
        state.appActive = active
        if active, state.phase == .exhausted, state.target != nil {
            // Owner, 2026-10-31: coming to the foreground restarts an exhausted ladder once.
            state.ladder.flaps = 0
            startConnecting()
        } else if active, state.phase == .connecting, let id = state.target?.peripheralID {
            // A pending connect can be lost with no callback; reissuing it is harmless (the old client's
            // watchdog existed for a link that otherwise stayed down until a force quit).
            transport(.connect(id))
        } else if !active, state.phase == .backingOff {
            // The backoff timer won't fire while suspended. The flap is already counted, so issue the
            // pending connect now (owner, 2026-10-31), as a background flap does.
            cancelTimer(.backoff)
            startConnecting()
        }
    }

    func retest(_ key: MessageKey) {
        state.sittingOut.remove(key)
        state.undefinedErrors[key] = nil
        guard let unit = state.connection?.identity.unit ?? state.lastIdentity?.unit else { return }
        state.support.forget(key, on: unit)
        emit(.supportMatrixChanged(state.support))
    }

    // MARK: Requests

    func submit(_ request: LinkRequest) {
        // Refusals that hold on any link come first, so a call that can never be sent isn't reported
        // as merely not ready.
        let message = request.message
        if message.operationRisk > request.allowing {
            return complete(request.id, .notSent(.writeBlocked(message.operationRisk)))
        }
        if !SupportMatrix.isAllowedSignedWrite(message) {
            return complete(request.id, .notSent(.signedWriteNotAllowed))
        }
        if message.props.responseOpCode == nil {
            return complete(request.id, .notSent(.encodingFailed))
        }
        guard state.phase == .ready, let connection = state.connection else {
            return complete(request.id, .notSent(.notReady))
        }
        let identity = connection.identity
        if let devices = message.props.supportedDevices {
            guard let model = identity.model else { return complete(request.id, .notSent(.identityUnknown)) }
            if !devices.contains(model) { return complete(request.id, .notSent(.unsupported)) }
        }
        if !connection.present.contains(message.characteristic) {
            return complete(request.id, .notSent(.characteristicUnavailable))
        }
        let key = request.key
        if state.sittingOut.contains(key) { return complete(request.id, .notSent(.sittingOut)) }
        // The matrix decides, not the API version: a minApi above the pump's version leaves the
        // read untested, so it's probed once instead of never sent.
        let entry = state.support.entry(
            for: key, unit: identity.unit, model: identity.model, apiVersion: identity.apiVersion)
        if entry.status == .unsupported { return complete(request.id, .notSent(.unsupported)) }
        let untested = entry.status == .untested
        if untested, !message.signed, connection.probingStopped {
            return complete(request.id, .notSent(.probeStopped))
        }
        let pending = Pending(
            request: request, untested: untested,
            attemptsLeft: message.signed ? 0 : config.readRetries, isRetry: false)
        state.connection?.queue.append(pending)
        dispatch()
    }

    func cancel(_ id: RequestID) {
        guard var connection = state.connection else { return }
        if let index = connection.queue.firstIndex(where: { $0.request.id == id }) {
            connection.queue.remove(at: index)
            state.connection = connection
            return complete(id, .notSent(.cancelled))
        }
        if let inFlight = connection.inFlight, inFlight.pending?.request.id == id, !inFlight.orphaned {
            // It's on the wire: keep the slot busy until its reply or deadline, so a late reply can't be
            // taken for the next request's.
            state.connection?.inFlight?.orphaned = true
            effects.append(.complete(id, .unknown(.cancelled)))
            return
        }
        if let reply = connection.lastError, reply.pending?.request.id == id {
            state.connection?.lastError?.pending = nil
            complete(id, .pumpError(reply.error))
        }
    }

    /// Sends the next request if the wire is free.
    func dispatch() {
        guard let connection = state.connection, connection.inFlight == nil, connection.settleUntil == nil else {
            return
        }
        if state.phase == .handshaking {
            sendNextHandshakeRead()
            return
        }
        guard state.phase == .ready else { return }
        let held = connection.heldAt != nil
        for index in connection.queue.indices {
            let pending = connection.queue[index]
            guard connection.subscribed.contains(pending.request.message.characteristic) else { continue }
            // Untested commands go alone, only after the link held, and never in the post-pairing burst.
            if pending.untested && !held { continue }
            state.connection?.queue.remove(at: index)
            send(pending)
            return
        }
    }

    func send(_ pending: Pending) {
        guard let connection = state.connection else { return }
        let message = pending.request.message
        let txId = connection.nextTxId
        let packets: [Packet]
        do {
            packets = try Packetize.packetize(
                message, authenticationKey: connection.authKey ?? [], txId: txId,
                pumpTimeSinceReset: connection.clock?.pumpTime ?? 0,
                actionsAffectingInsulinDeliveryEnabled: pending.request.allowing >= .delivery)
        } catch {
            complete(pending.request.id, .notSent(.encodingFailed))
            dispatch()
            return
        }
        state.connection?.nextTxId = txId &+ 1
        state.connection?.inFlight = InFlight(
            pending: pending, message: message, txId: txId, pumpTimeAtSend: connection.clock?.estimate(at: now))
        // The deadline runs from here. Waiting in the queue is bounded by whatever it waits on: the
        // request ahead (its own deadline), the settle window, the hold, or a subscription coming back.
        startTimer(.request(pending.request.id), after: pending.request.deadline)
        transport(.write(message.characteristic, packets.map { $0.build() }))
    }

    func sendNextHandshakeRead() {
        guard var connection = state.connection, connection.inFlight == nil else { return }
        guard !connection.handshake.isEmpty else { return becomeReady() }
        let message = connection.handshake.removeFirst()
        let txId = connection.nextTxId
        guard let packets = try? Packetize.packetize(message, txId: txId) else {
            return failHandshake()
        }
        connection.nextTxId = txId &+ 1
        connection.inFlight = InFlight(pending: nil, message: message, txId: txId, pumpTimeAtSend: nil)
        state.connection = connection
        transport(.write(message.characteristic, packets.map { $0.build() }))
    }

    // MARK: Bluetooth

    func powerChanged(_ power: BluetoothPower) {
        state.power = power
        guard power == .poweredOn else {
            // didDisconnect doesn't reliably follow a power-off, so the connection closes here.
            if state.connection != nil { closeConnection(.bluetoothUnavailable(power)) }
            state.restored = []
            cancelTimer(.backoff)
            if case .scanning = state.phase { cancelTimer(.scan) }
            switch state.phase {
            case .idle, .failed, .exhausted: break
            default: setPhase(.waitingForBluetooth)
            }
            return
        }
        guard state.phase == .waitingForBluetooth else { return }
        if state.target != nil {
            startConnecting()
        } else if state.wantsPairingScan {
            scanForPairing()
        } else {
            setPhase(.idle)
        }
    }

    /// Issues the pending connect for the target, or adopts a connection iOS restored.
    func startConnecting() {
        cancelTimer(.backoff)
        guard let target = state.target else { return setPhase(.idle) }
        guard state.power == .poweredOn else { return setPhase(.waitingForBluetooth) }
        let restored = state.restored.first { $0.peripheralID == target.peripheralID }
        for other in state.restored where other.peripheralID != target.peripheralID {
            transport(.cancelConnection(other.peripheralID))
        }
        state.restored = []
        if let restored, restored.isConnected {
            // The link survived the app's termination; rediscover and authenticate on it.
            setPhase(.connecting)
            connected(restored.peripheralID, restored.name)
            return
        }
        transport(.connect(target.peripheralID))
        setPhase(.connecting)
    }

    func discovered(_ id: UUID, _ name: String?, _ rssi: Int) {
        switch state.phase {
        case .scanning(forPairing: true):
            emit(.discovered(peripheralID: id, name: name, model: pumpModel(advertisedName: name), rssi: rssi))
        case .scanning(forPairing: false) where id == state.target?.peripheralID:
            transport(.stopScan)
            cancelTimer(.scan)
            startConnecting()
        default:
            break
        }
    }

    func peripheralUnavailable(_ id: UUID) {
        guard state.phase == .connecting, id == state.target?.peripheralID else { return }
        transport(.scan)
        startTimer(.scan, after: config.scanTimeout)
        setPhase(.scanning(forPairing: false))
    }

    func connected(_ id: UUID, _ name: String?) {
        guard let target = state.target, id == target.peripheralID, state.connection == nil else {
            if state.connection?.peripheralID != id { transport(.cancelConnection(id)) }
            return
        }
        switch state.phase {
        case .connecting, .backingOff, .scanning(forPairing: false): break
        default:
            // A late completion after the link stopped or gave up: don't let it contradict that.
            transport(.cancelConnection(id))
            return
        }
        if case .scanning = state.phase { transport(.stopScan) }
        cancelTimer(.scan)
        cancelTimer(.backoff)
        let seen = pumpModel(advertisedName: name)
        state.connection = Connection(
            peripheralID: id, connectedAt: now,
            identity: PumpIdentity(model: seen ?? target.model, advertisedName: name))
        state.telemetry.connects += 1
        if let seen, let stored = target.model, seen != stored {
            return reject(id, .identityMismatch(stored: stored, seen: seen))
        }
        if let seen, !config.supportedModels.contains(seen) {
            return reject(id, .unsupportedModel(seen))
        }
        setPhase(.discovering)
        startTimer(.establishment, after: config.establishmentTimeout)
        transport(.discover)
        transport(.readDeviceInformation)
    }

    func reject(_ id: UUID, _ failure: LinkFailure) {
        closeConnection(.identityRejected)
        transport(.cancelConnection(id))
        setPhase(.failed(failure))
    }

    func connectFailed(_ id: UUID) {
        guard id == state.target?.peripheralID, state.connection == nil, state.phase == .connecting else { return }
        flap()
    }

    func disconnected(_ id: UUID, _ error: BluetoothError?) {
        guard let connection = state.connection, connection.peripheralID == id else { return }
        var reason = DisconnectReason.linkLost(error)
        var exempt = false
        if let errorReply = connection.lastError {
            // A drop inside the settle window is the pump's answer to that op-77.
            let code = errorReply.error.errorCodeId
            let unsupported = code == 6 || (code == 0 && errorReply.untested)
            if unsupported {
                recordEvidence(
                    code == 6 ? .unsupported : .droppedAfterError, for: errorReply.key,
                    note: "op-77 code \(code), then a link drop")
                reason = .afterUnsupportedRequest(errorReply.key, errorCode: code)
                exempt = true
            } else {
                reason = .afterErrorReply(errorReply.key, errorCode: code)
                if code == 0 { countUndefinedError(errorReply.key) }
            }
            if let pending = errorReply.pending { complete(pending.request.id, .pumpError(errorReply.error)) }
            state.connection?.lastError = nil
        }
        dropped(reason, exempt: exempt, cancel: false)
    }

    /// The connection is gone (or being cancelled). Decides how to reconnect:
    /// - after the link held, or after a probe's error: a pending connect at once, off the ladder;
    /// - otherwise it's a flap and climbs the ladder.
    func dropped(_ reason: DisconnectReason, exempt: Bool, cancel: Bool) {
        guard let connection = state.connection else { return }
        let held = connection.heldAt != nil
        if cancel { transport(.cancelConnection(connection.peripheralID)) }
        if exempt || held {
            closeConnection(reason)
            startConnecting()
        } else {
            state.ladder.flaps += 1
            closeConnection(reason)
            afterFlap()
        }
    }

    /// A drop before the link held, or a connect that failed.
    func flap() {
        state.ladder.flaps += 1
        afterFlap()
    }

    func afterFlap() {
        let flaps = state.ladder.flaps
        if flaps >= config.unstableAfterFlaps && !state.ladder.reportedUnstable {
            state.ladder.reportedUnstable = true
            emit(.connectionUnstable(flaps: flaps))
        }
        if flaps >= config.maxFlaps {
            if let id = state.target?.peripheralID { transport(.cancelConnection(id)) }
            setPhase(.exhausted)
        } else if state.appActive {
            // Jitter keeps the phone's retries from locking into step with the pump's advertising.
            let base = config.backoff.isEmpty ? 0 : config.backoff[min(flaps - 1, config.backoff.count - 1)]
            startTimer(.backoff, after: base * (1 + config.backoffJitter * jitter))
            setPhase(.backingOff)
        } else {
            // Owner, 2026-10-31: in the background a flap issues the pending connect at once, counted.
            startConnecting()
        }
    }

    /// Closes the open connection: every queued request fails, the one on the wire becomes unknown, its
    /// timers stop, and the span is recorded.
    func closeConnection(_ reason: DisconnectReason) {
        guard let connection = state.connection else { return }
        state.connection = nil
        for pending in connection.queue { complete(pending.request.id, .notSent(.connectionLost)) }
        if let pending = connection.inFlight?.pending {
            if connection.inFlight?.orphaned == true {
                cancelTimer(.request(pending.request.id))
            } else {
                complete(pending.request.id, .unknown(.connectionLost))
            }
        }
        if let pending = connection.lastError?.pending {
            complete(pending.request.id, .pumpError(connection.lastError!.error))
        }
        for timer in [LinkTimer.establishment, .hold, .settle, .resubscribe] { cancelTimer(timer) }
        if state.phase == .authenticating { effects.append(.endAuthentication) }
        let span = ConnectionSpan(
            connectedAt: connection.connectedAt, closedAt: now, authenticated: connection.authenticatedAt != nil,
            held: connection.heldAt != nil, reason: reason, flapsAfter: state.ladder.flaps)
        state.telemetry.record(span, kept: config.spansKept, wasReady: connection.readyAt != nil)
        emit(.disconnected(reason, span))
    }

    // MARK: Setup

    func characteristicsDiscovered(_ present: Set<Characteristic>) {
        guard state.phase == .discovering, state.connection != nil else { return }
        state.connection?.present = present
        guard LinkReducer.requiredCharacteristics.isSubset(of: present) else {
            return dropped(.setupFailed, exempt: false, cancel: true)
        }
        for characteristic in ServiceUUID.notificationCharacteristics where present.contains(characteristic) {
            transport(.subscribe(characteristic))
        }
    }

    func subscription(_ characteristic: Characteristic, isNotifying: Bool, failed: Bool) {
        guard let connection = state.connection else { return }
        if failed {
            // Failing while being restored: the resubscribe deadline decides.
            guard !connection.resubscribing.contains(characteristic) else { return }
            // A first subscription that fails: an optional characteristic isn't waited for; a
            // required one ends setup.
            if state.phase == .discovering, LinkReducer.requiredCharacteristics.contains(characteristic) {
                dropped(.setupFailed, exempt: false, cancel: true)
            }
            return
        }
        if !isNotifying {
            state.connection?.subscribed.remove(characteristic)
            guard state.phase != .discovering, connection.subscribed.contains(characteristic) else { return }
            // A subscription can drop while the link stays up, with no disconnect. Re-subscribe, and
            // give up on the connection if it doesn't come back.
            if connection.resubscribing.isEmpty { startTimer(.resubscribe, after: config.establishmentTimeout) }
            state.connection?.resubscribing.insert(characteristic)
            transport(.subscribe(characteristic))
            return
        }
        state.connection?.subscribed.insert(characteristic)
        if state.connection?.resubscribing.remove(characteristic) != nil,
            state.connection?.resubscribing.isEmpty == true
        {
            cancelTimer(.resubscribe)
        }
        if state.phase == .discovering,
            LinkReducer.requiredCharacteristics.isSubset(of: state.connection?.subscribed ?? []),
            let credentials = state.target?.credentials
        {
            setPhase(.authenticating)
            effects.append(.startAuthentication(credentials))
        }
        dispatch()
    }

    func authenticationRequest(_ message: any Message) {
        guard state.phase == .authenticating, let connection = state.connection else { return }
        let txId = connection.nextTxId
        guard let packets = try? Packetize.packetize(message, txId: txId) else {
            return authenticationFailed(rejected: false)
        }
        state.connection?.nextTxId = txId &+ 1
        transport(.write(message.characteristic, packets.map { $0.build() }))
    }

    func authenticated(key: [UInt8], derivedSecret: [UInt8]?) {
        guard state.phase == .authenticating, state.connection != nil else { return }
        effects.append(.endAuthentication)
        state.connection?.authKey = key
        state.connection?.authenticatedAt = now
        if let derivedSecret, case .jpake = state.target?.credentials {
            state.target?.credentials = .jpakeResume(derivedSecret: derivedSecret)
            emit(.paired(.jpakeResume(derivedSecret: derivedSecret)))
        }
        state.connection?.handshake = LinkReducer.handshakeReads()
        setPhase(.handshaking)
        sendNextHandshakeRead()
    }

    func authenticationFailed(rejected: Bool) {
        guard state.phase == .authenticating, let id = state.connection?.peripheralID else { return }
        if rejected {
            closeConnection(.authenticationFailed(rejected: true))
            transport(.cancelConnection(id))
            setPhase(.failed(.authenticationRejected))
        } else {
            dropped(.authenticationFailed(rejected: false), exempt: false, cancel: true)
        }
    }

    func failHandshake() {
        dropped(.handshakeFailed, exempt: false, cancel: true)
    }

    func becomeReady() {
        guard let connection = state.connection else { return }
        state.connection?.readyAt = now
        state.lastIdentity = connection.identity
        cancelTimer(.establishment)
        startTimer(.hold, after: config.holdWindow)
        state.telemetry.becameReady(at: now)
        setPhase(.ready)
        emit(.ready(connection.identity))
        dispatch()
    }

    // MARK: Inbound

    func notified(_ characteristic: Characteristic, _ bytes: [UInt8]) {
        guard let connection = state.connection else { return }
        if characteristic == .qualifyingEvents {
            // A raw 4-byte bitmap, not a framed message (upstream `QualifyingEvent.fromRawBtBytes`).
            let events = QualifyingEvent.decode(bytes)
            guard !events.isEmpty else { return }
            emit(.qualifyingEvents(events))
            // Clear it, as upstream does, but not while a signed write is on the wire.
            if connection.inFlight?.message.signed != true {
                transport(.write(.qualifyingEvents, [[0, 0, 0, 0]]))
            }
            return
        }
        var reassembler = connection.reassembly[characteristic] ?? PacketReassembler()
        let frame = reassembler.ingest(bytes)
        state.connection?.reassembly[characteristic] = reassembler
        if let frame { received(frame, on: characteristic) }
    }

    func received(_ frame: [UInt8], on characteristic: Characteristic) {
        guard let connection = state.connection, frame.count >= 2 else { return }
        if characteristic == .authorization, state.phase == .authenticating {
            effects.append(.authenticationFrame(frame))
            return
        }
        if let inFlight = connection.inFlight, matches(frame, on: characteristic, inFlight, connection) {
            state.connection?.inFlight = nil
            return replied(frame, on: characteristic, inFlight)
        }
        if let parsed = try? ResponseParser.parse(
            frame: frame, characteristic: characteristic, authenticationKey: connection.authKey ?? [])
        {
            emit(.unsolicited(reply(parsed, on: characteristic)))
        }
    }

    /// Whether `frame` answers the request on the wire: same characteristic, the expected reply or an
    /// op-77, and on t:slim the echoed txId. With one request in flight the opcode alone is
    /// enough elsewhere.
    func matches(_ frame: [UInt8], on characteristic: Characteristic, _ inFlight: InFlight, _ connection: Connection)
        -> Bool
    {
        guard characteristic == inFlight.characteristic else { return false }
        let opCode = frame[0]
        guard opCode == inFlight.message.props.responseOpCode || opCode == ErrorResponse.props.opCode else {
            return false
        }
        return connection.identity.model != .tslim || frame[1] == inFlight.txId
    }

    func reply(_ parsed: ResponseParser.Parsed, on characteristic: Characteristic) -> LinkReply {
        LinkReply(
            characteristic: characteristic, txId: parsed.txId, message: parsed.message,
            signedPumpTime: parsed.signedPumpTime)
    }

    func replied(_ frame: [UInt8], on characteristic: Characteristic, _ inFlight: InFlight) {
        let parsed = try? ResponseParser.parse(
            frame: frame, characteristic: characteristic, authenticationKey: state.connection?.authKey ?? [])
        guard let pending = inFlight.pending else { return handshakeReplied(parsed) }
        if inFlight.orphaned {
            // Its caller is gone, but what the reply means for the pump (probing, a drop to come) isn't.
            if let error = parsed?.message as? ErrorResponse {
                settle(after: error, pending: nil, untested: pending.untested, inFlight)
            }
            return dispatch()
        }
        let id = pending.request.id
        guard let parsed else {
            complete(id, .unknown(.invalidReply))
            return dispatch()
        }
        if let unverified = parsed.message as? UnverifiedErrorResponse {
            // Anyone on the link can write a CRC-valid frame; this isn't a refusal.
            complete(id, .unknown(.unverifiedError(unverified.reason)))
            startSettleWindow()
            return
        }
        if inFlight.message.signed && !isFresh(parsed.signedPumpTime, inFlight) {
            complete(id, .unknown(.staleSignedReply))
            return dispatch()
        }
        if let error = parsed.message as? ErrorResponse {
            cancelTimer(.request(id))
            return settle(after: error, pending: pending, untested: pending.untested, inFlight)
        }
        if let time = parsed.message as? TimeSinceResetResponse {
            state.connection?.clock = PumpClock(pumpTime: time.currentTime, receivedAt: now)
        }
        if pending.untested || !isRecordedSupported(pending.request.key) {
            recordEvidence(.supported, for: pending.request.key, note: "answered")
        }
        complete(id, .reply(reply(parsed, on: characteristic)))
        dispatch()
    }

    func handshakeReplied(_ parsed: ResponseParser.Parsed?) {
        guard let message = parsed?.message else { return failHandshake() }
        switch message {
        case let api as ApiVersionResponse:
            state.connection?.identity.apiVersion = ApiVersion(major: api.majorVersion, minor: api.minorVersion)
        case let version as PumpVersionResponse:
            state.connection?.identity.unit = PumpUnit(version)
        case let time as TimeSinceResetResponse:
            state.connection?.clock = PumpClock(pumpTime: time.currentTime, receivedAt: now)
        default:
            return failHandshake()  // an op-77 or anything else: the link can't be trusted to be set up
        }
        sendNextHandshakeRead()
    }

    /// A verified signed reply carries the pump's own time (pumpx2's captures show it a few seconds
    /// after the request's stamp). One older than the request, or newer than the pump can be now, is
    /// not this request's reply: a replay after txIds wrap would be. Upstream doesn't check this.
    func isFresh(_ signedPumpTime: UInt32?, _ inFlight: InFlight) -> Bool {
        guard let replyTime = signedPumpTime.map(Double.init), let atSend = inFlight.pumpTimeAtSend,
            let clock = state.connection?.clock
        else { return false }
        let slack = config.signedReplyClockSlack
        return replyTime >= atSend - slack && replyTime <= clock.estimate(at: now) + slack
    }

    // MARK: op-77

    /// Holds an op-77's verdict for the settle window: nothing else is sent, and a drop inside it is the
    /// pump's answer to this error.
    func settle(after error: ErrorResponse, pending: Pending?, untested: Bool, _ inFlight: InFlight) {
        if untested && !inFlight.message.signed { stopProbing() }
        state.connection?.lastError = ErrorReply(
            key: MessageKey(inFlight.message), error: error, pending: pending, untested: untested,
            signed: inFlight.message.signed)
        startSettleWindow()
    }

    func startSettleWindow() {
        state.connection?.settleUntil = now + config.errorSettleWindow
        startTimer(.settle, after: config.errorSettleWindow)
    }

    /// The first probe that draws an op-77 ends probing on this connection (owner, 2026-10-31); untested
    /// reads still queued are refused.
    func stopProbing() {
        guard let connection = state.connection, !connection.probingStopped else { return }
        state.connection?.probingStopped = true
        let stopped = connection.queue.filter { $0.untested && !$0.request.message.signed && !$0.isRetry }
        state.connection?.queue.removeAll { $0.untested && !$0.request.message.signed && !$0.isRetry }
        for pending in stopped { complete(pending.request.id, .notSent(.probeStopped)) }
    }

    /// The settle window passed with the link up: classify the op-77.
    func settleWindowPassed() {
        state.connection?.settleUntil = nil
        cancelTimer(.settle)
        guard let errorReply = state.connection?.lastError else { return dispatch() }
        state.connection?.lastError = nil
        let code = errorReply.error.errorCodeId
        var retry: Pending?
        switch code {
        case 6:
            // BAD_OPCODE: the pump says the command isn't there.
            recordEvidence(.unsupported, for: errorReply.key, note: "op-77 BAD_OPCODE")
        case 0:
            // Undefined (P1 answers this way): ambiguous without a drop. A bounded retry, then the
            // command sits out the rest of the session.
            if countUndefinedError(errorReply.key), !errorReply.signed, var pending = errorReply.pending {
                pending.isRetry = true
                retry = pending
            }
        default:
            // Transient (CRC, txId, buffer, auth): a bounded retry for a read.
            if !errorReply.signed, var pending = errorReply.pending, pending.attemptsLeft > 0 {
                pending.attemptsLeft -= 1
                pending.isRetry = true
                retry = pending
            }
        }
        if let retry {
            state.connection?.queue.insert(retry, at: 0)
        } else if let pending = errorReply.pending {
            complete(pending.request.id, .pumpError(errorReply.error))
        }
        dispatch()
    }

    /// Counts an undefined-code error for `key`; returns whether it's still within the retry budget.
    /// Past it, the command sits out the session.
    @discardableResult
    func countUndefinedError(_ key: MessageKey) -> Bool {
        let count = (state.undefinedErrors[key] ?? 0) + 1
        state.undefinedErrors[key] = count
        if count > config.readRetries {
            state.sittingOut.insert(key)
            return false
        }
        return true
    }

    func isRecordedSupported(_ key: MessageKey) -> Bool {
        guard let identity = state.connection?.identity else { return true }
        let entry = state.support.entry(
            for: key, unit: identity.unit, model: identity.model, apiVersion: identity.apiVersion)
        return entry.status == .supported
    }

    func recordEvidence(_ result: SupportEvidence.Result, for key: MessageKey, note: String) {
        guard let unit = state.connection?.identity.unit else { return }
        state.support.record(result, for: key, on: unit, note: note, at: date)
        emit(.supportMatrixChanged(state.support))
    }

    // MARK: Failures and timers

    /// A write the pump didn't acknowledge. A request of several packets can report several failures,
    /// so it's matched by txId: a later failure of the same request mustn't land on the next one.
    func writeFailed(_ characteristic: Characteristic, txId: UInt8?) {
        guard let connection = state.connection else { return }
        if state.phase == .authenticating, characteristic == .authorization {
            return authenticationFailed(rejected: false)
        }
        guard let inFlight = connection.inFlight, inFlight.characteristic == characteristic,
            txId == nil || txId == inFlight.txId
        else { return }
        state.connection?.inFlight = nil
        guard let pending = inFlight.pending else { return failHandshake() }
        if !inFlight.orphaned { complete(pending.request.id, .unknown(.writeFailed)) }
        dispatch()
    }

    func timerFired(_ timer: LinkTimer) {
        switch timer {
        case .backoff:
            if state.phase == .backingOff { startConnecting() }
        case .scan:
            guard case .scanning(let forPairing) = state.phase else { return }
            transport(.stopScan)
            if forPairing {
                state.wantsPairingScan = false
                setPhase(.failed(.pumpNotFound))
            } else {
                flap()  // a rescan never resets the ladder
            }
        case .establishment:
            switch state.phase {
            case .discovering, .authenticating, .handshaking:
                dropped(.establishmentTimedOut, exempt: false, cancel: true)
            default: break
            }
        case .hold:
            holdReached(at: now)
        case .settle:
            if state.connection?.settleUntil != nil { settleWindowPassed() }
        case .resubscribe:
            guard let lost = state.connection?.resubscribing.first else { return }
            dropped(.subscriptionLost(lost), exempt: false, cancel: true)
        case .request(let id):
            requestDeadline(id)
        }
    }

    /// The link stayed ready for the hold window: it held. The ladder resets only here (an
    /// authenticated hold), and probes may run.
    func holdReached(at time: LinkTime) {
        guard state.phase == .ready, state.connection?.heldAt == nil else { return }
        cancelTimer(.hold)
        state.connection?.heldAt = time
        state.ladder.flaps = 0
        if state.ladder.reportedUnstable {
            state.ladder.reportedUnstable = false
            emit(.connectionRestored)
        }
        dispatch()
    }

    func requestDeadline(_ id: RequestID) {
        guard let connection = state.connection else { return }
        if let inFlight = connection.inFlight, inFlight.pending?.request.id == id {
            state.connection?.inFlight = nil
            if !inFlight.orphaned { effects.append(.complete(id, .unknown(.timedOut))) }
            dispatch()
        }
    }
}

extension ConnectionTelemetry {
    mutating func record(_ span: ConnectionSpan, kept: Int, wasReady: Bool) {
        spans.append(span)
        if spans.count > kept { spans.removeFirst(spans.count - kept) }
        disconnects += 1
        closedUptime += span.duration
        if wasReady { downSince = span.closedAt }
    }

    mutating func becameReady(at now: LinkTime) {
        if let downSince { lastReconnectDuration = now - downSince }
        downSince = nil
    }
}
