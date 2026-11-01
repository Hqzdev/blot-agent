import BlotDesign
import SwiftUI
import BlotAPI
import CoreImage.CIFilterBuiltins

struct DevicePairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var descriptor: PairingDescriptor?
    @State private var requests: [PairRequest] = []
    @State private var error: String?
    nonisolated private struct Ticket: Decodable, Sendable { let id: UUID; let secret: String?; let expiresAt: String }
    nonisolated private struct PairRequest: Decodable, Sendable, Identifiable { let id: UUID; let version: Int64; let deviceName: String?; let platform: String?; let approved: Bool; let claimed: Bool }
    nonisolated private struct Id: Encodable, Sendable { let id: UUID }
    var body: some View {
        KSheet("Connect your iPhone", subtitle: "Scan this code in Blot on your iPhone, then approve the device here.", width: 440) {
            VStack(spacing: KSpace.md) {
                Group {
                    if let descriptor, let image = qr(descriptor) {
                        Image(nsImage: image).interpolation(.none).resizable()
                            .accessibilityLabel("Pairing QR code")
                            .transition(.opacity)
                    } else if error == nil {
                        ProgressView().controlSize(.regular)
                    } else {
                        KIcon("circle-alert", size: 28, color: K.text3)
                    }
                }
                .frame(width: 240, height: 240)
                .padding(KSpace.md)
                .background(RoundedRectangle(cornerRadius: K.rLg, style: .continuous).fill(Color.white))
                .overlay(RoundedRectangle(cornerRadius: K.rLg, style: .continuous).strokeBorder(K.border, lineWidth: 1))
                if let descriptor {
                    Text(descriptor.address.absoluteString).font(KFont.mono(11)).foregroundStyle(K.text3)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity)
            let waiting = requests.filter { !$0.approved && $0.deviceName != nil }
            if !waiting.isEmpty {
                SettingsGroup(title: "Waiting for approval") {
                    ForEach(Array(waiting.enumerated()), id: \.element.id) { index, request in
                        if index > 0 { SettingsDivider() }
                        ListRow(title: request.deviceName ?? "iPhone", subtitle: request.platform) {
                            IconTile(icon: "iphone")
                        } trailing: {
                            KButton(title: "Approve", icon: "check", kind: .primary, height: 28) { approve(request) }
                        }
                    }
                }
                .transition(.kAppear)
            }
            if let error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "New code", icon: "rotate-ccw") { Task { await create() } }
            KButton(title: "Done", kind: .primary) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .task {
            await create()
            while !Task.isCancelled { await refresh(); try? await Task.sleep(for: .seconds(1)) }
        }
    }
    private func create() async {
        do {
            let runtime = BackendRuntime.shared
            runtime.enableBluetooth()
            guard let fingerprint = runtime.fingerprint, let installation = runtime.installationId else { throw URLError(.secureConnectionFailed) }
            let receipt = try await runtime.client.command("device.pair", payload: [String: String]())
            let created = try receipt.result.decode(Ticket.self)
            let ticket = try await runtime.client.get("v2/pairing/\(created.id.uuidString)/ticket", as: Ticket.self)
            guard let secret = ticket.secret else { throw URLError(.cannotParseResponse) }
            var address = URLComponents(url: runtime.client.baseURL, resolvingAgainstBaseURL: false)!
            address.host = Host.current().name ?? ProcessInfo.processInfo.hostName
            descriptor = PairingDescriptor(installationId: installation, address: address.url!, fingerprint: fingerprint, bluetoothName: runtime.bluetoothName, id: ticket.id, secret: secret, expiresAt: ticket.expiresAt)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func refresh() async {
        do { requests = try await BackendRuntime.shared.client.get("v2/devices/pairings", as: [PairRequest].self) }
        catch { self.error = error.localizedDescription }
    }
    private func approve(_ request: PairRequest) {
        Task { do { _ = try await BackendRuntime.shared.client.command("device.approve", payload: Id(id: request.id), expectedVersion: request.version); await refresh() } catch { self.error = error.localizedDescription } }
    }
    private func qr(_ value: PairingDescriptor) -> NSImage? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        let filter = CIFilter.qrCodeGenerator(); filter.message = data
        guard let image = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let result = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height))
    }
}
