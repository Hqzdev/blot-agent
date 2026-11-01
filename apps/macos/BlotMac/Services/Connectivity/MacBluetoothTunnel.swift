import BlotDesign
import Foundation
@preconcurrency import CoreBluetooth
@preconcurrency import Network
import BlotAPI

/// Прозрачный мост BLE → отдельный TLS-коннектор Java. Содержимое команд здесь не читается.
@MainActor
final class MacBluetoothTunnel: NSObject, @preconcurrency CBPeripheralManagerDelegate {
    private struct Key: Hashable, Sendable { let central: UUID; let stream: UInt32 }
    private struct Channel {
        let connection: NWConnection
        let central: CBCentral
        var incoming: UInt32 = 1
        var outgoing: UInt32 = 0
    }
    private let port: UInt16
    private let name: String
    private var manager: CBPeripheralManager!
    private var channels: [Key: Channel] = [:]
    private var pending: [(CBCentral, Data)] = []
    private let outgoing = CBMutableCharacteristic(type: CBUUID(string: BlotBluetoothIdentifiers.outgoing), properties: [.notify], value: nil, permissions: [])

    init(port: UInt16, name: String) {
        self.port = port; self.name = name
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }
    func stop() {
        manager.stopAdvertising()
        channels.values.forEach { $0.connection.cancel() }
        channels = [:]; pending = []
    }
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        guard peripheral.state == .poweredOn else { stop(); return }
        let service = CBMutableService(type: CBUUID(string: BlotBluetoothIdentifiers.service), primary: true)
        let incoming = CBMutableCharacteristic(type: CBUUID(string: BlotBluetoothIdentifiers.incoming), properties: [.write], value: nil, permissions: [.writeable])
        service.characteristics = [incoming, outgoing]
        peripheral.removeAllServices()
        peripheral.add(service)
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: (any Error)?) {
        guard error == nil else { return }
        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [service.uuid], CBAdvertisementDataLocalNameKey: name])
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            do {
                guard request.characteristic.uuid == CBUUID(string: BlotBluetoothIdentifiers.incoming), let bytes = request.value else { throw URLError(.cannotParseResponse) }
                let frame = try BluetoothFrame(data: bytes)
                let key = Key(central: request.central.identifier, stream: frame.channel)
                guard frame.channel != 0 else { throw URLError(.cannotParseResponse) }
                if frame.kind == .open {
                    guard frame.sequence == 0, channels[key] == nil, channels.count < 16 else { throw URLError(.resourceUnavailable) }
                    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
                    channels[key] = Channel(connection: connection, central: request.central)
                    connection.stateUpdateHandler = { [weak self] state in
                        if case .failed = state { Task { @MainActor [weak self] in self?.close(key, notify: true) } }
                    }
                    connection.start(queue: .main)
                    receive(key)
                } else {
                    guard var channel = channels[key], channel.incoming == frame.sequence else { close(key, notify: true); throw URLError(.cannotParseResponse) }
                    channel.incoming &+= 1
                    channels[key] = channel
                    if frame.kind == .close { close(key, notify: false) }
                    else { channel.connection.send(content: frame.payload, completion: .contentProcessed { [weak self] error in
                        if error != nil { Task { @MainActor [weak self] in self?.close(key, notify: true) } }
                    }) }
                }
                peripheral.respond(to: request, withResult: .success)
            } catch { peripheral.respond(to: request, withResult: .unlikelyError) }
        }
    }
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        for key in Array(channels.keys) where key.central == central.identifier { close(key, notify: false) }
        pending.removeAll { $0.0.identifier == central.identifier }
    }
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) { flush() }

    private func receive(_ key: Key) {
        guard let channel = channels[key] else { return }
        channel.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let data, !data.isEmpty { self.send(data, key: key) }
                if done || error != nil { self.close(key, notify: true) } else { self.receive(key) }
            }
        }
    }
    private func send(_ data: Data, key: Key) {
        guard var channel = channels[key] else { return }
        let size = min(1024, channel.central.maximumUpdateValueLength - BluetoothFrame.headerSize)
        guard size > 0, pending.reduce(0, { $0 + $1.1.count }) + data.count < 4_194_304 else { close(key, notify: false); return }
        for offset in stride(from: 0, to: data.count, by: size) {
            let frame = BluetoothFrame(kind: .data, channel: key.stream, sequence: channel.outgoing, payload: data.subdata(in: offset..<min(data.count, offset + size)))
            guard let bytes = try? frame.encode() else { close(key, notify: false); return }
            pending.append((channel.central, bytes)); channel.outgoing &+= 1
        }
        channels[key] = channel
        flush()
    }
    private func close(_ key: Key, notify: Bool) {
        guard let channel = channels.removeValue(forKey: key) else { return }
        channel.connection.cancel()
        if notify, let bytes = try? BluetoothFrame(kind: .close, channel: key.stream, sequence: channel.outgoing).encode() { pending.append((channel.central, bytes)); flush() }
    }
    private func flush() {
        while let packet = pending.first {
            guard manager.updateValue(packet.1, for: outgoing, onSubscribedCentrals: [packet.0]) else { return }
            pending.removeFirst()
        }
    }
}
