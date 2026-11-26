import BlotDesign
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspacePasswordProviding { func passwordService() async throws -> WorkspacePasswordConnect }
extension LocalWorkspaceService: WorkspacePasswordProviding {
    func passwordService() async throws -> WorkspacePasswordConnect { .init(credentials: mcpCredentials, ownerID: try await context().ownerID) }
}
extension WorkspaceAccountApplicationService: WorkspacePasswordProviding {
    func passwordService() async throws -> WorkspacePasswordConnect {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; return try await local.passwordService()
    }
}

struct WorkspacePasswordConnectView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var endpoint = ""
    @State private var token = ""
    @State private var vaults: [WorkspacePasswordVault] = []
    @State private var selected: Set<String> = []
    @State private var entries: [WorkspacePasswordEntry] = []
    @State private var vaultID = ""
    @State private var connected = false
    @State private var working = false
    @State private var failure: String?
    @State private var importing: WorkspacePasswordEntry?
    @State private var success: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BlotLabel("1Password", symbol: "key.fill").font(.title2)
                Text(ru ? "Подключение через ваш 1Password Connect Server. Выберите разрешённые хранилища, затем импортируйте нужные логины в Vault этого устройства." : "Connect to your 1Password Connect Server. Choose allowed vaults, then import selected logins into this device’s Vault.").foregroundStyle(.secondary)
                if connected {
                    WorkspaceChoice(title: ru ? "Хранилище" : "Vault", selection: $vaultID, options: vaults.map { .init($0.id, $0.name) })
                        .onChange(of: vaultID) { _, _ in loadEntries() }
                    ForEach(entries) { entry in
                        HStack { Text(entry.title); Spacer(); Button(ru ? "Импорт в Vault" : "Import into Vault") { importing = entry } }
                    }
                    WorkspaceVaultButton()
                    Button(store.t("Disconnect"), role: .destructive) { perform { try await $0.disconnect(); connected = false; vaults = []; entries = [] } }
                } else {
                    TextField("https://connect.example.com", text: $endpoint)
                    SecureField("Connect access token", text: $token).privacySensitive()
                    Button(ru ? "Проверить сервер" : "Check server") { inspect() }.disabled(endpoint.isEmpty || token.isEmpty)
                    ForEach(vaults) { vault in
                        Toggle(vault.name, isOn: Binding(get: { selected.contains(vault.id) }, set: { if $0 { selected.insert(vault.id) } else { selected.remove(vault.id) } }))
                    }
                    if !vaults.isEmpty { Button(store.t("Connect")) { save() }.disabled(selected.isEmpty) }
                    Link(ru ? "Настройка 1Password Connect" : "Set up 1Password Connect", destination: URL(string: "https://developer.1password.com/docs/connect/get-started/")!)
                }
                if working { ProgressView() }
                if let failure { Text(failure).foregroundStyle(.red) }
                if let success { Text(success).foregroundStyle(.green) }
            }.padding(24).textFieldStyle(WorkspacePanelTextFieldStyle()).disabled(working)
        }
        .task { await reload() }
        .workspaceConfirmationDialog(ru ? "Скопировать этот логин в Keychain Vault устройства?" : "Copy this login into the device’s Keychain Vault?", isPresented: Binding(get: { importing != nil }, set: { if !$0 { importing = nil } }), titleVisibility: .visible) {
            Button(ru ? "Импортировать" : "Import") { if let importing { importEntry(importing) }; importing = nil }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
    private func reload() async {
        guard let commands = store.passwordCommands else { return }
        do {
            let service = try await commands.passwordService(); connected = try await service.connected()
            if connected { vaults = try await service.vaults(); vaultID = vaults.first?.id ?? ""; entries = vaultID.isEmpty ? [] : try await service.entries(vaultID: vaultID) }
        } catch { failure = ru ? "1Password недоступен. Проверьте сервер и токен." : "1Password unavailable. Check the server and token." }
    }
    private func inspect() { perform { service in vaults = try await service.inspect(endpoint: endpoint, token: token); selected = [] } }
    private func save() { perform { service in try await service.save(endpoint: endpoint, token: token, vaults: selected); token = ""; await reload() } }
    private func loadEntries() { guard !vaultID.isEmpty else { return }; perform { entries = try await $0.entries(vaultID: vaultID) } }
    private func importEntry(_ entry: WorkspacePasswordEntry) {
        let id = vaultID
        perform { service in
            guard let vault = try await store.vaultCommands?.vaultService() else { throw WorkspaceServiceError.unavailable }
            try await service.importLogin(vaultID: id, itemID: entry.id, into: vault)
            success = ru ? "Логин сохранён в Vault." : "Login saved in Vault."
        }
    }
    private func perform(_ action: @escaping @MainActor (WorkspacePasswordConnect) async throws -> Void) {
        guard !working, let commands = store.passwordCommands else { return }; working = true; failure = nil; success = nil
        _Concurrency.Task {
            defer { working = false }
            do { try await action(commands.passwordService()) }
            catch { failure = ru ? "Не удалось выполнить действие 1Password. Проверьте сервер, токен и доступ к хранилищу." : "1Password action failed. Check the server, token, and vault access." }
        }
    }
}
