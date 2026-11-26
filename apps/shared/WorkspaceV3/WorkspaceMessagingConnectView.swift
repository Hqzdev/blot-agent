import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceMessagingProviding { func messagingService() async throws -> WorkspaceMessagingService }
extension LocalWorkspaceService: WorkspaceMessagingProviding {
    func messagingService() async throws -> WorkspaceMessagingService {
        if let messaging { return messaging }; let identity = try await context()
        if let messaging { return messaging }
        let service = WorkspaceMessagingService(repository: repository, identity: identity, credentials: mcpCredentials); messaging = service; return service
    }
    func messagingTools() async throws -> WorkspaceMessagingTools {
        let center = appleIntegrations.interactions
        return WorkspaceMessagingTools(service: try await messagingService(), repository: repository, identity: try await context()) { title, detail in try await center.confirm(title: title, details: detail) }
    }
}
extension WorkspaceAccountApplicationService: WorkspaceMessagingProviding {
    func messagingService() async throws -> WorkspaceMessagingService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; return try await local.messagingService()
    }
}

struct WorkspaceMessagingConnectView: View {
    let provider: WorkspaceMessagingProvider
    @Environment(WorkspaceStore.self) private var store
    @State private var accounts: [WorkspaceMessagingAccount] = []
    @State private var clientID = ""
    @State private var botToken = ""
    @State private var working = false
    @State private var failure: String?
    @State private var browser = WorkspaceMCPOAuthBrowser()
    @State private var removing: WorkspaceMessagingAccount?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BlotLabel(provider.name, symbol: "bubble.left.and.bubble.right").font(.title2)
                Text(ru ? "Используется зарегистрированное публичное OAuth-приложение с PKCE. Client ID не является секретом. Токены остаются в Keychain устройства." : "Uses a registered public OAuth app with PKCE. Client ID is public. Tokens remain in this device’s Keychain.").foregroundStyle(.secondary)
                ForEach(accounts) { account in VStack(alignment: .leading) { HStack { Text(account.name); Spacer(); Button(store.t("Disconnect"), role: .destructive) { removing = account } }; Text(account.id.uuidString).font(.caption.monospaced()).textSelection(.enabled); Text(account.workspace).font(.caption).textSelection(.enabled) } }
                TextField("OAuth client ID", text: $clientID)
                Button(ru ? "Войти через браузер" : "Sign in with browser") { signIn() }.disabled(clientID.isEmpty)
                if provider == .slack {
                    DisclosureGroup(ru ? "Токен собственного Slack-бота" : "Own Slack bot token") {
                        SecureField("xoxb-…", text: $botToken).privacySensitive()
                        Text(ru ? "Бот должен быть добавлен в выбранные каналы. Права задаются в настройках вашего Slack-приложения." : "Invite the bot to selected channels. Permissions are configured in your Slack app.").font(.caption).foregroundStyle(.secondary)
                        Button(store.t("Connect")) { connectBot() }.disabled(!botToken.hasPrefix("xoxb-"))
                    }
                } else {
                    Text(ru ? "Нужен рабочий или учебный Microsoft-аккаунт. Сообщения отправляются от вошедшего пользователя; отдельная Bot Framework-личность настраивается в Azure." : "Requires a work or school Microsoft account. Sends as the signed-in user; a separate Bot Framework identity is configured in Azure.").font(.caption).foregroundStyle(.secondary)
                }
                Text(ru ? "Redirect URI" : "Redirect URI").font(.headline)
                Text(callback.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
                if let failure { Text(failure).foregroundStyle(.red) }
                if working { ProgressView() }
            }.padding(24).textFieldStyle(WorkspacePanelTextFieldStyle()).disabled(working)
        }
        .task { clientID = (Bundle.main.object(forInfoDictionaryKey: "BlotMessagingClientIDs") as? [String: String])?[provider.rawValue] ?? ""; await reload() }
        .workspaceConfirmationDialog(store.t("Disconnect") + "?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(store.t("Disconnect"), role: .destructive) { if let removing { perform { try await $0.disconnect(removing.id) } }; removing = nil }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }
    private var callback: URL {
        #if os(macOS)
        URL(string: "blot-agent-macos:/plugins/" + provider.rawValue)!
        #else
        URL(string: "blot-agent-ios:/plugins/" + provider.rawValue)!
        #endif
    }
    private func reload() async { do { accounts = try await store.messagingCommands?.messagingService().accounts().filter { $0.provider == provider } ?? [] } catch { failure = WorkspaceFailureCopy.message(error) } }
    private func signIn() {
        perform { service in
            let authorization = try WorkspaceMessagingAuthorization(provider: provider, clientID: clientID, redirectURI: callback)
            let result = try await browser.signIn(url: authorization.url, redirectURI: callback)
            try await service.connect(authorization, callback: result)
        }
    }
    private func connectBot() { perform { service in try await service.connectSlackBot(botToken); botToken = "" } }
    private func perform(_ action: @escaping @MainActor (WorkspaceMessagingService) async throws -> Void) {
        guard !working, let commands = store.messagingCommands else { return }; working = true; failure = nil
        _Concurrency.Task {
            defer { working = false }
            do { try await action(commands.messagingService()); await reload(); try await store.refreshContent() }
            catch { failure = ru ? "Подключение не завершено. Проверьте регистрацию приложения, PKCE, redirect URI и разрешения сервиса." : "Connection failed. Check app registration, PKCE, redirect URI and provider permissions." }
        }
    }
}
