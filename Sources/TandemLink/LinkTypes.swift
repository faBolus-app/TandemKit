import Foundation
import TandemMessages

// The connection state machine's vocabulary. `LinkReducer.reduce(_:_:)` turns a `LinkState` and a
// `LinkInput` into a new state and `[LinkEffect]`; nothing here imports CoreBluetooth, so every
// transition runs in a plain unit test. `PumpConnection` (TandemBLE) performs the effects.
//
// Each number with no pump observation behind it says "guess".

/// Seconds on a monotonic clock that keeps counting while the phone sleeps (`ContinuousClock`). Only
/// differences between two values mean anything.
public typealias LinkTime = Double

// MARK: Configuration

/// Timings and limits. Every default is either copied from the old client or marked a guess.
public struct LinkConfiguration: Sendable, Equatable {
    /// How long an authenticated, handshaken link must stay up before it counts as held: the ladder
    /// resets, probes may run, and a later drop reconnects at once. Guess: well past P1's drop 2.0 s
    /// after pairing, so that drop stays a flap. Mobi's renegotiation drop at about 15 s
    /// would need a longer window when Mobi is built.
    public var holdWindow: Double = 10
    /// The wait before reconnecting after a drop or a failed connect, as t:connect waits: a base set by
    /// the error, doubled for each failure in a row before it (`ReconnectLadder.flaps`), up to
    /// `cooldownCap`. Reconnecting never stops. t:connect's bases are for Android's error codes; these are
    /// CoreBluetooth's nearest (`LinkReducer`'s cooldown base), a guess until a range-edge bench.
    public var cooldown: Double = 1
    /// The base after a supervision timeout (`CBError.connectionTimeout`), the drop at the edge of range:
    /// t:connect's for Android's link-layer timeout.
    public var cooldownAfterTimeout: Double = 3
    /// The base after a connect that failed (`didFailToConnect`): t:connect's for Android's generic
    /// error, which is how a connect fails there.
    public var cooldownAfterFailedConnect: Double = 10
    public var cooldownCap: Double = 30
    /// Flaps in a row before `connectionUnstable` is reported. Guess.
    public var unstableAfterFlaps = 3
    /// Drops during authentication of a first JPAKE pairing that end it as `pairingDropped`: one retry for
    /// the radio, then the code is taken as wrong. Guess, from Mobi taking one drop there as a wrong code.
    public var pairingDropsToFail = 2
    /// From `connected` to ready (services, subscriptions, authentication, handshake). The old
    /// client's establishment bound.
    public var establishmentTimeout: Double = 30
    /// How long a scan for a known pump runs before it counts as a flap (the old client's bound).
    public var scanTimeout: Double = 30
    /// A pairing scan fails as `pumpNotFound` after this long, unless the strongest pump found advertises
    /// that it is accepting connections first (Mobi's pump timer). The scan itself runs until it is
    /// stopped or a pump is picked.
    public var pairingScanTimeout: Double = 120
    /// A pump this weak or weaker isn't listed for pairing (Mobi and t:connect: -75 dBm). CoreBluetooth's
    /// 127, signal unknown, passes, as Mobi's does.
    public var pairingRSSIFloor = -75
    /// A listed pump is reported again when its signal moves by this many dB, not on every advertisement.
    public var pairingRSSIStep = 5
    /// After an op-77 reply nothing else is sent for this long, so a drop that follows can be tied to
    /// the reply. On P1 the drop came about 90 ms after the error; 1 s is a guess with margin.
    public var errorSettleWindow: Double = 1
    /// Extra attempts for a read answered with a transient op-77 or the undefined code. Guess.
    public var readRetries = 1
    /// How far a verified signed reply's pump time may sit outside the pump time estimated from the
    /// last TimeSinceReset read plus the phone's elapsed time. Guess: the pump stamps whole seconds and
    /// the two clocks drift by far less than this over a connection.
    public var signedReplyClockSlack: Double = 10
    /// Models the release connects to (the t:slim X2 only; Mobi is designed for, not built).
    public var supportedModels: Set<PumpModel> = [.tslim]
    /// Closed connections kept in telemetry.
    public var spansKept = 50

    public init() {}
}

// MARK: Pairing and identity

