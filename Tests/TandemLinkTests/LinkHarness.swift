import Foundation
import Testing
import TandemMessages
@testable import TandemLink

/// Drives `LinkReducer` by hand: feeds inputs at a chosen time, keeps every effect, and checks after
/// each step that every submitted request completes exactly once and nothing completes twice.
struct LinkHarness {
    var state: LinkState
    var now: LinkTime = 0
    /// Effects of the last input.
    var last: [LinkEffect] = []
    /// Every effect so far.
    var all: [LinkEffect] = []
    /// Results by request, in the order they came.
    var results: [RequestID: RequestResult] = [:]
    var submitted: Set<RequestID> = []
    var nextID: RequestID = 1
    /// Timers armed and not cancelled or fired, with when they're due.
    var timers: [LinkTimer: LinkTime] = [:]
    /// The random number the driver would draw for each input.
    var jitter: Double = 0

    static let pumpID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let legacyCode = "ABCDEFGHIJKLMNOP"
    static let key = Array(legacyCode.utf8)
    static let p1Unit = PumpUnit(serialNumber: 1693, armSoftwareVersion: 1, mspSoftwareVersion: 2)
    static let p2Unit = PumpUnit(serialNumber: 2000, armSoftwareVersion: 7, mspSoftwareVersion: 7)

    /// Starts in the foreground, as most tests want; the link itself starts assuming the background.
    init(config: LinkConfiguration = LinkConfiguration()) {
        state = LinkState(config: config)
        state.appActive = true
    }

    var phase: LinkPhase { state.phase }

