import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceNativeProjectsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var projects: [WorkspaceNativeProject] = []
    @State private var processes: [NativeProcessSnapshot] = []
    @State private var importing = false
    @State private var folder: NativeFolderChoice?
    @State private var error: String?
    @State private var diff: String?
    @State private var busy = false
    @State private var selectedID: UUID?
    @State private var resolving: UUID?
    private var ru: Bool { store.language == "ru" }
    private func text(_ ru: String, _ en: String) -> String { self.ru ? ru : en }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(text("Проекты, терминал и Git", "Projects, terminal and Git")).font(.title2.bold())
            Text(text("Команды выполняются на Mac. Код доверенного проекта имеет доступ пользователя и не изолирован внутри его папки.", "Commands run on your Mac. Trusted project code has user-level access and is not isolated inside its folder.")).font(.callout).foregroundStyle(.secondary)
            if let center = store.appleIntegrations?.interactions, let interaction = center.pending, interaction.kind == .confirmation {
                WorkspaceCard {
                    Text(text("Требуется подтверждение", "Confirmation required")).font(.headline)
                    Text(interaction.title)
                    ScrollView { Text(interaction.details).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 240)
                    HStack {
                        Button(text("Отмена", "Cancel"), role: .cancel) { center.finish(interaction.id, result: .success(.bool(false))) }
                        Spacer()
                        Button(text("Разрешить один раз", "Allow once")) { center.finish(interaction.id, result: .success(.bool(true))) }.buttonStyle(WorkspaceButtonStyle())
                    }
                }
            }
            #if os(macOS)
            Button(text("Подключить папку…", "Connect folder…")) { importing = true }.buttonStyle(WorkspaceButtonStyle()).disabled(busy)
            #endif
            if store.selectedConversationID != nil {
                WorkspaceChoice(title: text("Проект этого чата", "Project for this chat"), selection: $selectedID,
                    options: [.init(nil, text("Без проекта", "No project"))] + projects.map { .init(Optional($0.id), $0.name) }).disabled(busy)
                .onChange(of: selectedID) { _, value in select(value) }
            }
            ForEach(projects) { project in
                WorkspaceCard {
                    Text(project.name).font(.headline)
                    Text(project.root).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(text("Доверенные операции: ", "Trusted operations: ") + (project.trustedClasses.isEmpty ? text("каждое изменение подтверждается", "confirm every change") : project.trustedClasses.sorted().map { NativeOperationLabel.title($0, russian: ru) }.joined(separator: ", "))).font(.caption)
                    HStack {
                        Button(text("Посмотреть diff", "View diff")) { readDiff(project.id) }
                        Button(text("Отозвать доступ", "Revoke access"), role: .destructive) { disconnect(project.id) }
                    }.disabled(busy)
                }
            }
            ForEach((store.snapshot.projects ?? []).filter { record in !projects.contains { $0.id == record.metadata.id } }, id: \.metadata.id) { project in
                WorkspaceCard { Text(project.name).font(.headline); Text(text("Подключён на другом устройстве. Выберите его при отправке задачи на Mac.", "Connected on another device. Select it when delegating a task to that Mac.")).font(.caption).foregroundStyle(.secondary) }
            }
            ForEach(processes) { process in NativeProcessCard(process: process, russian: ru) { stop(process.id) } }
            ForEach(nativeActions, id: \.metadata.id) { action in
                if let invocation = store.snapshot.toolInvocations?.first(where: { $0.preparedActionId == action.metadata.id }),
                   !processes.contains(where: { process in action.toolId == "process_run" && invocation.result?.contains(process.id.uuidString) == true }) {
                    WorkspaceCard {
                    Text(NativeOperationLabel.title(action.toolId, russian: ru)).font(.headline)
                        Text(invocation.state.rawValue).font(.caption).foregroundStyle(.secondary)
                        if let result = invocation.result { Text(result).font(.caption.monospaced()).textSelection(.enabled) }
                        if invocation.state == .unknown && invocation.execution.executorDeviceId == store.snapshot.localDeviceID {
                            Text(action.parameters).font(.caption.monospaced()).textSelection(.enabled)
                            Text(action.consequences).font(.caption.monospaced()).textSelection(.enabled)
                            if action.toolId == "git_push" {
                                Button(text("Проверить remote", "Check remote")) { checkRemote(invocation.metadata.id) }
                            }
                            Button(text("Сверить результат…", "Reconcile outcome…")) { resolving = invocation.metadata.id }
                        }
                    }
                }
            }
            if let diff { DisclosureGroup(text("Изменения проекта", "Project changes")) { ScrollView(.horizontal) { Text(diff).font(.caption.monospaced()).textSelection(.enabled) } } }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .task {
            await reload()
            while !_Concurrency.Task.isCancelled {
                do {
                    try await _Concurrency.Task.sleep(for: .milliseconds(500))
                    guard let commands = store.nativeCommands else { return }
                    processes = try await commands.nativeService().processSnapshots()
                    try await store.refreshMCP()
                } catch { return }
            }
        }
        .workspacePanelSheet(item: $folder, onDismiss: { _Concurrency.Task { await reload() } }) { folder in NativeProjectSetup(folder: folder.url, agents: store.snapshot.agents, russian: ru, commands: store.nativeCommands) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { folder = NativeFolderChoice(url: url) }
            else if case .failure(let error) = result { self.error = error.localizedDescription }
        }
        .confirmationDialog(text("Сначала проверьте результат в проекте. Решение не повторяет действие.", "Verify the outcome in the project first. This decision does not repeat the action."), isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
            Button(text("Проверено: выполнено", "Verified: completed")) { resolve(true) }
            Button(text("Проверено: не выполнено", "Verified: not completed")) { resolve(false) }
        }
    }
    private var nativeActions: [BlotV3.PreparedAction] { (store.snapshot.preparedActions ?? []).filter { $0.resource.hasPrefix("project:") }.sorted { $0.metadata.createdAt > $1.metadata.createdAt } }
    private func reload() async {
        do {
            guard let service = try await store.nativeCommands?.nativeService() else { return }
            projects = try await service.projects()
            if let conversation = store.selectedConversationID { selectedID = try await service.selectedProject(conversationID: conversation) }
            processes = await service.processSnapshots(); try await store.refreshMCP()
        } catch { self.error = error.localizedDescription }
    }
    private func work(_ action: @escaping @MainActor (WorkspaceNativeService) async throws -> Void) {
        guard !busy, let commands = store.nativeCommands else { return }; busy = true; error = nil
        _Concurrency.Task {
            defer { busy = false }
            do { try await action(commands.nativeService()); await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func select(_ id: UUID?) { guard let conversation = store.selectedConversationID else { return }; work { try await $0.select(projectID: id, conversationID: conversation) } }
    private func disconnect(_ id: UUID) { work { try await $0.disconnect(id) } }
    private func stop(_ id: UUID) { work { try await $0.stopProcess(id) } }
    private func readDiff(_ id: UUID) { work { diff = try await $0.inspect(projectID: id, operation: .gitDiff) } }
    private func resolve(_ succeeded: Bool) { guard let id = resolving else { return }; resolving = nil; work { try await $0.resolve(invocationID: id, succeeded: succeeded) } }
    private func checkRemote(_ id: UUID) {
        work { service in
            if try await !service.checkRemote(invocationID: id) { error = text("Remote не подтвердил этот коммит в выбранной ветке. Исход остаётся неизвестным.", "The remote did not confirm this commit at the selected ref. The outcome remains unknown.") }
        }
    }
}

private struct NativeFolderChoice: Identifiable { let id = UUID(); let url: URL }

struct WorkspaceNativeProjectButton: View {
    @State private var visible = false
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    var body: some View {
        Button {
            if let panelNavigation { panelNavigation.path.append(.projects) }
            else { visible = true }
        } label: { Label(store.language == "ru" ? "Проект и терминал" : "Project and terminal", systemImage: "terminal") }
            .font(.caption).disabled(store.nativeCommands == nil)
            .workspacePanelSheet(isPresented: $visible) {
                NavigationStack {
                    ScrollView { WorkspaceNativeProjectsView().padding(24) }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.language == "ru" ? "Закрыть" : "Close") { visible = false } } }
                }
                #if os(macOS)
                .frame(width: 760, height: 650)
                #endif
            }
    }
}