/// How the link authenticates, held with the pairing by the caller.
public enum PairingCredentials: Sendable, Equatable {
    /// Legacy pairing with the 16-character code. It has no resume: every connection runs the
    /// full challenge again, silently.
    case legacy(code: String)
    /// A first JPAKE pairing with the 6-digit code. On success the link reports the derived secret
    /// (`LinkEvent.paired`), and later connections use `jpakeResume`.
    case jpake(code: String)
    /// A JPAKE reconnect from the stored derived secret (rounds 3 and 4 only).
    case jpakeResume(derivedSecret: [UInt8])
}

/// The pump the link is kept up with. Stored with the pairing, because a restored or retrieved
/// reconnect has no advertisement to read the model from.
public struct PumpTarget: Sendable, Equatable {
    public var peripheralID: UUID
    /// The model from the advertised name prefix when the pump was paired; nil if it was never seen.
    public var model: PumpModel?
    public var credentials: PairingCredentials

    public init(peripheralID: UUID, model: PumpModel?, credentials: PairingCredentials) {
        self.peripheralID = peripheralID
        self.model = model
        self.credentials = credentials
    }
}

/// The model from a Bluetooth name, by the prefixes pumpx2 uses. Never from the API version.
public func pumpModel(advertisedName name: String?) -> PumpModel? {
    guard let name else { return nil }
    if name.hasPrefix("tslim X2") { return .tslim }
    if name.hasPrefix("Tandem Mobi") { return .mobi }
    return nil
}

/// Whether an advertising pump takes a new pairing, from Tandem's manufacturer data (company ID 0x059D):
/// format byte 0 = 0, then the authentication method, then the pump type in the high nibble and this
/// state in the low one, as both Tandem apps read it. A Mobi advertises it; nothing shows a t:slim X2
/// does (both apps take a t:slim with no data as one with no state), so for one it is usually nil.
public enum PumpRegistrationState: UInt8, Sendable, Equatable {
    /// NONE in both apps; not `none`, which would read as `Optional.none` beside an optional state.
    case noState = 0
    case acceptingConnections = 1
    case registered = 2
    case notAcceptingConnections = 5
    case readyToPair = 7

    /// The state in CoreBluetooth's manufacturer data, or nil when it isn't Tandem's or names no state.
    public init?(manufacturerData data: [UInt8]?) {
        guard let data, data.count >= 5, data[0] == 0x9D, data[1] == 0x05, data[2] == 0 else { return nil }
        self.init(rawValue: data[4] & 0x0F)
    }
}

/// What the link learned about the pump on this connection.
public struct PumpIdentity: Sendable, Equatable {
    public var model: PumpModel?
    public var advertisedName: String?
    /// The Device Information Service model number, when the pump exposes it. Recorded, not decided on.
    public var modelNumber: String?
    public var apiVersion: ApiVersion?
    public var unit: PumpUnit?

    public init(
        model: PumpModel? = nil, advertisedName: String? = nil, modelNumber: String? = nil,
        apiVersion: ApiVersion? = nil, unit: PumpUnit? = nil
    ) {
        self.model = model
        self.advertisedName = advertisedName
        self.modelNumber = modelNumber
        self.apiVersion = apiVersion
        self.unit = unit
    }
}

/// The pump's clock as of the last TimeSinceReset reply.
public struct PumpClock: Sendable, Equatable {
    /// `TimeSinceResetResponse.currentTime`: what signed requests are stamped with (pumpx2 and the old
    /// app both sign with the last value read, not an extrapolation).
    public var pumpTime: UInt32
    /// When the reply arrived.
    public var receivedAt: LinkTime

    public init(pumpTime: UInt32, receivedAt: LinkTime) {
        self.pumpTime = pumpTime
        self.receivedAt = receivedAt
    }

    /// The pump's time now, estimated from the reply and the phone's elapsed time.
    public func estimate(at now: LinkTime) -> Double { Double(pumpTime) + (now - receivedAt) }
}

// MARK: Bluetooth

public enum BluetoothPower: String, Sendable, Equatable, Codable {
    case unknown, resetting, unsupported, unauthorized, poweredOff, poweredOn
}