    @discardableResult
    mutating func apply(_ input: LinkInput, sourceLocation: SourceLocation = #_sourceLocation) -> [LinkEffect] {
        let (newState, effects) = LinkReducer.reduce(
            state, input, now: now, date: Date(timeIntervalSince1970: 0), jitter: jitter)
        state = newState
        last = effects
        all += effects
        for effect in effects {
            switch effect {
            case .complete(let id, let result):
                #expect(results[id] == nil, "request \(id) completed twice", sourceLocation: sourceLocation)
                #expect(
                    submitted.contains(id), "request \(id) completed but never submitted",
                    sourceLocation: sourceLocation)
                results[id] = result
            case .startTimer(let timer, let after):
                timers[timer] = now + after
            case .cancelTimer(let timer):
                timers[timer] = nil
            default:
                break
            }
        }
        return effects
    }

    /// Moves the clock on, firing due timers in order, as the driver would in the foreground.
    mutating func advance(by seconds: Double) {
        let end = now + seconds
        while let (timer, due) = timers.filter({ $0.value <= end }).min(by: { $0.value < $1.value }) {
            now = max(now, due)
            timers[timer] = nil
            apply(.timerFired(timer))
        }
        now = end
    }

    /// Moves the clock on with no timer firing, as while iOS has the app suspended.
    mutating func sleep(for seconds: Double) { now += seconds }

    // MARK: Queries

    var commands: [TransportCommand] {
        last.compactMap { if case .transport(let c) = $0 { return c } else { return nil } }
    }
    var allCommands: [TransportCommand] {
        all.compactMap { if case .transport(let c) = $0 { return c } else { return nil } }
    }
    var events: [LinkEvent] { last.compactMap { if case .emit(let e) = $0 { return e } else { return nil } } }
    var allEvents: [LinkEvent] { all.compactMap { if case .emit(let e) = $0 { return e } else { return nil } } }

    /// Frames written so far, as `(characteristic, opcode, txId)` decoded from the first packet.
    var writes: [(characteristic: Characteristic, opCode: UInt8, txId: UInt8)] {
        allCommands.compactMap {
            guard case .write(let characteristic, let packets) = $0, let first = packets.first, first.count >= 4,
                characteristic != .qualifyingEvents
            else { return nil }
            return (characteristic, first[2], first[3])
        }
    }

    func writes(of type: (some Message).Type) -> Int {
        writes.filter { $0.characteristic == type.props.characteristic && $0.opCode == type.props.opCode }.count
    }

    var lastWrite: (characteristic: Characteristic, opCode: UInt8, txId: UInt8)? { writes.last }

    mutating func clearLog() {
        all = []
        last = []
    }

    // MARK: Driving

    mutating func submit(
        _ message: any Message, allowing: OperationRisk = .read, deadline: Double = 10
    ) -> RequestID {
        let id = nextID
        nextID += 1
        submitted.insert(id)
        apply(.submit(LinkRequest(id: id, message: message, allowing: allowing, deadline: deadline)))
        return id
    }

    /// Connects, authenticates and runs the handshake, ending ready.
    mutating func makeReady(
        model: PumpModel? = .tslim, name: String? = "tslim X2 ***693", api: (Int, Int) = (2, 5),
        unit: PumpUnit = LinkHarness.p1Unit, pumpTime: UInt32 = 586_961_779,
        present: Set<Characteristic> = Set(Characteristic.allCases), support: SupportMatrix = SupportMatrix()
    ) {
        if state.power != .poweredOn { apply(.power(.poweredOn)) }
        if state.target == nil {
            apply(
                .connect(
                    PumpTarget(peripheralID: Self.pumpID, model: model, credentials: .legacy(code: Self.legacyCode)),
                    support))
        }
        connectAndAuthenticate(name: name, present: present)
        answerHandshake(api: api, unit: unit, pumpTime: pumpTime)
    }

    mutating func connectAndAuthenticate(
        name: String? = "tslim X2 ***693", present: Set<Characteristic> = Set(Characteristic.allCases)
    ) {
        apply(.connected(peripheralID: Self.pumpID, name: name))
        apply(.characteristicsDiscovered(present))
        for characteristic in ServiceUUID.notificationCharacteristics where present.contains(characteristic) {
            apply(.subscription(characteristic, isNotifying: true, failed: false))
        }
        apply(
            .authenticationRequest(
                CentralChallengeRequest(appInstanceId: 0, centralChallenge: [UInt8](repeating: 1, count: 8))))
        apply(.authenticated(key: Self.key, derivedSecret: nil))
    }

    mutating func answerHandshake(
        api: (Int, Int) = (2, 5), unit: PumpUnit = LinkHarness.p1Unit, pumpTime: UInt32 = 586_961_779
    ) {
        reply(ApiVersionResponse(cargo: le16(api.0) + le16(api.1)))
        reply(PumpVersionResponse(cargo: pumpVersionCargo(unit)))
        reply(TimeSinceResetResponse(cargo: le32(pumpTime) + le32(1_000)))
    }

    /// Answers the request on the wire with `message`, echoing its txId (or `txId`).
    mutating func reply(_ message: any Message, txId: UInt8? = nil, signedAt pumpTime: UInt32? = nil) {
        guard let write = lastWrite else {
            Issue.record("nothing on the wire to answer")
            return
        }
        notify(message, txId: txId ?? write.txId, signedAt: pumpTime)
    }

    /// Delivers `message` as notification packets on its characteristic.
    mutating func notify(
        _ message: any Message, txId: UInt8, signedAt pumpTime: UInt32? = nil, key: [UInt8] = LinkHarness.key
    ) {
        for packet in Self.packets(message, txId: txId, signedAt: pumpTime, key: key) {
            apply(.notified(message.characteristic, packet))
        }
    }

    /// An op-77 on `characteristic` answering the request on the wire. On CONTROL it's signed.
    mutating func replyError(code: UInt8, request: UInt8 = 0, signedAt pumpTime: UInt32? = nil) {
        if let pumpTime {
            reply(ControlError(cargo: [request, code]), signedAt: pumpTime)
        } else {
            reply(ErrorResponse(cargo: [request, code]))
        }
    }

    static func packets(_ message: any Message, txId: UInt8, signedAt pumpTime: UInt32?, key: [UInt8]) -> [[UInt8]] {
        // swiftlint:disable:next force_try - test messages are well-formed
        let packets = try! Packetize.packetize(
            message, authenticationKey: pumpTime == nil ? [] : key, txId: txId, pumpTimeSinceReset: pumpTime ?? 0,
            actionsAffectingInsulinDeliveryEnabled: true, maxChunkSize: 18)
        return packets.map { $0.build() }
    }
}

/// op-77 as it arrives on CONTROL: signed, so Packetize writes the pump's trailer.
struct ControlError: Message {
    static let props = MessageProps(opCode: 77, size: 2, signed: true, type: .response, characteristic: .control)
    var cargo: [UInt8]
    init() { cargo = [] }
    init(cargo: [UInt8]) { self.cargo = cargo }
    mutating func parse(_ raw: [UInt8]) { cargo = raw }
}

/// op-77 on CONTROL with no trailer: anyone on the link could write it.
struct UnsignedControlError: Message {
    static let props = MessageProps(opCode: 77, size: 2, type: .response, characteristic: .control)
    var cargo: [UInt8]
    init() { cargo = [] }
    init(cargo: [UInt8]) { self.cargo = cargo }
    mutating func parse(_ raw: [UInt8]) { cargo = raw }
}

func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }

func pumpVersionCargo(_ unit: PumpUnit) -> [UInt8] {
    var cargo = [UInt8](repeating: 0, count: 48)
    cargo.replaceSubrange(0..<4, with: le32(unit.armSoftwareVersion))
    cargo.replaceSubrange(4..<8, with: le32(unit.mspSoftwareVersion))
    cargo.replaceSubrange(16..<20, with: le32(unit.serialNumber))
    return cargo
}
