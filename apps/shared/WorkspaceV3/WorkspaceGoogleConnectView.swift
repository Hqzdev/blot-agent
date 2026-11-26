import BlotAppleIntegrations
import BlotDomain
import BlotDesign
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceGoogleProviding { func googleService() async throws -> WorkspaceGoogleService }
extension LocalWorkspaceService: WorkspaceGoogleProviding {
    func googleService() async throws -> WorkspaceGoogleService {
        if let google { return google }
        let identity = try await context()
        if let google { return google }
        let value = WorkspaceGoogleService(repository: repository, identity: identity, credentials: mcpCredentials); google = value; return value
    }
    func googleTools() async throws -> WorkspaceGoogleTools {
        let center = appleIntegrations.interactions
        return WorkspaceGoogleTools(service: try await googleService(), repository: repository, identity: try await context(), files: try await fileService()) { title, detail in try await center.confirm(title: title, details: detail) }
    }
}
extension WorkspaceAccountApplicationService: WorkspaceGoogleProviding {
    func googleService() async throws -> WorkspaceGoogleService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; return try await local.googleService()
    }
}

struct WorkspaceGoogleConnectView: View {
    let plugin: WorkspaceGooglePlugin
    @Environment(WorkspaceStore.self) private var store
    @State private var accounts: [WorkspaceGoogleAccount] = []
    @State private var browser = WorkspaceGoogleOAuthBrowser()
    @State private var working = false
    @State private var failure: String?
    @State private var removing: WorkspaceGoogleAccount?
    @State private var verified: Set<UUID> = []
    @State private var operation: _Concurrency.Task<Void, Never>?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                BlotLabel(plugin.name, symbol: "person.crop.circle.badge.checkmark").font(.title2)
                Text(ru ? "Вход через Google. Токены хранятся в Keychain этого устройства. Подключение доступно всем агентам на этом устройстве. Отправка писем и изменения показываются на подтверждение в чате." : "Sign in with Google. Tokens stay in this device’s Keychain. The connection is available to all agents on this device. Sending email and making changes are reviewed in chat.").foregroundStyle(.secondary)
                ForEach(accounts) { account in
                    WorkspaceCard {
                        Text(account.email).font(.headline)
                        if verified.contains(account.id) { BlotLabel(ru ? "Google API доступен" : "Google API verified", symbol: "checkmark.circle").font(.caption).foregroundStyle(.green) }
                        Button(ru ? "Проверить доступ" : "Check access") { perform { service in
                            try await service.verifyAccount(account.id); verified.insert(account.id)
                        } }
                        Button(store.t("Disconnect"), role: .destructive) { removing = account }
                    }
                }
                DisclosureGroup(ru ? "Запрашиваемые разрешения Google" : "Requested Google permissions") {
                    ForEach(plugin.access.map(\.scope).sorted(), id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
                Button(ru ? "Подключить Google аккаунт" : "Connect Google account") { connect() }
                    .buttonStyle(WorkspaceButtonStyle()).disabled(store.googleCommands == nil)
                if working { ProgressView() }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.padding(24).disabled(working)
        }
        .onDisappear { cancel() }
        .safeAreaInset(edge: .bottom) {
            if working {
                Button(ru ? "Отменить" : "Cancel") { cancel() }
                    .buttonStyle(WorkspaceButtonStyle(.secondary)).padding(16)
            }
        }
        .task { await reload() }
        .workspaceConfirmationDialog(ru ? "Удалить доступ Ori к этому аккаунту на устройстве?" : "Remove Ori’s access to this account on this device?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(store.t("Disconnect"), role: .destructive) { if let removing { disconnect(removing) }; removing = nil }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
    private func configuration() throws -> GoogleOAuthConfiguration {
        guard let url = Bundle.main.url(forResource: "GoogleOAuth", withExtension: "plist"), let id = Bundle.main.bundleIdentifier else { throw GoogleOAuthError.notConfigured }
        #if os(macOS)
        let platform = GoogleOAuthConfiguration.Platform.macOS
        #else
        let platform = GoogleOAuthConfiguration.Platform.iOS
        #endif
        return try .load(plist: Data(contentsOf: url), platform: platform, bundleID: id)
    }
    private func reload() async {
        do { accounts = try await store.googleCommands?.googleService().accounts().filter { $0.plugin == plugin } ?? [] }
        catch { failure = ru ? "Не удалось прочитать подключения Google." : "Could not read Google connections." }
    }
    private func connect() {
        perform { service in
            let (authorization, callback) = try await browser.signIn(configuration: configuration(), access: plugin.access)
            try await service.connect(plugin: plugin, authorization: authorization, callback: callback)
        }
    }
    private func disconnect(_ account: WorkspaceGoogleAccount) { perform { try await $0.disconnect(account.id) } }
    private func perform(_ action: @escaping @MainActor (WorkspaceGoogleService) async throws -> Void) {
        guard !working, let commands = store.googleCommands else { return }; working = true; failure = nil
        operation = _Concurrency.Task {
            defer { working = false; operation = nil }
            do { try await action(commands.googleService()); await reload(); try await store.refreshContent() }
            catch { failure = WorkspaceGoogleFailure.message(error, russian: ru) }
        }
    }
    private func cancel() { operation?.cancel(); browser.cancel() }
}
