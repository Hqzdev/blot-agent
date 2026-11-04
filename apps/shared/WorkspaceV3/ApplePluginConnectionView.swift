import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI
import UniformTypeIdentifiers

struct ApplePluginConnectionView: View {
    let plugin: ApplePluginID
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var resources: [AppleResource] = []
    @State private var selectedResources: Set<String> = []
    @State private var selectedAgents: Set<UUID> = []
    @State private var importing = false
    @State private var requesting = false
    @State private var status = "Нужна настройка"
    @State private var failure: String?
    @State private var shortcutName = ""
    @State private var verifyingShortcuts = false
    private var connection: BlotV3.Connection? {
        store.snapshot.connections.first { $0.pluginId == plugin.rawValue && $0.deviceId == store.snapshot.localDeviceID }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                ApplePluginIcon(plugin: plugin, size: 44)
                VStack(alignment: .leading, spacing: 4) { Text(plugin.name).font(.title2.bold()); Text(status).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button("Готово") { dismiss() }.buttonStyle(.plain)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(plugin.summary).foregroundStyle(.secondary)
                    if let deviceID = store.snapshot.localDeviceID {
                        ForEach(AppleInvocationRecovery.pending(plugin: plugin, deviceID: deviceID, actions: store.snapshot.preparedActions ?? [], invocations: store.snapshot.toolInvocations ?? [])) { pending in
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Нужна проверка результата").font(.headline)
                                Text(pending.preparation.consequences).font(.callout).textSelection(.enabled)
                                Text("Проверьте объект в системном приложении. До вашего решения новые изменения через этот плагин приостановлены.").font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Проверено: выполнено") { _Concurrency.Task { await store.resolveAppleInvocation(pending.id, succeeded: true) } }
                                    Button("Проверено: не выполнено") { _Concurrency.Task { await store.resolveAppleInvocation(pending.id, succeeded: false) } }
                                }.disabled(store.busy)
                            }.padding(16).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    if plugin.available, let controller = store.appleIntegrations {
                        Text("Доступ к данным").font(.headline)
                        Text("Разрешить чтение, создание и обычное редактирование в выбранных ресурсах. Отправка писем и удаление требуют отдельного подтверждения. Результаты запросов могут передаваться выбранной вами модели.")
                            .font(.callout).foregroundStyle(.secondary)
                        if plugin == .files {
                            Button("Выбрать папки…") { importing = true }.buttonStyle(WorkspaceButtonStyle(.secondary))
                        } else if plugin == .shortcuts {
                            Text("Откройте «Команды» и укажите точное название существующей команды. Blot запускает только выбранные команды, с подтверждением.").font(.callout)
                            HStack {
                                TextField("Название команды", text: $shortcutName).textFieldStyle(.roundedBorder)
                                Button("Добавить") {
                                    let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty, !resources.contains(where: { $0.id == name }) else { return }
                                    resources.append(.init(id: name, name: name)); selectedResources.insert(name); shortcutName = ""
                                }.disabled(shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            Link("Открыть «Команды»", destination: URL(string: "shortcuts://")!)
                            Button("Проверить выбранные команды…") { verifyingShortcuts = true }
                                .disabled(selectedResources.isEmpty || requesting)
                        } else {
                            Button(requesting ? "Проверяем доступ…" : "Разрешить доступ / обновить ресурсы") {
                                _Concurrency.Task { await request(controller) }
                            }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(requesting)
                        }
                        ForEach(resources) { resource in
                            Toggle(resource.name, isOn: Binding(get: { selectedResources.contains(resource.id) }, set: {
                                if $0 { selectedResources.insert(resource.id) } else { selectedResources.remove(resource.id) }
                            })).toggleStyle(.checkboxIfMac)
                        }
                        if resources.isEmpty { Text("Выберите ресурсы для подключения.").font(.caption).foregroundStyle(.secondary) }
                        Text("Агенты с доступом").font(.headline)
                        ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                            Toggle(agent.name, isOn: Binding(get: { selectedAgents.contains(agent.metadata.id) }, set: {
                                if $0 { selectedAgents.insert(agent.metadata.id) } else { selectedAgents.remove(agent.metadata.id) }
                            })).toggleStyle(.checkboxIfMac)
                        }
                        if let failure { Text(failure).foregroundStyle(.red).font(.callout) }
                        if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
                        HStack {
                            Button(connection == nil ? "Подключить" : "Сохранить доступ") {
                                _Concurrency.Task {
                                    await store.connectApple(plugin, resources: selectedResources.sorted(), agentIDs: selectedAgents.sorted { $0.uuidString < $1.uuidString })
                                    if store.error == nil { await refreshStatus() }
                                }
                            }.buttonStyle(WorkspaceButtonStyle()).disabled(store.busy || selectedResources.isEmpty || selectedAgents.isEmpty || requesting)
                            if let connection {
                                Button("Отключить", role: .destructive) {
                                    _Concurrency.Task { await store.disconnectApple(connection); await refreshStatus() }
                                }.buttonStyle(.plain).disabled(store.busy)
                            }
                        }
                    } else if plugin.available {
                        Text("Подключения доступны в рабочем пространстве после входа.").font(.callout)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(WorkspaceStyle.canvas)
        #if os(macOS)
        .frame(width: 580, height: 620)
        #endif
        .task {
            if let connection {
                selectedResources = Set(connection.resourceIds ?? []); selectedAgents = Set(connection.agentIds ?? [])
                resources = (connection.resourceIds ?? []).map { .init(id: $0, name: $0) }
            } else if let agent = store.snapshot.agents.first(where: { $0.roleId == "ceo" }) ?? store.snapshot.agents.first { selectedAgents.insert(agent.metadata.id) }
            if let controller = store.appleIntegrations, let connection,
               await controller.accessible(plugin, resources: connection.resourceIds ?? []) {
                do { resources = try await controller.requestResources(plugin) } catch { failure = error.localizedDescription }
            }
            await refreshStatus()
        }
        .confirmationDialog("Запустить выбранные команды для проверки?", isPresented: $verifyingShortcuts, titleVisibility: .visible) {
            Button("Запустить") { _Concurrency.Task {
                guard let controller = store.appleIntegrations else { return }
                requesting = true; failure = nil
                defer { requesting = false }
                do {
                    for name in selectedResources.sorted() { try await controller.verifyShortcut(name) }
                    status = "Команды проверены. Можно подключить."
                } catch { failure = error.localizedDescription }
            } }
            Button("Отмена", role: .cancel) {}
        } message: { Text("Каждая выбранная команда выполнится с пустым входом. Её действия могут изменить данные. После успешного возврата можно сохранить подключение.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder], allowsMultipleSelection: true) { result in
            do {
                guard let controller = store.appleIntegrations else { return }
                for url in try result.get() {
                    let resource = try controller.addFolder(url)
                    resources.append(resource); selectedResources.insert(resource.id)
                }
            } catch { failure = error.localizedDescription }
        }
    }
    private func request(_ controller: AppleIntegrationController) async {
        requesting = true; failure = nil
        defer { requesting = false }
        do {
            resources = try await controller.requestResources(plugin)
            selectedResources.formIntersection(Set(resources.map(\.id)))
            if resources.count == 1 { selectedResources.insert(resources[0].id) }
            await refreshStatus()
        } catch { failure = error.localizedDescription; status = "Нужно разрешение" }
    }
    private func refreshStatus() async {
        guard let controller = store.appleIntegrations else { status = plugin.available ? "Нужна настройка" : "Доступно на Mac"; return }
        status = connection == nil ? (plugin.available ? "Подключить" : "Доступно на Mac") : await controller.status(plugin, resources: connection?.resourceIds ?? [])
    }
}

private struct AppleConnectionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        #if os(macOS)
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        #else
        Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        #endif
    }
}
private extension ToggleStyle where Self == AppleConnectionToggleStyle {
    static var checkboxIfMac: AppleConnectionToggleStyle { .init() }
}
