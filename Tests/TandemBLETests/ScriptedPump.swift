import Foundation
import TandemAuth
import TandemLink
import TandemMessages
@testable import TandemBLE

/// A clock whose time moves only when a test says so. While `suspended`, nothing fires, as on iOS when
/// the app is suspended; timers due by then fire on `resume()`.
@MainActor
final class ManualClock: LinkClock {
    private(set) var now: LinkTime = 0
    var suspended = false
    private var scheduled: [(due: LinkTime, token: Token, action: @MainActor () -> Void)] = []

    final class Token: LinkClockToken {
        var cancelled = false
        func cancel() { cancelled = true }
    }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any LinkClockToken {
        let token = Token()
        scheduled.append((now + seconds, token, action))
        return token
    }

    func advance(by seconds: Double) {
        let end = now + seconds
        while !suspended,
            let next = scheduled.enumerated().filter({ !$0.element.token.cancelled && $0.element.due <= end })
                .min(by: { $0.element.due < $1.element.due })
        {
            scheduled.remove(at: next.offset)
            now = max(now, next.element.due)
            next.element.action()
        }
        now = end
        scheduled.removeAll { $0.token.cancelled }
    }

    func resume() {
        suspended = false
        advance(by: 0)
    }

    var pendingTimers: Int { scheduled.filter { !$0.token.cancelled }.count }
}

/// The pump and the radio as CoreBluetooth would report them. The pump lives outside any one
/// transport, so a relaunched app's transport finds the same pump (and, after restoration, the same
/// link). It answers legacy pairing, the handshake reads, status reads and BolusPermission.
@MainActor
final class ScriptedPump {
    static let id = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    static let code = "ABCDEFGHIJKLMNOP"
    static let name = "tslim X2 ***693"

    var inRange = true
    var poweredOn = true
    /// The link iOS keeps for the app, if any.
    var linked = false
    /// Drop the link this long after pairing, if set.
    var dropAfterPairing: Double?
    var pumpTime: UInt32 = 586_961_779
    /// Stop answering anything.
    var silent = false
    var writes: [(Characteristic, UInt8)] = []
    weak var transport: ScriptedTransport?
}

@MainActor
final class ScriptedTransport: LinkTransport {
    var report: ((LinkInput) -> Void)?
    let pump: ScriptedPump
    let clock: ManualClock
    private(set) var commands: [TransportCommand] = []
    /// A connect the transport was asked for and the pump hasn't completed (out of range or off).
    private(set) var pendingConnect = false

    init(pump: ScriptedPump, clock: ManualClock) {
        self.pump = pump
        self.clock = clock
        pump.transport = self
    }

    /// What CoreBluetooth reports right after the central is created.
    func start(restoring: Bool = false) {
        if restoring {
            report?(
                .restored([
                    RestoredPeripheral(peripheralID: ScriptedPump.id, isConnected: pump.linked, name: ScriptedPump.name)
                ]))
        }
        report?(.power(pump.poweredOn ? .poweredOn : .poweredOff))
    }

    func perform(_ command: TransportCommand) {
        commands.append(command)
        switch command {
        case .connect(let id) where id == ScriptedPump.id:
            pendingConnect = true
            completeConnectIfPossible()
        case .cancelConnection:
            pendingConnect = false
            if pump.linked {
                pump.linked = false
                report?(.disconnected(peripheralID: ScriptedPump.id, nil))
            }
        case .discover:
            report?(.characteristicsDiscovered(Set(Characteristic.allCases)))
        case .subscribe(let c):
            report?(.subscription(c, isNotifying: true, failed: false))
        case .readDeviceInformation:
            report?(.deviceInformation(modelNumber: "1000354"))
        case .write(let c, let packets):
            answer(c, packets)
        default:
            break
        }
    }

    func completeConnectIfPossible() {
        guard pendingConnect, pump.inRange, pump.poweredOn, !pump.linked else { return }
        pendingConnect = false
        pump.linked = true
        report?(.connected(peripheralID: ScriptedPump.id, name: ScriptedPump.name))
    }