private struct NativeProcessCard: View {
    let process: NativeProcessSnapshot
    let russian: Bool
    let stop: () -> Void
    var body: some View {
        WorkspaceCard {
            Text(([process.executable] + process.arguments).joined(separator: " ")).font(.caption.monospaced()).textSelection(.enabled)
            HStack {
                Text(process.state.rawValue)
                if let exit = process.exitCode { Text("exit \(exit)") }
                Spacer()
                if process.finishedAt == nil { Button(russian ? "Остановить" : "Stop", role: .destructive, action: stop) }
            }.font(.caption)
            DisclosureGroup("stdout") { ScrollView([.horizontal, .vertical]) { Text(process.stdout).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 220) }
            DisclosureGroup("stderr") { ScrollView([.horizontal, .vertical]) { Text(process.stderr).font(.caption.monospaced()).textSelection(.enabled) }.frame(maxHeight: 160) }
            if process.truncated { Text(russian ? "Вывод усечён по лимиту." : "Output was truncated at the limit.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct NativeProjectSetup: View {
    let folder: URL
    let agents: [BlotV3.AgentProfile]
    let russian: Bool
    let commands: (any WorkspaceNativeProviding)?
    @WorkspacePresentationDismiss private var dismiss
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    @State private var selected: Set<UUID> = []
    @State private var trusted: Set<String> = []
    @State private var trustCLI = false
    @State private var variables = "{}"
    @State private var token = ""
    @State private var credentialURL = ""
    @State private var sshSocket = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Text(folder.lastPathComponent).font(.headline)
                Text(folder.path).font(.caption).textSelection(.enabled)
                Toggle(russian ? "Доверяю выполнению кода проекта на этом Mac" : "Trust executing this project’s code on this Mac", isOn: $trustCLI)
                Text(russian ? "Команды работают с доступом пользователя. Выбор папки не изолирует скрипты проекта." : "Commands have user-level access. Selecting a folder does not isolate project scripts.").font(.caption).foregroundStyle(.secondary)
                Section(russian ? "Агенты" : "Agents") {
                    ForEach(agents, id: \.metadata.id) { agent in
                        Toggle(agent.name, isOn: Binding(get: { selected.contains(agent.metadata.id) }, set: { if $0 { selected.insert(agent.metadata.id) } else { selected.remove(agent.metadata.id) } }))
                    }
                }
                Section(russian ? "Не спрашивать для этих операций" : "Trust these operation classes") {
                    ForEach(WorkspaceNativeCatalog.trustedClasses, id: \.self) { operation in
                        Toggle(NativeOperationLabel.title(operation, russian: russian), isOn: Binding(get: { trusted.contains(operation) }, set: { if $0 { trusted.insert(operation) } else { trusted.remove(operation) } }))
                    }
                    Text(russian ? "Push всегда подтверждается отдельно. Права можно отозвать в списке проектов." : "Push always requires separate confirmation. Revoke access from the project list.").font(.caption)
                }
                Section(russian ? "Защищённые настройки" : "Protected settings") {
                    SecureField(russian ? "Переменные среды — JSON" : "Environment variables — JSON", text: $variables)
                    TextField(russian ? "HTTPS URL для Git-токена" : "HTTPS URL for Git credential", text: $credentialURL)
                    SecureField(russian ? "Git HTTPS Bearer-токен" : "Git HTTPS bearer token", text: $token)
                    TextField(russian ? "Сокет SSH agent (необязательно)" : "SSH agent socket (optional)", text: $sshSocket)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button(russian ? "Подключить проект" : "Connect project") { connect() }.disabled(busy || !trustCLI || selected.isEmpty)
            }.disabled(busy)
            .navigationTitle(russian ? "Доступ к проекту" : "Project access")
            .safeAreaInset(edge: .top, spacing: 0) {
                if panelNavigation != nil { WorkspacePanelFormHeader(title: russian ? "Доступ к проекту" : "Project access") { Button(russian ? "Отмена" : "Cancel") { dismiss() }.disabled(busy) } }
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { if panelNavigation == nil { Button(russian ? "Отмена" : "Cancel") { dismiss() }.disabled(busy) } } }
        }
        #if os(macOS)
        .frame(width: panelNavigation == nil ? 660 : nil, height: panelNavigation == nil ? 650 : nil)
        #endif
        .interactiveDismissDisabled(busy)
    }
    private func connect() {
        guard let commands else { return }; busy = true; error = nil
        _Concurrency.Task {
            defer { busy = false }
            do {
                let scope = folder.startAccessingSecurityScopedResource(); defer { if scope { folder.stopAccessingSecurityScopedResource() } }
                #if os(macOS)
                let bookmark = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                _ = try await commands.nativeService().connect(name: folder.lastPathComponent, root: folder, bookmark: bookmark, agents: selected,
                    trustedClasses: trusted, variables: JSONDecoder().decode([String: String].self, from: Data(variables.utf8)), gitToken: token, gitCredentialURL: credentialURL, sshAuthSocket: sshSocket, trustedCLI: trustCLI)
                dismiss()
                #else
                throw NativeExecutionError.unavailable
                #endif
            } catch { self.error = error.localizedDescription }
        }
    }
}

private enum NativeOperationLabel {
    static func title(_ key: String, russian: Bool) -> String {
        let ru = ["file.write": "Изменение файлов", "project_write_file": "Изменение файла", "process.run": "Запуск команд", "process_run": "Запуск команды",
            "git.branch": "Создание веток", "git_branch": "Создание ветки", "git.commit": "Локальные коммиты", "git_commit": "Локальный коммит", "git_push": "Отправка коммитов"]
        let en = ["file.write": "Edit files", "project_write_file": "Edit file", "process.run": "Run commands", "process_run": "Run command",
            "git.branch": "Create branches", "git_branch": "Create branch", "git.commit": "Local commits", "git_commit": "Local commit", "git_push": "Push commits"]
        return (russian ? ru : en)[key] ?? key
    }
}
