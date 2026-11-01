import BlotDesign
import Foundation
import Observation
import UIKit
import BlotAPI

@MainActor
@Observable
final class PhoneConnection {
    private(set) var client: BackendClient?
    private(set) var status = "Scan the QR code on your Mac"
    private(set) var error: String?
    private var tunnel: PhoneBluetoothTunnel?
    private var pairing: Task<Void, Never>?
    private var descriptor: PairingDescriptor?
    private var discovery: MacDiscovery?
    private var revision = 0

    nonisolated private struct Request: Encodable, Sendable { let id: UUID; let secret: String; let name: String; let platform: String }
    nonisolated private struct Session: Decodable, Sendable { let token: String; let expiresAt: String }
    nonisolated private struct Saved: Codable, Sendable { let installationId: String; let address: URL; let fingerprint: String; let bluetoothName: String }

    func pair(json: String, bluetooth: Bool) {
        do {
            let value = try JSONDecoder().decode(PairingDescriptor.self, from: Data(json.utf8))
            guard value.schemaVersion == 2, value.address.scheme == "https", value.fingerprint.count == 64,
                  value.fingerprint.allSatisfy({ $0.isHexDigit }) else { throw URLError(.cannotParseResponse) }
            revision += 1
            discovery?.cancel(); discovery = nil
            tunnel?.stop(); tunnel = nil
            descriptor = value; error = nil; pairing?.cancel()
            if bluetooth {
                status = "Looking for your Mac over Bluetooth"
                let tunnel = PhoneBluetoothTunnel()
                tunnel.onError = { [weak self] error in self?.error = error }
                tunnel.onReady = { [weak self] url in self?.begin(value, endpoint: url) }
                self.tunnel = tunnel
                tunnel.connect(name: value.bluetoothName)
            } else { begin(value, endpoint: value.address) }
        } catch { self.error = error.localizedDescription }
    }
    private func begin(_ value: PairingDescriptor, endpoint: URL) {
        let currentRevision = revision
        pairing?.cancel()
        pairing = Task {
            do {
                let session = PinnedBackendSession(fingerprint: value.fingerprint).makeSession()
                let client = BackendClient(baseURL: endpoint, session: session)
                let request = Request(id: value.id, secret: value.secret, name: UIDevice.current.name, platform: "iOS")
                let _: [String: String] = try await client.post("v2/pairing/request", body: request, as: [String: String].self)
                status = "Approve this iPhone on your Mac"
                for _ in 0..<300 {
                    try Task.checkCancellation()
                    do {
                        let token = try await client.post("v2/pairing/claim", body: request, as: Session.self)
                        try BackendKeychain.write(token.token, key: "phone.session." + value.installationId)
                        await client.useToken(token.token)
                        guard currentRevision == revision else { return }
                        let saved = Saved(installationId: value.installationId, address: value.address, fingerprint: value.fingerprint, bluetoothName: value.bluetoothName)
                        UserDefaults.standard.set(try JSONEncoder().encode(saved), forKey: "blot.phone.connection")
                        try await prepareCommands(client, installationId: value.installationId)
                        guard currentRevision == revision else { return }
                        self.client = client; descriptor = nil; status = "Connected"; return
                    } catch let failure as BackendFailure where failure.code == "pairing_pending" {
                        try await Task.sleep(for: .seconds(1))
                    }
                }
                throw URLError(.timedOut)
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func restore(bluetooth: Bool = false) async {
        guard let data = UserDefaults.standard.data(forKey: "blot.phone.connection"),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              let token = try? BackendKeychain.read("phone.session." + saved.installationId) else { return }
        revision += 1
        let currentRevision = revision
        discovery?.cancel(); discovery = nil
        tunnel?.stop(); tunnel = nil
        func connect(_ endpoint: URL) async {
            guard currentRevision == revision else { return }
            let session = PinnedBackendSession(fingerprint: saved.fingerprint).makeSession()
            let client = BackendClient(baseURL: endpoint, token: token, session: session)
            do {
                try await prepareCommands(client, installationId: saved.installationId)
                guard currentRevision == revision else { return }
                self.client = client; status = "Connected"; error = nil
                if !bluetooth {
                    let updated = Saved(installationId: saved.installationId, address: endpoint, fingerprint: saved.fingerprint, bluetoothName: saved.bluetoothName)
                    UserDefaults.standard.set(try JSONEncoder().encode(updated), forKey: "blot.phone.connection")
                }
            } catch { self.error = error.localizedDescription; self.client = nil }
        }
        if bluetooth {
            let tunnel = PhoneBluetoothTunnel()
            tunnel.onReady = { url in Task { await connect(url) } }
            tunnel.onError = { [weak self] in self?.error = $0 }
            self.tunnel = tunnel; tunnel.connect(name: saved.bluetoothName)
        } else {
            status = "Looking for your saved Mac"
            let discovery = MacDiscovery(); self.discovery = discovery
            let address = await discovery.find(installationId: saved.installationId)
            guard currentRevision == revision else { return }
            self.discovery = nil
            await connect(address ?? saved.address)
        }
    }
    private func prepareCommands(_ client: BackendClient, installationId: String) async throws {
        let account = try await client.get("v2/auth/me", as: [String: BackendJSON].self)
        guard let installation = UUID(uuidString: installationId), case .string(let rawID) = account["id"], let id = UUID(uuidString: rawID) else { throw URLError(.cannotParseResponse) }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Blot/pending/" + installation.uuidString + "/" + id.uuidString)
        try await client.persistPendingCommands(in: directory)
        do { _ = try await client.recoverPendingCommands() }
        catch { self.error = "Some commands still await delivery: " + error.localizedDescription }
    }
    func disconnect() {
        revision += 1; discovery?.cancel(); discovery = nil
        pairing?.cancel(); tunnel?.stop(); tunnel = nil; client = nil; descriptor = nil; status = "Disconnected"
    }
}
