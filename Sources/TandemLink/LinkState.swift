import Foundation
import TandemMessages

/// Everything the link knows. Per-connection state lives in `connection`, which is replaced on every
/// connect and dropped on every disconnect, so nothing from one connection can leak into the next.
public struct LinkState: Sendable {
    public internal(set) var config: LinkConfiguration
    public internal(set) var phase: LinkPhase = .idle
    public internal(set) var target: PumpTarget?
    public internal(set) var power: BluetoothPower = .unknown
    /// Whether the app is in the foreground. Starts false: an app relaunched in the background may never
    /// be told.
    public internal(set) var appActive = false
    public internal(set) var support = SupportMatrix()
    public internal(set) var ladder = ReconnectLadder()
    public internal(set) var telemetry = ConnectionTelemetry()
    /// Commands past the retry budget for the undefined error code, not sent until they come back. One the
    /// pump answered that way on a link that stayed up sits out the connection, so a read it fumbled (IOB,
    /// the alerts, history) is tried again on the next one. One it answered that way and then dropped the
    /// link after sits out until `retest` or another pump, because each try costs the connection.
    public var sittingOut: Set<MessageKey> { (connection?.sittingOut ?? []).union(sittingOutAfterDrops) }
    /// Undefined-code errors the link dropped after, per command, toward `sittingOutAfterDrops`.
    var undefinedErrorDrops: [MessageKey: Int] = [:]
    var sittingOutAfterDrops: Set<MessageKey> = []
    /// The open connection, from `connected` to its disconnect.
    public internal(set) var connection: Connection?
    /// Peripherals iOS handed back on relaunch, until the target is known and Bluetooth is on.
    var restored: [RestoredPeripheral] = []
    /// A pairing scan was asked for while Bluetooth was off.
    var wantsPairingScan = false
    /// The pumps a pairing scan listed, by their last sighting stronger than the floor.
    var pairingCandidates: [UUID: PairingCandidate] = [:]
    /// The pairing scan's timer was stopped by a pump taking a pairing.
    var pairingTimerStopped = false
    /// The identity from the last connection that reached ready, kept after it closes.
    public internal(set) var lastIdentity: PumpIdentity?

    public init(config: LinkConfiguration = LinkConfiguration()) {
        self.config = config
    }

    /// Whether requests can be submitted.
    public var isReady: Bool { phase == .ready }
}

/// The failures in a row that double the reconnect cooldown: drops (one after the link held included)
/// and failed connects. It resets only after an authenticated hold, or when the caller connects afresh;
/// a rescan never resets it. t:connect resets on every connect instead, which on iOS, where a pending
/// connect doesn't fail, would leave a pump that connects and drops at once retried at the base forever.
public struct ReconnectLadder: Sendable, Equatable {
    /// Failures in a row since the link last held.
    public internal(set) var flaps = 0
    /// Whether `connectionUnstable` was reported and not yet followed by `connectionRestored`.
    public internal(set) var reportedUnstable = false
    /// Drops during authentication of a first JPAKE pairing, toward `LinkFailure.pairingDropped`.
    public internal(set) var pairingDrops = 0

    public init() {}
}

struct PairingCandidate: Sendable, Equatable {
    var rssi: Int
    /// The signal last reported in `discovered`.
    var listedRSSI: Int
    var registration: PumpRegistrationState?
}

/// One connection's record, opened at `connected` and closed at its disconnect.
public struct ConnectionSpan: Sendable, Equatable {
    public var connectedAt: LinkTime
    public var closedAt: LinkTime
    public var authenticated: Bool
    /// Whether it reached ready and stayed up for the hold window.
    public var held: Bool
    public var reason: DisconnectReason
    /// Flaps in a row after this connection closed.
    public var flapsAfter: Int

    public var duration: Double { closedAt - connectedAt }
}