    // MARK: Events a test injects

    func pumpWalksAway() {
        pump.inRange = false
        guard pump.linked else { return }
        pump.linked = false
        report?(.disconnected(peripheralID: ScriptedPump.id, BluetoothError(domain: "CBErrorDomain", code: 6)))
    }

    func pumpComesBack() {
        pump.inRange = true
        completeConnectIfPossible()
    }

    func bluetooth(on: Bool) {
        pump.poweredOn = on
        if !on {
            // A power-off cancels pending connects and drops the link; didDisconnect doesn't reliably
            // follow (the link handles this from the power state).
            pendingConnect = false
            pump.linked = false
            report?(.power(.poweredOff))
        } else {
            report?(.power(.poweredOn))
        }
    }

    func drop() {
        guard pump.linked else { return }
        pump.linked = false
        report?(.disconnected(peripheralID: ScriptedPump.id, BluetoothError(domain: "CBErrorDomain", code: 7)))
    }

    // MARK: The pump's answers

    private var reassembly: [Characteristic: PacketReassembler] = [:]
    private let key = Array(ScriptedPump.code.utf8)

    private func answer(_ characteristic: Characteristic, _ packets: [[UInt8]]) {
        guard pump.linked else { return report?(.writeFailed(characteristic, txId: packets.first?[1])) ?? () }
        var reassembler = reassembly[characteristic] ?? PacketReassembler()
        var frame: [UInt8]?
        for packet in packets { frame = reassembler.ingest(packet) ?? frame }
        reassembly[characteristic] = reassembler
        guard let frame, frame.count >= 3 else { return }
        let opCode = frame[0]
        let txId = frame[1]
        pump.writes.append((characteristic, opCode))
        guard !pump.silent else { return }
        switch (characteristic, opCode) {
        case (.authorization, CentralChallengeRequest.props.opCode):
            send(
                CentralChallengeResponse(
                    cargo: [0, 0] + [UInt8](repeating: 7, count: 20) + [UInt8](repeating: 9, count: 8)), txId)
        case (.authorization, PumpChallengeRequest.props.opCode):
            send(PumpChallengeResponse(cargo: [0, 0, 1]), txId)
            if let after = pump.dropAfterPairing {
                _ = clock.schedule(after: after) { [weak self] in self?.drop() }
            }
        case (.currentStatus, ApiVersionRequest.props.opCode):
            send(ApiVersionResponse(cargo: [2, 0, 5, 0]), txId)
        case (.currentStatus, PumpVersionRequest.props.opCode):
            var cargo = [UInt8](repeating: 0, count: 48)
            cargo[16] = 0x9D
            cargo[17] = 0x06
            send(PumpVersionResponse(cargo: cargo), txId)
        case (.currentStatus, TimeSinceResetRequest.props.opCode):
            let t = pump.pumpTime + UInt32(clock.now)
            send(TimeSinceResetResponse(cargo: (0..<4).map { UInt8((t >> (8 * $0)) & 0xFF) } + [0, 0, 0, 0]), txId)
        case (.currentStatus, CurrentBatteryV1Request.props.opCode):
            send(CurrentBatteryV1Response(cargo: [80, 0]), txId)
        case (.control, BolusPermissionRequest.props.opCode):
            send(BolusPermissionResponse(cargo: [0, 1, 0, 0, 0, 0]), txId, signed: true)
        default:
            break
        }
    }

    private func send(_ message: any Message, _ txId: UInt8, signed: Bool = false) {
        let time = pump.pumpTime + UInt32(clock.now)
        // swiftlint:disable:next force_try - the pump's replies are well-formed
        let packets = try! Packetize.packetize(
            message, authenticationKey: signed ? key : [], txId: txId, pumpTimeSinceReset: time, maxChunkSize: 18)
        for packet in packets { report?(.notified(message.characteristic, packet.build())) }
    }
}
