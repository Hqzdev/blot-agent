import BlotDesign
import SwiftUI
import BlotAPI

struct SMTPSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = "587"
    @State private var username = ""
    @State private var password = ""
    @State private var from = ""
    @State private var error: String?
    @State private var busy = false
    private nonisolated struct Configuration: Encodable, Sendable { let host: String; let port: Int; let username: String; let password: String; let from: String }
    var body: some View {
        KSheet("Email delivery", subtitle: "Blot sends verification and password reset codes through this SMTP account using STARTTLS.",
               width: 480) {
            HStack(alignment: .top, spacing: KSpace.md) {
                KTextField("SMTP host", text: $host, placeholder: "smtp.example.com", required: true, autofocus: true)
                KTextField("Port", text: $port, placeholder: "587", mono: true,
                           error: port.isEmpty || Int(port) != nil ? nil : "Numbers only.").frame(width: 96)
            }
            KTextField("Username", text: $username, contentType: .username)
            KTextField("Password", text: $password, secure: true, contentType: .password)
            KTextField("Sender email", text: $from, placeholder: "blot@example.com", required: true)
            if let error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: "Save", kind: .primary, loading: busy) { save() }
                .disabled(host.isEmpty || from.isEmpty)
                .keyboardShortcut(.defaultAction)
        }
    }
    private func save() {
        guard let port = Int(port) else { error = "Enter a valid port"; return }
        busy = true
        Task {
            do {
                try await BackendRuntime.shared.start()
                try await BackendRuntime.shared.client.put("v2/setup/smtp", body: Configuration(host: host, port: port, username: username, password: password, from: from))
                password = ""; dismiss()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}
