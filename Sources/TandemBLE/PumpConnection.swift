import Foundation
import TandemAuth
import TandemLink
import TandemMessages
import os

/// Fixed literal subsystem/category, so `log show` matches on any developer's build:
///   `log show <archive> --predicate 'subsystem == "com.fabolus.app" AND category == "ble"' --info`
let linkLog = Logger(subsystem: "com.fabolus.app", category: "ble")

/// What the link needs from Bluetooth. `CoreBluetoothTransport` is the real one; tests use a scripted
/// stand-in. A transport only converts: it performs commands and reports what Bluetooth did, and keeps
/// no link state of its own beyond the handles CoreBluetooth needs retained.
@MainActor
public protocol LinkTransport: AnyObject {
    /// Set by `PumpConnection`; the transport reports every Bluetooth event through it.
    var report: ((LinkInput) -> Void)? { get set }
    func perform(_ command: TransportCommand)
}

/// A monotonic clock and one-shot timers.
@MainActor
public protocol LinkClock: AnyObject {
    var now: LinkTime { get }
    /// Runs `action` once after `seconds`, unless the returned token is cancelled first.
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any LinkClockToken
}

@MainActor
public protocol LinkClockToken: AnyObject {
    func cancel()
}

/// The pairing handshake as the driver runs it: JPAKE or legacy (`PairingCoordinating`).
public typealias AuthenticatorFactory = @MainActor (PairingCredentials) throws -> any PairingCoordinating

/// The link to one pump: runs `LinkReducer` and performs its effects. Everything the link knows is in
/// `state`; this class keeps only what can't be a value (the transport, timers, the handshake object and
/// the callers' continuations), and each of those is driven by an effect.
@MainActor
public final class PumpConnection {
    public private(set) var state: LinkState
    /// The link's clock now, to read `state`'s times against (telemetry uptime, for one).
    public var now: LinkTime { clock.now }
    /// The link's events, in order. One consumer.
    public let events: AsyncStream<LinkEvent>

    private let transport: LinkTransport
    private let clock: LinkClock
    private let makeAuthenticator: AuthenticatorFactory
    private let eventSink: AsyncStream<LinkEvent>.Continuation
    private var authenticator: (any PairingCoordinating)?
    private var timers: [LinkTimer: (generation: UInt64, token: any LinkClockToken)] = [:]
    private var timerGeneration: UInt64 = 0
    private var waiting: [RequestID: CheckedContinuation<RequestResult, Never>] = [:]
    private var nextRequestID: RequestID = 1
    private var inbox: [LinkInput] = []
    private var processing = false
    /// Every event, in order, for tests in this module.
    var observer: ((LinkEvent) -> Void)?

    /// A link over CoreBluetooth. `restoreIdentifier` opts in to state preservation and restoration:
    /// iOS then relaunches the app for pump events after it was terminated (not after a force quit), and
    /// the link picks up the restored connection. Needs the `bluetooth-central` background mode.
    public convenience init(restoreIdentifier: String?, config: LinkConfiguration = LinkConfiguration()) {
        self.init(
            transport: CoreBluetoothTransport(restoreIdentifier: restoreIdentifier), clock: ContinuousLinkClock(),
            config: config)
    }

    public init(
        transport: LinkTransport, clock: LinkClock, config: LinkConfiguration = LinkConfiguration(),
        makeAuthenticator: @escaping AuthenticatorFactory = PumpConnection.defaultAuthenticator
    ) {
        self.state = LinkState(config: config)
        self.transport = transport
        self.clock = clock
        self.makeAuthenticator = makeAuthenticator
        var sink: AsyncStream<LinkEvent>.Continuation!
        self.events = AsyncStream { sink = $0 }
        self.eventSink = sink
        transport.report = { [weak self] input in self?.feed(input) }
    }

    // MARK: Caller

    /// Keeps the link up with `target`, starting a fresh reconnect ladder. `support` is the matrix
    /// stored with the pairing; changes come back as `supportMatrixChanged`.
    public func connect(to target: PumpTarget, support: SupportMatrix) { feed(.connect(target, support)) }

    /// Scans for pumps to pair with; each one found comes as `discovered`.
    public func scanForPairing() { feed(.scanForPairing) }

    /// Closes the link and stops reconnecting.
    public func stop() { feed(.stop) }

    /// Tell the link when the app enters or leaves the foreground.
    public func setAppActive(_ active: Bool) { feed(.appActive(active)) }

    /// Forgets this pump's recorded result for a command, so it's probed again (a developer setting).
    public func retest(_ key: MessageKey) { feed(.retest(key)) }