/// Connection telemetry, kept by the state machine itself so connects and disconnects always pair up
/// and the numbers can be compared (the old counters couldn't: "190 connects" with 14 minutes of
/// uptime and no way to tell why).
public struct ConnectionTelemetry: Sendable, Equatable {
    /// The latest closed connections, oldest first.
    public internal(set) var spans: [ConnectionSpan] = []
    /// Pending connects issued; each ends in a connect, a failed connect, or still pending.
    public internal(set) var connectAttempts = 0
    public internal(set) var failedConnects = 0
    public internal(set) var connects = 0
    public internal(set) var disconnects = 0
    /// Summed from closed spans.
    public internal(set) var closedUptime: Double = 0
    /// When the link last went from ready to down, until it's ready again.
    public internal(set) var downSince: LinkTime?
    /// The last time from a drop to ready again.
    public internal(set) var lastReconnectDuration: Double?

    public init() {}

    /// Uptime including the open connection.
    public func uptime(openSince: LinkTime?, now: LinkTime) -> Double {
        closedUptime + (openSince.map { now - $0 } ?? 0)
    }
}

/// The open connection.
public struct Connection: Sendable {
    public internal(set) var peripheralID: UUID
    public internal(set) var connectedAt: LinkTime
    public internal(set) var identity: PumpIdentity
    /// Characteristics the pump service exposes. Optional ones may be missing on old firmware.
    public internal(set) var present: Set<Characteristic> = []
    /// Subscriptions the pump confirmed.
    public internal(set) var subscribed: Set<Characteristic> = []
    /// Present characteristics whose first subscription failed; requests on them are refused.
    public internal(set) var unavailable: Set<Characteristic> = []
    var reassembly: [Characteristic: PacketReassembler] = [:]
    /// Next transaction id. pumpx2 starts every connection at 0.
    var nextTxId: UInt8 = 0
    /// Set once the handshake confirms the pairing.
    var authKey: [UInt8]?
    public internal(set) var authenticatedAt: LinkTime?
    public internal(set) var readyAt: LinkTime?
    /// Set when the hold window passed while ready.
    public internal(set) var heldAt: LinkTime?
    public internal(set) var clock: PumpClock?
    /// The handshake reads still to send, in order.
    var handshake: [any Message] = []
    /// Requests waiting to go out, oldest first.
    var queue: [Pending] = []
    var inFlight: InFlight?
    /// Nothing is sent before this, after an op-77 (`errorSettleWindow`).
    var settleUntil: LinkTime?
    /// The op-77 the settle window follows, so a drop inside it can be tied to it.
    var lastError: ErrorReply?
    /// Set when a probe on this connection drew an op-77; untested reads are refused after that.
    public internal(set) var probingStopped = false
    /// Undefined-code errors per command on this connection with the link staying up, toward `sittingOut`.
    var undefinedErrors: [MessageKey: Int] = [:]
    public internal(set) var sittingOut: Set<MessageKey> = []
    /// Adopted from state restoration rather than connected by this process.
    public internal(set) var adoptedFromRestore = false
    /// A dropped subscription being restored.
    var resubscribing: Set<Characteristic> = []
    /// A qualifying-events notice came while a signed write was on the wire, so its clear waits for the
    /// wire to free.
    var qualifyingEventsClearOwed = false
}

/// A request waiting to go out.
struct Pending: Sendable {
    var request: LinkRequest
    /// Untested on this pump: it goes alone, after the link held (a probe for a read).
    var untested: Bool
    var attemptsLeft: Int
    /// The op-77 an earlier attempt drew, for a queued retry.
    var previousError: ErrorResponse?
}

/// The one request on the wire.
struct InFlight: Sendable {
    /// nil for a handshake read.
    var pending: Pending?
    var message: any Message
    var txId: UInt8
    /// The pump time estimated when it was sent, for the signed-reply freshness check.
    var pumpTimeAtSend: Double?
    /// The caller cancelled it after it went out: its reply is awaited only to keep the slot busy, so a
    /// late reply can't be taken for the next request's.
    var orphaned = false

    var characteristic: Characteristic { message.characteristic }
}

/// An op-77 reply whose verdict waits for the settle window, because a drop inside it changes what the
/// reply means.
struct ErrorReply: Sendable {
    var key: MessageKey
    var error: ErrorResponse
    var pending: Pending?
    var untested: Bool
    var signed: Bool
}
