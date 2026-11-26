import BlotDesign
import BlotWorkspace
import SwiftUI
import UniformTypeIdentifiers

@MainActor protocol WorkspaceVaultProviding { func vaultService() async throws -> WorkspaceVaultService }
extension LocalWorkspaceService: WorkspaceVaultProviding {
    func vaultService() async throws -> WorkspaceVaultService {
        if let vault { return vault }
        let ownerID = try await context().ownerID
        if let vault { return vault }
        let service = WorkspaceVaultService(credentials: mcpCredentials, ownerID: ownerID)
        vault = service; return service
    }
}
extension WorkspaceAccountApplicationService: WorkspaceVaultProviding {
    func vaultService() async throws -> WorkspaceVaultService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.vaultService()
    }
}

struct WorkspaceVaultButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { BlotLabel("Vault", symbol: "lock.shield") }
            .workspacePanelSheet(isPresented: $showing) { WorkspaceVaultView().environment(store) }
    }
}

struct WorkspaceVaultView: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var items: [WorkspaceVaultSummary] = []
    @State private var editing: WorkspaceVaultItem?
    @State private var search = ""
    @State private var importing = false
    @State private var imported: [WorkspaceVaultItem] = []
    @State private var failure: String?
    @State private var working = false
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Text(ru ? "Личное хранилище в Связке ключей этого устройства. Секреты не передаются в чат или модели." : "Personal vault in this device’s Keychain. Secrets are never sent to chat or models.").font(.caption).foregroundStyle(.secondary)
                TextField(store.t("Search"), text: $search)
                ForEach(items.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { item in
                    Button {
                        _Concurrency.Task {
                            do { editing = try await store.vaultCommands?.vaultService().read(item.id) }
                            catch { failure = WorkspaceFailureCopy.message(error) }
                        }
                    } label: {
                        HStack {
                            BlotIcon(symbol: symbol(item.kind))
                            VStack(alignment: .leading) { Text(item.title); Text(item.hint).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); BlotIcon(symbol: "chevron.right")
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Button(ru ? "Импорт логинов CSV" : "Import logins CSV") { importing = true }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: "Vault") {
                    Button(store.t("Close")) { dismiss() }
                    WorkspaceMenu {
                        ForEach(WorkspaceVaultItem.Kind.allCases, id: \.self) { kind in
                            Button { editing = .init(title: "", kind: kind) } label: {
                                BlotLabel(kindTitle(kind), symbol: symbol(kind))
                            }
                        }
                    } label: { BlotLabel(ru ? "Новая запись" : "New item", symbol: "plus") }
                }
            }.workspaceEditorChrome()
        }
        .task { await refresh() }
        .workspacePanelSheet(item: $editing) { item in WorkspaceVaultEditor(item: item, saved: { await refresh() }).environment(store) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            do {
                let url = try result.get(), scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_000_000 else { throw WorkspaceStorageError.invalidParameters }
                imported = try WorkspaceVaultCSV.logins(String(contentsOf: url, encoding: .utf8))
            } catch { failure = ru ? "Не удалось прочитать CSV. Нужны столбцы username и password, необязательно name и url." : "Cannot read CSV. Provide username/password columns and optional name/url." }
        }
        .workspacePanelSheet(isPresented: Binding(get: { !imported.isEmpty }, set: { if !$0 { imported = [] } })) {
            NavigationStack {
                List(imported) { item in
                    VStack(alignment: .leading) { Text(item.title); Text(item.fields["username"] ?? "").font(.caption) }
                }

                .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Импорт: \(imported.count) логинов" : "Import \(imported.count) logins") {
                    Button(store.t("Cancel")) { imported = [] }.disabled(working)
                    Button(store.t("Import")) {
                            guard let commands = store.vaultCommands else { return }
                            working = true
                            _Concurrency.Task {
                                defer { working = false }
                                do { _ = try await commands.vaultService().importLogins(imported); imported = []; await refresh() }
                                catch { failure = WorkspaceFailureCopy.message(error); imported = [] }
                            }
                        }.disabled(working)
                }
            }.workspaceEditorChrome()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
    }
    private func refresh() async {
        do { items = try await store.vaultCommands?.vaultService().list() ?? []; failure = nil }
        catch { failure = WorkspaceFailureCopy.message(error) }
    }
    private func kindTitle(_ kind: WorkspaceVaultItem.Kind) -> String {
        switch kind {
        case .login: ru ? "Пароль" : "Login"
        case .card: ru ? "Банковская карта" : "Payment card"
        case .contact: ru ? "Контакт" : "Contact"
        case .apiSecret: ru ? "Ключ API" : "API key"
        }
    }
    private func symbol(_ kind: WorkspaceVaultItem.Kind) -> String {
        switch kind { case .login: "key"; case .card: "creditcard"; case .contact: "person.crop.circle"; case .apiSecret: "lock" }
    }
}

private struct WorkspaceVaultEditor: View {
    @State var item: WorkspaceVaultItem
    let saved: @MainActor () async -> Void
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var working = false
    @State private var deleting = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                TextField(store.t("Name"), text: $item.title)
                ForEach(WorkspaceVaultItem.fieldNames(item.kind), id: \.self) { key in
                    let binding = Binding(get: { item.fields[key] ?? "" }, set: { item.fields[key] = $0 })
                    if key == "password" || key == "secret" { SecureField(key, text: binding).privacySensitive() }
                    else { TextField(key, text: binding).privacySensitive() }
                }
                TextField(ru ? "Подсказка для выбора" : "Hint", text: $item.hint, axis: .vertical)
                if item.kind == .card {
                    Text(ru ? "Укажите ссылку/токен способа оплаты и последние четыре цифры. Полный номер и CVC здесь не сохраняются." : "Store a payment reference/token and last four digits. Full card numbers and CVC are not saved here.").font(.caption).foregroundStyle(.secondary)
                }
                if item.version > 0 { Button(store.t("Delete"), role: .destructive) { deleting = true } }
                if let failure { Text(failure).foregroundStyle(.red) }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: item.title.isEmpty ? "Vault" : item.title) {
                    Button(store.t("Cancel")) { dismiss() }.disabled(working)
                    Button(store.t("Save")) { perform(deleting: false) }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(working || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.workspaceEditorChrome()
        }
        .privacySensitive().interactiveDismissDisabled(working)
        .workspaceConfirmationDialog(ru ? "Удалить запись?" : "Delete item?", isPresented: $deleting, titleVisibility: .visible) {
            Button(store.t("Delete"), role: .destructive) { perform(deleting: true) }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 460)
        #endif
    }
    private func perform(deleting: Bool) {
        guard let commands = store.vaultCommands, !working else { return }
        working = true
        _Concurrency.Task {
            defer { working = false }
            do {
                let service = try await commands.vaultService()
                if deleting { try await service.delete(item.id, expectedVersion: item.version) }
                else { try await service.save(item) }
                await saved(); dismiss()
            } catch { failure = WorkspaceFailureCopy.message(error) }
        }
    }
}
