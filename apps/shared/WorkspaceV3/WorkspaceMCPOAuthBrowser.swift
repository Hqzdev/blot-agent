import BlotDesign
import AuthenticationServices
import BlotWorkspace
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor final class WorkspaceMCPOAuthBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    func cancel() { session?.cancel() }
    func signIn(_ attempt: MCPOAuthAttempt) async throws -> URL {
        try await signIn(url: attempt.url, redirectURI: attempt.redirectURI)
    }
    func signIn(url: URL, redirectURI: URL) async throws -> URL {
        guard session == nil else { throw MCPError.unavailable }
        #if os(macOS)
        anchor = NSApp.keyWindow ?? NSApp.mainWindow
        #else
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first { $0.isKeyWindow }
        #endif
        guard anchor != nil else { throw MCPError.unavailable }
        defer { session = nil; anchor = nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectURI.scheme) { callback, error in
                    if let callback { continuation.resume(returning: callback) }
                    else { continuation.resume(throwing: error ?? MCPError.denied) }
                }
                session.presentationContextProvider = self
                self.session = session
                if !session.start() { self.session = nil; continuation.resume(throwing: MCPError.unavailable) }
            }
        } onCancel: { _Concurrency.Task { @MainActor [weak self] in self?.session?.cancel() } }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor! }
}

struct WorkspaceMCPOAuthButton: View {
    @Binding var configuration: MCPConfiguration
    let russian: Bool
    @State private var browser = WorkspaceMCPOAuthBrowser()
    @State private var working = false
    @State private var failure: String?
    @State private var clientID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(russian ? "Войти через браузер (OAuth)" : "Sign in with browser (OAuth)") { signIn() }
                .disabled(working || configuration.transport != .http || !configuration.endpoint.hasPrefix("https://"))
            DisclosureGroup(russian ? "Зарегистрированный OAuth client ID" : "Pre-registered OAuth client ID") {
                TextField("Client ID", text: $clientID)
                Text(russian ? "Необязательно: оставьте пустым для автоматической регистрации, если сервер её поддерживает." : "Optional: leave empty for automatic registration when supported by the server.").font(.caption).foregroundStyle(.secondary)
            }
            if working { ProgressView() }
            if configuration.oauth != nil { BlotLabel(russian ? "OAuth подключён" : "OAuth connected", symbol: "checkmark.shield").font(.caption).foregroundStyle(.green) }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
    }
    private func signIn() {
        guard !working else { return }; working = true; failure = nil
        let endpoint = configuration.endpoint
        _Concurrency.Task {
            defer { working = false }
            do {
                #if os(macOS)
                let callback = URL(string: "blot-agent-macos:/mcp/oauth")!
                #else
                let callback = URL(string: "blot-agent-ios:/mcp/oauth")!
                #endif
                let client = MCPOAuthClient()
                let attempt = try await client.begin(endpoint: endpoint, redirectURI: callback, clientID: clientID)
                let url = try await browser.signIn(attempt)
                let (token, credentials) = try await client.finish(attempt, callback: url)
                guard configuration.endpoint == endpoint else { throw MCPError.accessChanged }
                configuration.bearerToken = token; configuration.oauth = credentials
            } catch {
                failure = russian ? "Не удалось завершить OAuth. Проверьте поддержку автоматической регистрации или укажите зарегистрированный client ID." : "OAuth failed. Check automatic client registration support or supply a registered client ID."
            }
        }
    }
}