    /// Sends `message` and waits for how it ended. `allowing` is the highest risk this one call grants
    ///: pass `.delivery` only for the single delivery call. A signed write is sent at most once;
    /// anything but `.reply` or `.pumpError` after it went out is `.unknown`.
    public func send(
        _ message: any Message, allowing: OperationRisk = .read, deadline: Double = 10
    ) async -> RequestResult {
        if Task.isCancelled { return .notSent(.cancelled) }
        let id = nextRequestID
        nextRequestID += 1
        let request = LinkRequest(id: id, message: message, allowing: allowing, deadline: deadline)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiting[id] = continuation
                feed(.submit(request))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.feed(.cancel(id)) }
        }
    }

    // MARK: Running the state machine

    /// Inputs are applied one at a time, in order. An input raised while effects are being performed
    /// (the handshake answering synchronously, a transport reporting at once) waits its turn, so the
    /// reducer never runs inside itself.
    func feed(_ input: LinkInput) {
        inbox.append(input)
        guard !processing else { return }
        processing = true
        defer { processing = false }
        while !inbox.isEmpty {
            let next = inbox.removeFirst()
            let (newState, effects) = LinkReducer.reduce(
                state, next, now: clock.now, date: Date(), jitter: Double.random(in: 0..<1))
            state = newState
            for effect in effects { perform(effect) }
        }
    }

    private func perform(_ effect: LinkEffect) {
        switch effect {
        case .transport(let command):
            transport.perform(command)
        case .startTimer(let timer, let seconds):
            timers[timer]?.token.cancel()
            timerGeneration += 1
            let generation = timerGeneration
            let token = clock.schedule(after: seconds) { [weak self] in
                guard let self, self.timers[timer]?.generation == generation else { return }
                self.timers[timer] = nil
                self.feed(.timerFired(timer))
            }
            timers[timer] = (generation, token)
        case .cancelTimer(let timer):
            timers.removeValue(forKey: timer)?.token.cancel()
        case .startAuthentication(let credentials):
            startAuthentication(credentials)
        case .authenticationFrame(let frame):
            authenticator?.handle(frame: frame)
        case .endAuthentication:
            authenticator = nil
        case .complete(let id, let result):
            waiting.removeValue(forKey: id)?.resume(returning: result)
        case .emit(let event):
            log(event)
            observer?(event)
            eventSink.yield(event)
        }
    }

    private func startAuthentication(_ credentials: PairingCredentials) {
        let authenticator: any PairingCoordinating
        do {
            authenticator = try makeAuthenticator(credentials)
        } catch {
            // A malformed stored code can't succeed on retry.
            feed(.authenticationFailed(rejected: true))
            return
        }
        self.authenticator = authenticator
        let full: Bool
        if case .jpake = credentials { full = true } else { full = false }
        authenticator.onSendRequest = { [weak self] message in self?.feed(.authenticationRequest(message)) }
        authenticator.onPaired = { [weak self, weak authenticator] key, _ in
            let secret = full ? (authenticator as? PairingCoordinator)?.derivedSecret : nil
            self?.feed(.authenticated(key: key, derivedSecret: secret))
        }
        authenticator.onError = { [weak self] error in
            self?.feed(.authenticationFailed(rejected: Self.isRejection(error)))
        }
        authenticator.start()
    }

    /// The pump saying the code is wrong, as opposed to a frame lost or garbled on the way.
    nonisolated static func isRejection(_ error: Error) -> Bool {
        switch error {
        case LegacyPairingCoordinator.PairingError.pairingRejected: return true
        case PairingCoordinator.PairingError.keyConfirmationFailed: return true
        default: return false
        }
    }

    public static let defaultAuthenticator: AuthenticatorFactory = { credentials in
        switch credentials {
        case .legacy(let code): return try LegacyPairingCoordinator(pairingCode: code)
        case .jpake(let code): return try PairingCoordinator(pairingCode: code)
        case .jpakeResume(let secret): return PairingCoordinator(resumeDerivedSecret: secret)
        }
    }

    private func log(_ event: LinkEvent) {
        // Phase and reason names are not health data, so they're public and survive a pulled archive.
        switch event {
        case .phase(let phase):
            linkLog.log("link phase → \(String(describing: phase), privacy: .public)")
        case .disconnected(let reason, let span):
            linkLog.log(
                "link closed reason=\(String(describing: reason), privacy: .public) up=\(span.duration, privacy: .public)s held=\(span.held, privacy: .public) flaps=\(span.flapsAfter, privacy: .public)"
            )
        case .connectionUnstable(let flaps):
            linkLog.log("link unstable flaps=\(flaps, privacy: .public)")
        default:
            break
        }
    }
}

/// `ContinuousClock`, which keeps counting while the phone sleeps, and timers as main-actor tasks.
/// A timer can't fire while iOS has the app suspended; the reducer accounts for that.
@MainActor
public final class ContinuousLinkClock: LinkClock {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: LinkTime {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    public func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any LinkClockToken {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskToken(task: task)
    }

    private final class TaskToken: LinkClockToken {
        let task: Task<Void, Never>
        init(task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }
}