/// A Bluetooth error, as plain values (CoreBluetooth's `NSError` domain and code).
public struct BluetoothError: Sendable, Equatable, Codable {
    public var domain: String
    public var code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

// MARK: Phases and reasons

/// Where the link is. Each phase's own data lives in `LinkState.connection` (per connection) or in
/// `LinkState` itself, so nothing about the link is kept anywhere else.
public enum LinkPhase: Sendable, Equatable {
    /// Nothing to connect to: no target, or the caller stopped the link.
    case idle
    /// A target is set but Bluetooth isn't powered on.
    case waitingForBluetooth
    /// Scanning, for pairing (`forPairing`) or because the target's handle couldn't be retrieved.
    case scanning(forPairing: Bool)
    /// A pending `connect()` is out. It has no timeout: CoreBluetooth completes it when the pump is in
    /// range, also while the app is suspended.
    case connecting
    /// Connected: services, characteristics and subscriptions.
    case discovering
    case authenticating
    /// Authenticated; the post-authentication reads (ApiVersion, PumpVersion, TimeSinceReset).
    case handshaking
    /// Authenticated and handshaken: requests may be sent.
    case ready
    /// After a drop or a failed connect, waiting out the cooldown before the next pending connect.
    case backingOff
    /// Stopped on something the user has to fix; no automatic retry.
    case failed(LinkFailure)
}

/// Why the link stopped for good, until the caller connects again.
public enum LinkFailure: Sendable, Equatable {
    /// The pump rejected the pairing code or the key confirmation.
    case authenticationRejected
    /// The pump's Bluetooth name names a model the release doesn't connect to.
    case unsupportedModel(PumpModel)
    /// The pump's Bluetooth name contradicts the model stored with the pairing.
    case identityMismatch(stored: PumpModel, seen: PumpModel)
    /// A pairing scan found nothing in time.
    case pumpNotFound
    /// A first JPAKE pairing's link dropped during authentication twice in a row. Mobi takes a drop there as
    /// the pump's answer to a wrong code.
    case pairingDropped
}

/// Why a connection closed. Each connection's span ends with exactly one of these.
public enum DisconnectReason: Sendable, Equatable {
    /// The caller stopped the link.
    case requested
    /// Bluetooth went off, unauthorized or resetting.
    case bluetoothUnavailable(BluetoothPower)
    /// The link dropped; the error is CoreBluetooth's when it gave one.
    case linkLost(BluetoothError?)
    /// The link dropped within the settle window after the pump rejected a request it doesn't support,
    /// as P1 does after an op-77. Not counted as instability.
    case afterUnsupportedRequest(MessageKey, errorCode: Int)
    /// The link dropped within the settle window after an op-77 that doesn't say the command is
    /// unsupported (an undefined or transient code).
    case afterErrorReply(MessageKey, errorCode: Int)
    /// The connection didn't reach ready within `establishmentTimeout`; the link cancelled it.
    case establishmentTimedOut
    /// The pump lacks a required characteristic or a subscription failed.
    case setupFailed
    /// A post-authentication read failed.
    case handshakeFailed
    case authenticationFailed(rejected: Bool)
    /// The pump's service was invalidated; the link cancelled the connection.
    case servicesInvalidated
    /// A dropped subscription wasn't restored in time; the link cancelled the connection.
    case subscriptionLost(Characteristic)
    /// The Bluetooth name contradicted the stored model, or names an unsupported model.
    case identityRejected
}

// MARK: Requests

public typealias RequestID = UInt64

/// One request from the caller. The caller grants the risk it may carry for this one request only
///, so no elevation can outlive the call.
public struct LinkRequest: Sendable {
    public var id: RequestID
    public var message: any Message
    /// The highest risk this call allows. A message above it is refused before a byte is built.
    public var allowing: OperationRisk
    /// Seconds from when it goes out to its reply.
    public var deadline: Double

    public init(id: RequestID, message: any Message, allowing: OperationRisk, deadline: Double) {
        self.id = id
        self.message = message
        self.allowing = allowing
        self.deadline = deadline
    }

    var key: MessageKey { MessageKey(message) }
}

/// A reply the pump sent, parsed.
public struct LinkReply: Sendable {
    public let characteristic: Characteristic
    public let txId: UInt8
    public let message: any Message
    /// The verified trailer's pump time, for a signed reply.
    public let signedPumpTime: UInt32?

