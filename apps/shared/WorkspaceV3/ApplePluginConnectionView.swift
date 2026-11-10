import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI
import UniformTypeIdentifiers

struct ApplePluginConnectionView: View {
    let plugin: ApplePluginID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.macSheetSize) private var sheetSize
    #endif
    @Environment(\.scenePhase) private var scenePhase
    #if os(iOS)
    @Environment(\.phonePageTitle) private var pageTitle
    #endif
    @State private var hasAccess = false
    @State private var checking = true
    @State private var working = false
    @State private var importing = false
    @State private var confirmingDisconnect = false
    @State private var confirmingShortcut = false
    @State private var shortcutName = ""
    @State private var failure: String?

    private var connection: BlotV3.Connection? {
        store.snapshot.connections.first {
            $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID && $0.state == .connected
        }
    }
    private var connected: Bool { connection != nil && hasAccess }
    private var busy: Bool { working || checking || store.busy }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ApplePluginIcon(plugin: plugin, size: 64)
                #if os(macOS)
                WorkspaceLocalizedText(plugin.name).font(.title2.bold())
                #else
                if pageTitle != store.t(plugin.name) { WorkspaceLocalizedText(plugin.name).font(.title3.weight(.semibold)) }
                #endif
                WorkspaceLocalizedText(plugin.summary).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if !connected {
                    Text("Доступ получат все текущие агенты команды. Результаты запросов могут передаваться выбранной вами модели. Отправка и удаление требуют отдельного подтверждения.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if plugin == .shortcuts {
                        TextField("Название команды", text: $shortcutName).textFieldStyle(.roundedBorder)
                        Text("При подключении команда выполнится один раз для проверки. Её действия могут изменить данные.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if store.snapshot.agents.isEmpty {
                        Text("Сначала создайте агента в команде.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                if let error = failure ?? store.error {
                    WorkspaceLocalizedText(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                }
                Button(action: activate) {
                    HStack(spacing: 8) {
                        if busy { ProgressView().controlSize(.small) }
                        else if connected { Image(systemName: "checkmark") }
                        WorkspaceLocalizedText(busy ? "Подождите…" : connected ? "Подключено" : "Подключить")
                    }.frame(minWidth: 150)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .tint(connected ? .green : WorkspaceStyle.ink)
                .disabled(busy || !plugin.available || store.appleIntegrations == nil || (!connected && store.snapshot.agents.isEmpty))
                .help(connected ? "Отключить приложение" : "Разрешить доступ и подключить приложение")
                .accessibilityIdentifier("apple.connection.toggle")
            }
            #if os(iOS)
            .frame(maxWidth: 640).padding(PhonePageLayout.inset).frame(maxWidth: .infinity)
            #else
            .padding(32).frame(maxWidth: .infinity)
            #endif
        }
        .scrollBounceBehavior(.basedOnSize)
        #if os(macOS)
        .frame(width: min(480, sheetSize.width), height: min(520, sheetSize.height))
        #endif
        .background(WorkspaceStyle.canvas)
        .interactiveDismissDisabled(busy)
        #if os(macOS)
        .onExitCommand { if !busy { dismiss() } }
        #endif
        .task(id: store.snapshot.connections) { await refreshAccess() }
        .task(id: store.appleIntegrations?.revision) { await refreshAccess() }
        .task(id: scenePhase) { if scenePhase == .active { await refreshAccess() } }
        .confirmationDialog("Отключить «\(plugin.name)»?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Отключить", role: .destructive) {
                _Concurrency.Task {
                    guard let connection else { return }
                    await store.disconnectApple(connection)
                    await refreshAccess()
                }
            }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Агенты потеряют доступ к этому приложению в Blot.") }
        .confirmationDialog("Подключить команду «\(shortcutName)»?", isPresented: $confirmingShortcut, titleVisibility: .visible) {
            Button("Запустить и подключить") { working = true; _Concurrency.Task { await connect() } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Команда выполнится с пустым входом для проверки доступа. Её действия могут изменить данные.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): _Concurrency.Task { await connect(folders: urls) }
            case .failure(let error):
                working = false
                if (error as NSError).code != NSUserCancelledError { failure = error.localizedDescription }
            }
        }
        .modifier(AppleConnectionRecovery(plugin: plugin))
    }

    private func activate() {
        guard !busy else { return }
        failure = nil; store.error = nil
        if connected { confirmingDisconnect = true }
        else if plugin == .files { working = true; importing = true }
        else if plugin == .shortcuts {
            shortcutName = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            if shortcutName.isEmpty { failure = "Введите название существующей команды." }
            else { confirmingShortcut = true }
        } else { working = true; _Concurrency.Task { await connect() } }
    }

    private func connect(folders: [URL]? = nil) async {
        working = true
        defer { working = false }
        guard let controller = store.appleIntegrations else { return }
        do {
            let resources: [AppleResource]
            if let folders {
                guard !folders.isEmpty else { return }
                resources = try folders.map { try controller.addFolder($0) }
            } else if plugin == .shortcuts {
                try await controller.verifyShortcut(shortcutName)
                resources = try await controller.resources(plugin, selected: [shortcutName])
            } else {
                resources = try await controller.requestResources(plugin)
            }
            guard !resources.isEmpty else {
                failure = "Нет доступных данных для подключения. Проверьте разрешения и повторите попытку."
                return
            }
            await store.connectApple(plugin, resources: Array(Set(resources.map(\.id))).sorted(),
                agentIDs: store.snapshot.agents.map(\.metadata.id))
            await refreshAccess()
        } catch { failure = error.localizedDescription }
    }

    private func refreshAccess() async {
        defer { checking = false }
        guard let connection, let controller = store.appleIntegrations else { hasAccess = false; return }
        hasAccess = await controller.accessible(plugin, resources: connection.resourceIds ?? [])
    }
}
