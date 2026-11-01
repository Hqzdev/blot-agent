import BlotDesign
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import BlotAPI

struct ProviderCertificateSettingsView: View {
    @State private var pending: String?
    @State private var certificates: [CertificateInfo] = []
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        SettingsGroup(title: "GigaChat TLS certificate",
                      detail: "Choose a PEM certificate and compare its SHA-256 fingerprint with a source you trust. Approval applies to GigaChat requests for this account.") {
            SettingsRow(title: "Certificate authority", detail: "Download the CA from the provider’s instructions, then choose the file.") {
                HStack(spacing: KSpace.sm) {
                    Link(destination: URL(string: "https://developers.sber.ru/docs/ru/gigachat/certificates")!) {
                        Text("Instructions").font(KFont.label()).foregroundStyle(K.text2).underline()
                    }
                    .help("Opens the provider’s documentation in your browser")
                    KButton(title: "Choose file…", icon: "file-text", loading: busy && pending == nil) { choose() }
                        .disabled(busy)
                }
            }
            ForEach(certificates, id: \.sha256) { item in
                SettingsDivider()
                GroupContent(spacing: 6) {
                    Text(item.subject).font(KFont.label()).foregroundStyle(K.text)
                    KeyValueRow(label: "SHA-256", value: item.sha256, mono: true, labelWidth: 80)
                    KeyValueRow(label: "Valid until", value: item.notAfter, labelWidth: 80)
                }
            }
            if pending != nil || !certificates.isEmpty || error != nil {
                SettingsDivider()
                HStack(spacing: KSpace.sm) {
                    if let error { InlineFeedback(text: error, tone: .error) }
                    else if pending == nil { InlineFeedback(text: "Trusted for this account", tone: .success) }
                    else { InlineFeedback(text: "Check the fingerprint before trusting it.", tone: .warning) }
                    Spacer()
                    if pending != nil {
                        KButton(title: "Trust for GigaChat", icon: "check", kind: .primary, loading: busy) { save() }
                    }
                }
                .padding(KSpace.lg)
            }
        }
        .task {
            do { certificates = try await BackendRuntime.shared.client.get("v2/provider/certificate", as: [CertificateInfo].self) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "pem") ?? .data, UTType(filenameExtension: "crt") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let data = try file.read(upToCount: 65_537) ?? Data()
            guard data.count <= 65_536, let pem = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    certificates = try await BackendRuntime.shared.client.post("v2/provider/certificate/inspect", body: ["pem": pem], as: [CertificateInfo].self)
                    pending = pem
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        guard let pending else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await BackendRuntime.shared.client.put("v2/provider/certificate", body: ["pem": pending]); self.pending = nil }
            catch { self.error = error.localizedDescription }
        }
    }
    nonisolated private struct CertificateInfo: Codable, Sendable {
        let subject: String
        let issuer: String
        let sha256: String
        let notAfter: String
    }
}