    public init(characteristic: Characteristic, txId: UInt8, message: any Message, signedPumpTime: UInt32?) {
        self.characteristic = characteristic
        self.txId = txId
        self.message = message
        self.signedPumpTime = signedPumpTime
    }

    public var opCode: UInt8 { message.opCode }
}

extension LinkReply: Equatable {
    public static func == (a: LinkReply, b: LinkReply) -> Bool {
        a.characteristic == b.characteristic && a.txId == b.txId && a.opCode == b.opCode
            && a.message.cargo == b.message.cargo && a.signedPumpTime == b.signedPumpTime
    }
}

/// Why a request wasn't sent. Nothing reached the pump, so nothing happened there.
public enum NotSentReason: Sendable, Equatable {
    /// The link isn't ready.
    case notReady
    /// The message's risk is above what the call allowed.
    case writeBlocked(OperationRisk)
    /// A signed write outside `SupportMatrix.allowedSignedWrites`.
    case signedWriteNotAllowed
    /// The model isn't known, and the message is restricted to some models.
    case identityUnknown
    /// This pump doesn't support it: per its model, or recorded for this unit and firmware.
    case unsupported
    /// It drew the undefined error code more than the retry budget, so P1's error 0 can't loop: on this
    /// connection with the link up (it sits out the connection), or with the link dropping after it (it
    /// sits out until retested or another pump is connected).
    case sittingOut
    /// It's untested here, and an earlier probe on this connection drew an op-77 (probing stops then).
    case probeStopped
    /// The pump doesn't expose the characteristic it goes on.
    case characteristicUnavailable
    case cancelled
    /// It couldn't be framed (`Packetize` refused it).
    case encodingFailed
    /// The link dropped before it was sent.
    case connectionLost
}

/// Why a sent request has no definite answer. For a signed write the outcome is unknown: the app must
/// not start a new bolus until it's settled.
public enum UnknownReason: Sendable, Equatable {
    case timedOut
    case connectionLost
    /// The write itself failed after some packets may have gone out.
    case writeFailed
    case cancelled
    /// A reply came that couldn't be parsed or whose signature didn't verify.
    case invalidReply
    /// An op-77 on CONTROL whose HMAC didn't verify (`UnverifiedErrorResponse`): not a refusal.
    case unverifiedError(UnverifiedErrorResponse.Reason)
    /// A verified signed reply whose pump time doesn't fit this request, as a replayed old reply
    /// wouldn't once txIds wrap.
    case staleSignedReply
}

/// How a request ended. Exactly one result per submitted request.
public enum RequestResult: Sendable, Equatable {
    /// The pump answered with the expected reply (verified, if signed). For a signed write this is an
    /// authenticated answer; what it says (granted, refused) is in the message.
    case reply(LinkReply)
    /// The pump answered with op-77. For a signed write it verified, so it's an authenticated reject.
    case pumpError(ErrorResponse)
    /// Refused before a byte went out.
    case notSent(NotSentReason)
    /// Sent, with no definite answer.
    case unknown(UnknownReason)
}


// MARK: Inputs

/// Timers the reducer arms. One of each kind at a time, except request deadlines.
public enum LinkTimer: Hashable, Sendable {
    case scan
    case establishment
    case backoff
    case hold
    case settle
    case resubscribe
    case request(RequestID)
}

/// Everything that can happen to the link.
public enum LinkInput: Sendable {
    // From the caller
    /// Keep the link up with this pump. Starts a fresh ladder.
    case connect(PumpTarget, SupportMatrix)
    /// Scan for pumps to pair with.
    case scanForPairing
    /// Stop: close the connection and don't reconnect.
    case stop
    /// The app came to the foreground (true) or went to the background (false).
    case appActive(Bool)
    case submit(LinkRequest)
    case cancel(RequestID)
    /// Forget this unit's recorded evidence for a command, so it's probed again.
    case retest(MessageKey)

