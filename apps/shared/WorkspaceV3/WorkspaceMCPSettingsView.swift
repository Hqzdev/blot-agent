import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceMCPSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var entries: [MCPAccess] = []
    @State private var sheet: MCPSettingsSheet?
    @State private var error: String?
    @State private var busy = false
    @State private var resolving: BlotV3.ToolInvocation?
    private var russian: Bool { store.language == "ru" }
    private func text(_ ru: String, _ en: String) -> String { russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(text("MCP-серверы", "MCP servers")).font(.title2.bold())
            Text(text("Выберите инструменты и агентов. Каждый вызов требует подтверждения с точными аргументами.",
                      "Choose tools and agents. Every call requires confirmation of its exact arguments.")).foregroundStyle(.secondary)
            ForEach(entries) { entry in
                WorkspaceCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(.headline)
                            Text(entry.enabled ? text("Подключён на этом устройстве", "Connected on this device") : text("Требуется выбор доступа", "Review access to enable"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(text("Настроить", "Manage")) { sheet = .access(entry) }.disabled(busy)
                    }
                    Text(text("Инструментов: ", "Tools: ") + String(entry.selectedTools.count))
                    ForEach(unknown(entry.id), id: \.metadata.id) { invocation in
                        Text(text("Исход вызова неизвестен. Новые вызовы заблокированы до сверки с сервером.", "A call has an unknown outcome. New calls are blocked until you verify it on the server."))
                        Button(text("Сверить результат…", "Reconcile outcome…")) { resolving = invocation }.disabled(busy)
                    }
                }
            }
            ForEach(store.snapshot.mcpConnections.filter { record in !entries.contains { $0.id == record.metadata.id } }, id: \.metadata.id) { record in
                WorkspaceCard {
                    Text(record.name).font(.headline)
                    Text(text("Настроен на другом устройстве. Здесь нет параметров запуска и доступа.", "Configured on another device. Launch settings and access are local to that device.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button(text("Добавить MCP-сервер", "Add MCP server")) { sheet = .new }.buttonStyle(WorkspaceButtonStyle()).disabled(store.mcpCommands == nil || busy)
        }
        .task { await reload() }
        .workspacePanelSheet(item: $sheet, onDismiss: { _Concurrency.Task { await reload() } }) { item in
            WorkspaceMCPEditor(initial: item.access, agents: store.snapshot.agents, russian: russian, commands: store.mcpCommands)
        }
        .confirmationDialog(text("Проверьте фактический результат на сервере. Это решение не повторяет вызов.", "Verify the actual outcome on the server. This decision does not repeat the call."),
            isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
                Button(text("Проверено: выполнено", "Verified: completed")) { reconcile(true) }
                Button(text("Проверено: не выполнено", "Verified: not completed")) { reconcile(false) }
                Button(text("Отмена", "Cancel"), role: .cancel) { resolving = nil }
            }
    }
    private func unknown(_ id: UUID) -> [BlotV3.ToolInvocation] {
        let actions = Set((store.snapshot.preparedActions ?? []).filter { $0.resource == id.uuidString && $0.toolId.hasPrefix("mcp_") }.map(\.metadata.id))
        return (store.snapshot.toolInvocations ?? []).filter { $0.state == .unknown && $0.execution.executorDeviceId == store.snapshot.localDeviceID && actions.contains($0.preparedActionId) }
    }
    private func reload() async {
        do {
            guard let commands = store.mcpCommands else { return }
            entries = try await commands.mcpService().access()
            try await store.refreshMCP()
        } catch { self.error = error.localizedDescription }
    }
    private func reconcile(_ succeeded: Bool) {
        guard let invocation = resolving, let commands = store.mcpCommands else { return }; resolving = nil; busy = true
        _Concurrency.Task {
            defer { busy = false }
            do { try await commands.mcpService().resolve(invocationID: invocation.metadata.id, succeeded: succeeded); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
}

private enum MCPSettingsSheet: Identifiable {
    case new, access(MCPAccess)
    var id: String { access?.id.uuidString ?? "new" }
    var access: MCPAccess? { if case .access(let value) = self { value } else { nil } }
}

private struct WorkspaceMCPEditor: View {
    let initial: MCPAccess?
    let agents: [BlotV3.AgentProfile]
    let russian: Bool
    let commands: (any WorkspaceMCPProviding)?
    @WorkspacePresentationDismiss private var dismiss
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    @State private var name = ""
    @State private var configuration = MCPConfiguration()
    @State private var arguments = "[]"
    @State private var environment = "{}"
    @State private var inspection: MCPInspection?
    @State private var tools: [MCPTool] = []
    @State private var selected: Set<String> = []
    @State private var selectedAgents: Set<UUID> = []
    @State private var error: String?
    @State private var busy = false
    @State private var removing = false
    private func text(_ ru: String, _ en: String) -> String { russian ? ru : en }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if initial == nil && inspection == nil {
                        TextField(text("Имя сервера", "Server name"), text: $name)
                        MCPConfigurationFields(configuration: $configuration, arguments: $arguments, environment: $environment, russian: russian)
                        Button(text("Проверить и получить инструменты", "Test and discover tools")) { inspect() }.disabled(busy)
                    } else {
                        Text(initial?.name ?? inspection?.name ?? "MCP").font(.headline)
                        Text(text("Описания предоставлены сервером. Выбор инструмента не заменяет подтверждение каждого вызова.", "Descriptions come from the server. Selecting a tool does not approve its calls.")).font(.caption).foregroundStyle(.secondary)
                        MCPAccessFields(tools: tools, agents: agents, selected: $selected, selectedAgents: $selectedAgents, russian: russian)
                        Button(text("Сохранить доступ", "Save access")) { save() }.buttonStyle(WorkspaceButtonStyle()).disabled(busy || selected.isEmpty || selectedAgents.isEmpty)
                        if initial != nil {
                            Button(text("Обновить инструменты и сбросить доступ", "Refresh tools and reset access")) { refresh() }.disabled(busy)
                            Button(text("Отключить и удалить настройки", "Disconnect and remove settings"), role: .destructive) { removing = true }.disabled(busy)
                        } else {
                            Button(text("Изменить параметры", "Change settings")) { inspection = nil; tools = []; selected = [] }.disabled(busy)
                        }
                    }
                    if busy { ProgressView() }
                    if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }.textFieldStyle(WorkspacePanelTextFieldStyle()).padding(24).disabled(busy)
            }
            .navigationTitle(text("Подключение MCP", "MCP connection"))
            .safeAreaInset(edge: .top, spacing: 0) {
                if panelNavigation != nil { WorkspacePanelFormHeader(title: text("Подключение MCP", "MCP connection")) { Button(text("Закрыть", "Close")) { dismiss() }.disabled(busy) } }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { if panelNavigation == nil { Button(text("Закрыть", "Close")) { dismiss() }.disabled(busy) } } }
            .task { if let initial { tools = initial.tools; selected = initial.selectedTools; selectedAgents = initial.agentIDs } }
            .confirmationDialog(text("Удалить локальные параметры и отозвать доступ агентов?", "Remove local settings and revoke agent access?"), isPresented: $removing, titleVisibility: .visible) {
                Button(text("Отключить", "Disconnect"), role: .destructive) { disconnect() }
            }
        }
        #if os(macOS)
        .frame(width: panelNavigation == nil ? 640 : nil, height: panelNavigation == nil ? 650 : nil)
        #endif
        .interactiveDismissDisabled(busy)
    }
    private func perform(_ work: @escaping @MainActor (WorkspaceMCPService) async throws -> Void) {
        guard !busy, let commands else { return }; busy = true; error = nil
        _Concurrency.Task {
            defer { busy = false }
            do { try await work(commands.mcpService()) }
            catch is CancellationError { return }
            catch { self.error = (error as? MCPError)?.localizedDescription ?? text("Не удалось выполнить операцию MCP. Проверьте параметры и доступ.", "MCP operation failed. Check settings and access.") }
        }
    }
    private func inspect() {
        perform { service in
            var input = configuration
            if input.transport == .stdio {
                input.arguments = try JSONDecoder().decode([String].self, from: Data(arguments.utf8))
                input.environment = try JSONDecoder().decode([String: String].self, from: Data(environment.utf8))
            }
            let result = try await service.inspect(name: name, configuration: input)
            inspection = result; tools = result.tools
        }
    }
    private func save() {
        perform { service in
            if let initial { try await service.setAccess(id: initial.id, selectedTools: selected, agentIDs: selectedAgents) }
            else if let inspection { _ = try await service.save(inspection, selectedTools: selected, agentIDs: selectedAgents) }
            dismiss()
        }
    }
    private func refresh() {
        guard let initial else { return }
        perform { service in
            selected = []; try await service.refresh(id: initial.id)
            tools = try await service.access().first { $0.id == initial.id }?.tools ?? []
        }
    }
    private func disconnect() {
        guard let initial else { return }
        perform { service in try await service.disconnect(id: initial.id); dismiss() }
    }
}

private struct MCPAccessFields: View {
    let tools: [MCPTool]
    let agents: [BlotV3.AgentProfile]
    @Binding var selected: Set<String>
    @Binding var selectedAgents: Set<UUID>
    let russian: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(russian ? "Инструменты" : "Tools").font(.headline)
            if tools.isEmpty { Text(russian ? "Сервер не предоставил инструменты." : "The server returned no tools.") }
            ForEach(tools) { tool in
                Toggle(isOn: Binding(get: { selected.contains(tool.name) }, set: { if $0 { selected.insert(tool.name) } else { selected.remove(tool.name) } })) {
                    VStack(alignment: .leading) { Text(tool.name); Text(tool.description).font(.caption).foregroundStyle(.secondary) }
                }
                DisclosureGroup(russian ? "Схема аргументов" : "Argument schema") {
                    Text(String(decoding: (try? JSONEncoder().encode(tool.inputSchema)) ?? Data(), as: UTF8.self)).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Divider()
            Text(russian ? "Агенты" : "Agents").font(.headline)
            ForEach(agents, id: \.metadata.id) { agent in
                Toggle(agent.name, isOn: Binding(get: { selectedAgents.contains(agent.metadata.id) }, set: { if $0 { selectedAgents.insert(agent.metadata.id) } else { selectedAgents.remove(agent.metadata.id) } }))
            }
        }.toggleStyle(WorkspacePanelToggleStyle())
    }
}
