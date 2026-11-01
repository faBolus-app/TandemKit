import Foundation
@preconcurrency import CoreBluetooth
import TandemLink
import TandemMessages

/// The CoreBluetooth side of the link: performs `TransportCommand`s and reports every central and
/// peripheral callback as a `LinkInput`, in plain values. It decides nothing; reconnecting, timeouts and
/// what a drop means are `LinkReducer`'s. It keeps only the handles CoreBluetooth needs retained (a
/// deallocated `CBPeripheral` cancels its connection).
///
/// The central runs on the main queue, so the delegate methods hop onto the main actor with
/// `MainActor.assumeIsolated`.
@MainActor
public final class CoreBluetoothTransport: NSObject, LinkTransport {
    public var report: ((LinkInput) -> Void)?

    private var central: CBCentralManager!
    /// Handles of peripherals seen (discovered, retrieved or restored), by identifier.
    private var peripherals: [UUID: CBPeripheral] = [:]
    /// The peripheral connected or being set up.
    private var current: CBPeripheral?
    private var characteristics: [Characteristic: CBCharacteristic] = [:]
    private var modelNumber: CBCharacteristic?
    private var wantsModelNumber = false
    /// The txId of each packet written and not yet acknowledged, per characteristic, oldest first.
    /// CoreBluetooth acknowledges writes with response in order but doesn't say which value it means.
    private var unacknowledged: [Characteristic: [UInt8]] = [:]

    private static let pumpService = CBUUID(nsuuid: ServiceUUID.pumpService)
    private static let deviceInformationService = CBUUID(nsuuid: ServiceUUID.disService)
    /// Device Information Service model number string (Bluetooth SIG 0x2A24), which pumpx2 reads.
    private static let modelNumberCharacteristic = CBUUID(string: "2A24")

    public init(restoreIdentifier: String?) {
        super.init()
        var options: [String: Any] = [:]
        if let restoreIdentifier { options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier }
        central = CBCentralManager(delegate: self, queue: .main, options: options)
    }