    // From Bluetooth
    case power(BluetoothPower)
    /// iOS relaunched the app and restored these peripherals (`willRestoreState`).
    case restored([RestoredPeripheral])
    /// A pump's advertisement. `manufacturerData` is CoreBluetooth's, the company ID first.
    case discovered(peripheralID: UUID, name: String?, rssi: Int, manufacturerData: [UInt8]? = nil)
    /// The transport has no handle for the target (`retrievePeripherals` found nothing).
    case peripheralUnavailable(UUID)
    case connected(peripheralID: UUID, name: String?)
    case connectFailed(peripheralID: UUID, BluetoothError?)
    case disconnected(peripheralID: UUID, BluetoothError?)
    /// The pump service's characteristics, as discovered.
    case characteristicsDiscovered(Set<Characteristic>)
    case subscription(Characteristic, isNotifying: Bool, failed: Bool)
    case deviceInformation(modelNumber: String?)
    /// The pump's service was invalidated (`didModifyServices`): its characteristics are gone.
    case servicesInvalidated
    /// One notification packet (or the 4-byte qualifying-events bitmap).
    case notified(Characteristic, [UInt8])
    /// A write the pump didn't acknowledge, with the txId of the packet that failed when known.
    case writeFailed(Characteristic, txId: UInt8?)

    // From the authentication handshake (run by the driver)
    case authenticationRequest(any Message)
    case authenticated(key: [UInt8], derivedSecret: [UInt8]?)
    case authenticationFailed(rejected: Bool)

    case timerFired(LinkTimer)
    /// The background time that kept a cooldown's timer running in the background is ending
    /// (`LinkBackgroundTime`). Suspended, the timer wouldn't fire, so the pending connect goes out now.
    case backgroundTimeEnding
}

/// A peripheral handed back by state restoration.
public struct RestoredPeripheral: Sendable, Equatable {
    public var peripheralID: UUID
    public var isConnected: Bool
    public var name: String?

    public init(peripheralID: UUID, isConnected: Bool, name: String?) {
        self.peripheralID = peripheralID
        self.isConnected = isConnected
        self.name = name
    }
}

// MARK: Effects

/// What the driver does with Bluetooth.
public enum TransportCommand: Sendable, Equatable {
    /// Scan for the pump service. `repeats` reports every advertisement, not just a pump's first: a
    /// pairing scan lists a pump that comes into range only once it is close enough.
    case scan(repeats: Bool)
    case stopScan
    /// Resolve the peripheral by identifier and issue a pending connect. Reports
    /// `peripheralUnavailable` when it can't be resolved.
    case connect(UUID)
    case cancelConnection(UUID)
    /// Set up this connected peripheral: it becomes the one the transport writes to and listens to.
    case discover(UUID)
    case subscribe(Characteristic)
    case readDeviceInformation
    /// Write each packet, in order, with response.
    case write(Characteristic, [[UInt8]])
}

/// What the link tells its owner.
public enum LinkEvent: Sendable, Equatable {
    case phase(LinkPhase)
    case discovered(peripheralID: UUID, name: String?, model: PumpModel?, rssi: Int)
    /// A first JPAKE pairing succeeded: store these credentials with the pairing.
    case paired(PairingCredentials)
    case ready(PumpIdentity)
    case disconnected(DisconnectReason, ConnectionSpan)
    /// Flaps have reached `unstableAfterFlaps`.
    case connectionUnstable(flaps: Int)
    /// The link held after being reported unstable.
    case connectionRestored
    /// Persist the matrix with the pairing.
    case supportMatrixChanged(SupportMatrix)
    /// A frame no request was waiting for: a history-log or control stream, or a stray reply.
    case unsolicited(LinkReply)
    /// The pump answered a request after its caller cancelled it (the caller got `.unknown(.cancelled)`).
    /// For a signed write this can be the definite outcome.
    case cancelledRequestAnswered(RequestID, RequestResult)
    case qualifyingEvents(QualifyingEvent)
}

public enum LinkEffect: Sendable, Equatable {
    case transport(TransportCommand)
    case startTimer(LinkTimer, after: Double)
    case cancelTimer(LinkTimer)
    /// Begin the pairing handshake with these credentials.
    case startAuthentication(PairingCredentials)
    /// Hand an AUTHORIZATION frame to the handshake.
    case authenticationFrame([UInt8])
    /// Drop the handshake (the connection it belonged to is gone).
    case endAuthentication
    case complete(RequestID, RequestResult)
    case emit(LinkEvent)
}
