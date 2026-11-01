import BlotDesign
import Foundation
@preconcurrency import CoreBluetooth
@preconcurrency import Network
import BlotAPI

/// URLSession подключается к локальному TCP-порту, TLS проходит до Java через BLE.
@MainActor
final class PhoneBluetoothTunnel: NSObject, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {
    private struct Channel {
        let connection: NWConnection
        var incoming: UInt32 = 0
        var outgoing: UInt32 = 1
    }
    var onReady: ((URL) -> Void)?
    var onError: ((String) -> Void)?
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var incoming: CBCharacteristic?
    private var listener: NWListener?
    private var channels: [UInt32: Channel] = [:]
    private var nextChannel: UInt32 = 1
    private var writes: [Data] = []
    private var writing = false
    private var enabled = false
    private var expectedName = ""

    override init() { super.init(); manager = CBCentralManager(delegate: self, queue: .main) }
    func connect(name: String) { enabled = true; expectedName = name; scan() }
    func stop() {
        enabled = false; manager.stopScan(); listener?.cancel(); listener = nil
        channels.values.forEach { $0.connection.cancel() }; channels = [:]; writes = []; writing = false
        if let peripheral { manager.cancelPeripheralConnection(peripheral) }
    }
    private func scan() {
        guard enabled, manager.state == .poweredOn else { return }
        manager.scanForPeripherals(withServices: [CBUUID(string: BlotBluetoothIdentifiers.service)])
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { scan() }
    func centralManager(_ central: CBCentralManager, didDiscover device: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard device.name == expectedName || advertisementData[CBAdvertisementDataLocalNameKey] as? String == expectedName else { return }
        manager.stopScan(); peripheral = device; device.delegate = self; manager.connect(device)
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) { peripheral.discoverServices([CBUUID(string: BlotBluetoothIdentifiers.service)]) }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) { onError?(error?.localizedDescription ?? "Bluetooth connection failed") }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        listener?.cancel(); listener = nil; channels.values.forEach { $0.connection.cancel() }; channels = [:]; writes = []; writing = false
        if enabled { scan() }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard error == nil, let service = peripheral.services?.first else { onError?("Blot Bluetooth service is unavailable"); return }
        peripheral.discoverCharacteristics([CBUUID(string: BlotBluetoothIdentifiers.incoming), CBUUID(string: BlotBluetoothIdentifiers.outgoing)], for: service)
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard error == nil else { onError?("Bluetooth characteristics are unavailable"); return }
        incoming = service.characteristics?.first { $0.uuid == CBUUID(string: BlotBluetoothIdentifiers.incoming) }
        if let outgoing = service.characteristics?.first(where: { $0.uuid == CBUUID(string: BlotBluetoothIdentifiers.outgoing) }) { peripheral.setNotifyValue(true, for: outgoing) }
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, characteristic.isNotifying else { onError?("Bluetooth notifications failed"); return }
        do {
            let listener = try NWListener(using: .tcp, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in Task { @MainActor [weak self] in self?.open(connection) } }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                if case .ready = state, let port = listener?.port { Task { @MainActor [weak self] in self?.onReady?(URL(string: "https://127.0.0.1:\(port.rawValue)/")!) } }
            }
            listener.start(queue: .main)
        } catch { onError?(error.localizedDescription) }
    }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        writing = false
        guard error == nil else { stop(); onError?("Bluetooth packet was rejected"); return }
        if !writes.isEmpty { writes.removeFirst() }
        flush()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil, let data = characteristic.value, let frame = try? BluetoothFrame(data: data), var channel = channels[frame.channel] else { return }
        guard channel.incoming == frame.sequence else { close(frame.channel, notify: true); return }
        channel.incoming &+= 1; channels[frame.channel] = channel
        if frame.kind == .close { close(frame.channel, notify: false) }
        else if frame.kind == .data { channel.connection.send(content: frame.payload, completion: .contentProcessed { _ in }) }
    }
    private func open(_ connection: NWConnection) {
        guard channels.count < 8 else { connection.cancel(); return }
        let id = nextChannel; nextChannel &+= 1
        channels[id] = Channel(connection: connection)
        connection.start(queue: .main)
        enqueue(BluetoothFrame(kind: .open, channel: id, sequence: 0))
        receive(id)
    }
    private func receive(_ id: UInt32) {
        guard let channel = channels[id] else { return }
        channel.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data { self.send(data, channel: id) }
                if done || error != nil { self.close(id, notify: true) } else { self.receive(id) }
            }
        }
    }
    private func send(_ data: Data, channel id: UInt32) {
        guard var channel = channels[id], let peripheral else { return }
        let size = min(1024, peripheral.maximumWriteValueLength(for: .withResponse) - BluetoothFrame.headerSize)
        guard size > 0, writes.reduce(0, { $0 + $1.count }) + data.count < 4_194_304 else { close(id, notify: false); return }
        for offset in stride(from: 0, to: data.count, by: size) {
            enqueue(BluetoothFrame(kind: .data, channel: id, sequence: channel.outgoing, payload: data.subdata(in: offset..<min(offset + size, data.count))))
            channel.outgoing &+= 1
        }
        channels[id] = channel
    }
    private func enqueue(_ frame: BluetoothFrame) { if let bytes = try? frame.encode() { writes.append(bytes); flush() } }
    private func close(_ id: UInt32, notify: Bool) {
        guard let channel = channels.removeValue(forKey: id) else { return }
        channel.connection.cancel()
        if notify { enqueue(BluetoothFrame(kind: .close, channel: id, sequence: channel.outgoing)) }
    }
    private func flush() {
        guard !writing, let bytes = writes.first, let peripheral, let incoming else { return }
        writing = true; peripheral.writeValue(bytes, for: incoming, type: .withResponse)
    }
}