    public func perform(_ command: TransportCommand) {
        switch command {
        case .scan:
            central.scanForPeripherals(withServices: [Self.pumpService], options: nil)
        case .stopScan:
            central.stopScan()
        case .connect(let id):
            guard let peripheral = resolve(id) else {
                report?(.peripheralUnavailable(id))
                return
            }
            peripheral.delegate = self
            // A pending connect has no timeout; CoreBluetooth completes it when the pump is in range, also
            // while the app is suspended.
            central.connect(peripheral, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        case .cancelConnection(let id):
            if let peripheral = peripherals[id] { central.cancelPeripheralConnection(peripheral) }
        case .discover:
            characteristics = [:]
            modelNumber = nil
            current?.discoverServices([Self.pumpService, Self.deviceInformationService])
        case .subscribe(let characteristic):
            guard let peripheral = current, let cb = characteristics[characteristic] else {
                report?(.subscription(characteristic, isNotifying: false, failed: true))
                return
            }
            peripheral.setNotifyValue(true, for: cb)
        case .readDeviceInformation:
            if let peripheral = current, let modelNumber {
                peripheral.readValue(for: modelNumber)
            } else {
                wantsModelNumber = true
            }
        case .write(let characteristic, let packets):
            guard let peripheral = current, let cb = characteristics[characteristic] else {
                report?(.writeFailed(characteristic, txId: packets.first.flatMap { $0.count > 1 ? $0[1] : nil }))
                return
            }
            for packet in packets {
                unacknowledged[characteristic, default: []].append(packet.count > 1 ? packet[1] : 0)
                peripheral.writeValue(Data(packet), for: cb, type: .withResponse)
            }
        }
    }

    private func resolve(_ id: UUID) -> CBPeripheral? {
        if let known = peripherals[id] { return known }
        let found =
            central.retrievePeripherals(withIdentifiers: [id]).first
            ?? central.retrieveConnectedPeripherals(withServices: [Self.pumpService]).first { $0.identifier == id }
        if let found { peripherals[id] = found }
        return found
    }

    fileprivate func adopt(_ peripheral: CBPeripheral) {
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
    }

    fileprivate func connected(_ peripheral: CBPeripheral) {
        adopt(peripheral)
        current = peripheral
        characteristics = [:]
        modelNumber = nil
        wantsModelNumber = false
        unacknowledged = [:]
        report?(.connected(peripheralID: peripheral.identifier, name: peripheral.name))
    }

    fileprivate func disconnected(_ peripheral: CBPeripheral, _ error: Error?) {
        if current === peripheral {
            current = nil
            characteristics = [:]
            modelNumber = nil
            unacknowledged = [:]
        }
        report?(.disconnected(peripheralID: peripheral.identifier, error.map(BluetoothError.init)))
    }

    fileprivate func discoveredServices(_ peripheral: CBPeripheral, _ error: Error?) {
        guard peripheral === current else { return }
        guard error == nil else { return report?(.characteristicsDiscovered([])) ?? () }
        for service in peripheral.services ?? [] {
            if service.uuid == Self.pumpService {
                peripheral.discoverCharacteristics(nil, for: service)
            } else if service.uuid == Self.deviceInformationService {
                peripheral.discoverCharacteristics([Self.modelNumberCharacteristic], for: service)
            }
        }
        if peripheral.services?.contains(where: { $0.uuid == Self.pumpService }) != true {
            report?(.characteristicsDiscovered([]))
        }
    }

    fileprivate func discoveredCharacteristics(_ peripheral: CBPeripheral, _ service: CBService, _ error: Error?) {
        guard peripheral === current else { return }
        if service.uuid == Self.deviceInformationService {
            modelNumber = service.characteristics?.first { $0.uuid == Self.modelNumberCharacteristic }
            if wantsModelNumber, let modelNumber {
                wantsModelNumber = false
                peripheral.readValue(for: modelNumber)
            }
            return
        }
        guard service.uuid == Self.pumpService else { return }
        for cb in service.characteristics ?? [] {
            if let mapped = Characteristic.of(uuid: cb.uuid.uuidValue) { characteristics[mapped] = cb }
        }
        report?(.characteristicsDiscovered(error == nil ? Set(characteristics.keys) : []))
    }

    fileprivate func valueUpdated(_ peripheral: CBPeripheral, _ cb: CBCharacteristic, _ error: Error?) {
        guard peripheral === current, error == nil, let value = cb.value else { return }
        if cb.uuid == Self.modelNumberCharacteristic {
            report?(.deviceInformation(modelNumber: String(data: value, encoding: .utf8)))
        } else if let mapped = Characteristic.of(uuid: cb.uuid.uuidValue) {
            report?(.notified(mapped, [UInt8](value)))
        }
    }

    fileprivate func notificationStateUpdated(_ peripheral: CBPeripheral, _ cb: CBCharacteristic, _ error: Error?) {
        guard peripheral === current, let mapped = Characteristic.of(uuid: cb.uuid.uuidValue) else { return }
        report?(.subscription(mapped, isNotifying: cb.isNotifying, failed: error != nil))
    }

    fileprivate func wrote(_ peripheral: CBPeripheral, _ cb: CBCharacteristic, _ error: Error?) {
        guard peripheral === current, let mapped = Characteristic.of(uuid: cb.uuid.uuidValue) else { return }
        let txId = unacknowledged[mapped]?.isEmpty == false ? unacknowledged[mapped]?.removeFirst() : nil
        if error != nil { report?(.writeFailed(mapped, txId: txId)) }
    }

    fileprivate nonisolated static func power(_ state: CBManagerState) -> BluetoothPower {
        switch state {
        case .poweredOn: return .poweredOn
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .resetting: return .resetting
        default: return .unknown
        }
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let power = Self.power(central.state)
        MainActor.assumeIsolated { report?(.power(power)) }
    }

    /// iOS relaunched the app and hands back the peripherals it kept connected or connecting. Called
    /// before `centralManagerDidUpdateState`.
    public nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // The central delivers on the main queue, so this array is made and read on the main thread
        // only; the compiler can't see that through the non-Sendable dictionary it comes from.
        nonisolated(unsafe) let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        MainActor.assumeIsolated {
            for peripheral in restored { adopt(peripheral) }
            report?(
                .restored(
                    restored.map {
                        RestoredPeripheral(
                            peripheralID: $0.identifier, isConnected: $0.state == .connected, name: $0.name)
                    }))
            if let connected = restored.first(where: { $0.state == .connected }) { current = connected }
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let rssi = RSSI.intValue
        MainActor.assumeIsolated {
            adopt(peripheral)
            report?(.discovered(peripheralID: peripheral.identifier, name: name ?? peripheral.name, rssi: rssi))
        }
    }

    public nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated { connected(peripheral) }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        MainActor.assumeIsolated {
            report?(.connectFailed(peripheralID: peripheral.identifier, error.map(BluetoothError.init)))
        }
    }

    public nonisolated func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        MainActor.assumeIsolated { disconnected(peripheral, error) }
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated { discoveredServices(peripheral, error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        MainActor.assumeIsolated { discoveredCharacteristics(peripheral, service, error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?
    ) {
        MainActor.assumeIsolated { notificationStateUpdated(peripheral, characteristic, error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        MainActor.assumeIsolated { valueUpdated(peripheral, characteristic, error) }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?
    ) {
        MainActor.assumeIsolated { wrote(peripheral, characteristic, error) }
    }
}

extension BluetoothError {
    init(_ error: Error) {
        let ns = error as NSError
        self.init(domain: ns.domain, code: ns.code)
    }
}

extension CBUUID {
    /// The pump's UUIDs are 128-bit; this maps them onto `Characteristic`'s Foundation UUIDs.
    fileprivate var uuidValue: UUID { UUID(uuidString: uuidString) ?? UUID() }
}
