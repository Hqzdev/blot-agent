import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

struct WorkspaceTeamBotsButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { BlotLabel("Team Bots Manage", symbol: "person.3") }
            .disabled(store.collaborationCommands == nil)
            .workspacePanelSheet(isPresented: $showing) { WorkspaceTeamBotsView().environment(store) }
    }
}

private struct TeamBotSelection: Identifiable { let id = UUID(); let bot: WorkspaceTeamBot? }
struct WorkspaceTeamBotsView: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var teams: [WorkspaceTeam] = []
    @State private var teamID: UUID?
    @State private var bots: [WorkspaceTeamBot] = []
    @State private var members: [WorkspaceTeamMember] = []
    @State private var name = ""
    @State private var email = ""
    @State private var role = "member"
    @State private var token = ""
    @State private var invitation: WorkspaceTeamInvite?
    @State private var editor: TeamBotSelection?
    @State private var working = false
    @State private var failure: String?
    @State private var runtimeStatus: String?
    @State private var removing: WorkspaceTeamMember?
    private var ru: Bool { store.language == "ru" }
    private var team: WorkspaceTeam? { teams.first { $0.id == teamID } }
    private var admin: Bool { ["owner", "admin"].contains(team?.role ?? "") }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Section(ru ? "Команды" : "Teams") {
                    WorkspaceChoice(title: ru ? "Команда" : "Team", selection: $teamID, options: teams.map { .init(Optional($0.id), $0.name) })
                        .onChange(of: teamID) { _, _ in _Concurrency.Task { await loadTeam() } }
                    TextField(ru ? "Название команды" : "Team name", text: $name)
                    Button(ru ? "Создать команду" : "Create team") { createTeam() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    DisclosureGroup(ru ? "Принять приглашение" : "Accept invitation") {
                        TextField(ru ? "Код приглашения" : "Invitation code", text: $token)
                        Button(ru ? "Вступить" : "Join") { accept() }.disabled(token.isEmpty)
                    }
                }
                if let team {
                    Section(ru ? "Участники и роли" : "Members and roles") {
                        ForEach(members) { member in
                            HStack {
                                VStack(alignment: .leading) { Text(member.name); Text(member.email + " · " + member.role).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                if admin && member.role != "owner", member.role != "admin" || team.role == "owner" {
                                    Button(store.t("Delete"), role: .destructive) { removing = member }
                                }
                            }
                        }
                        if admin {
                            TextField("Email", text: $email)
                            WorkspaceChoice(title: ru ? "Роль" : "Role", selection: $role, options: [.init("member", ru ? "Участник" : "Member"), .init("admin", ru ? "Администратор" : "Admin")])
                            Button(ru ? "Создать приглашение" : "Create invitation") { invite() }.disabled(email.isEmpty)
                            if let invitation {
                                Text(invitation.token).font(.caption.monospaced()).textSelection(.enabled)
                                Text(ru ? "Передайте этот код участнику. Он сможет принять его только из подтверждённого аккаунта с указанным email." : "Share this code with the invitee. It can only be accepted by the verified account matching the email.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section("Team Bots Manage") {
                        if let runtimeStatus { Text(runtimeStatus).font(.caption).foregroundStyle(.orange) }
                        Text(ru ? "Бот выполняется на выбранном физическом Mac, пока Ori запущен. Права бота ограничены выбранными инструментами и каналами. Секреты подключений остаются на устройстве исполнителя." : "Bots run on the selected physical Mac while Ori is open. Access is limited to selected tools and channels. Connection secrets remain on the executor device.").font(.caption).foregroundStyle(.secondary)
                        ForEach(bots) { bot in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(bot.configuration.name).font(.headline)
                                Text(bot.configuration.enabled ? (ru ? "Включён" : "Enabled") : (ru ? "На паузе" : "Paused")).foregroundStyle(.secondary)
                                if admin, bot.ownerID == store.snapshot.ownerID { Button(store.t("Edit")) { editor = .init(bot: bot) } }
                            }
                        }
                        if admin { Button(ru ? "Новый бот" : "New bot") { editor = .init(bot: nil) }.disabled(store.snapshot.agents.isEmpty) }
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.disabled(working)

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: "Team Bots") {
                    Button(store.t("Close")) { dismiss() }.disabled(working)
                }
            }.workspaceEditorChrome()
        }
        .task { await reload() }
        .task {
            while !_Concurrency.Task.isCancelled {
                runtimeStatus = await store.collaborationCommands?.teamBotStatus()
                do { try await _Concurrency.Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
        .workspacePanelSheet(item: $editor, onDismiss: { _Concurrency.Task { await loadTeam() } }) { selection in
            if let team { WorkspaceTeamBotEditor(team: team, initial: selection.bot).environment(store) }
        }
        .workspaceConfirmationDialog(ru ? "Удалить участника и принадлежащих ему ботов?" : "Remove this member and their bots?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button(store.t("Delete"), role: .destructive) { if let removing, let teamID { perform { try await $0.removeMember(teamID, account: removing.id) } }; removing = nil }
        }
        #if os(macOS)
        .frame(minWidth: 620, minHeight: 640)
        #endif
    }
    private func reload() async { do { teams = try await store.collaborationCommands?.collaborationClient().teams() ?? []; if !teams.contains(where: { $0.id == teamID }) { teamID = teams.first?.id }; await loadTeam() } catch { failure = WorkspaceFailureCopy.message(error) } }
    private func loadTeam() async {
        guard let id = teamID, let commands = store.collaborationCommands else { return }
        do { let client = commands.collaborationClient(); bots = try await client.bots(id); members = try await client.members(id) }
        catch { failure = WorkspaceFailureCopy.message(error) }
    }
    private func createTeam() { perform { client in let created = try await client.createTeam(name); teamID = created.id; name = "" } }
    private func accept() { perform { try await $0.accept(token); token = "" } }
    private func invite() { guard let teamID else { return }; perform { invitation = try await $0.invite(teamID, email: email, role: role) } }
    private func perform(_ action: @escaping @MainActor (WorkspaceCollaborationClient) async throws -> Void) {
        guard !working, let commands = store.collaborationCommands else { return }; working = true; failure = nil
        _Concurrency.Task { defer { working = false }; do { try await action(commands.collaborationClient()); await reload() } catch { failure = WorkspaceFailureCopy.message(error) } }
    }
}

private struct WorkspaceTeamBotEditor: View {
    let team: WorkspaceTeam
    let initial: WorkspaceTeamBot?
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var name = ""
    @State private var agentID: UUID?
    @State private var deviceID: UUID?
    @State private var instructions = ""
    @State private var tools: Set<String> = []
    @State private var channels: [WorkspaceTeamBot.Channel] = []
    @State private var enabled = false
    @State private var working = false
    @State private var failure: String?
    @State private var deleting = false
    private var ru: Bool { store.language == "ru" }
    private var availableTools: [String] { (store.snapshot.configurations ?? []).first { $0.metadata.id == store.snapshot.agents.first { $0.metadata.id == agentID }?.configurationId }?.toolIds ?? [] }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                TextField(store.t("Name"), text: $name)
                WorkspaceChoice(title: ru ? "Агент" : "Agent", selection: $agentID, options: store.snapshot.agents.map { .init(Optional($0.metadata.id), $0.name) })
                    .onChange(of: agentID) { _, _ in tools.formIntersection(availableTools) }
                WorkspaceChoice(title: ru ? "Mac исполнитель" : "Executor Mac", selection: $deviceID, options: store.snapshot.devices.filter { $0.kind == .desktop && !$0.revoked }.map { .init(Optional($0.metadata.id), $0.name) })
                Toggle(ru ? "Бот включён" : "Bot enabled", isOn: $enabled)
                TextField(ru ? "Правила команды" : "Team rules", text: $instructions, axis: .vertical).lineLimit(4...10)
                Section(ru ? "Разрешённые инструменты" : "Allowed tools") {
                    ForEach(availableTools, id: \.self) { tool in Toggle(tool, isOn: Binding(get: { tools.contains(tool) }, set: { if $0 { tools.insert(tool) } else { tools.remove(tool) } })) }
                    Text(ru ? "Список ограничивает права агента. Внешние изменения всё равно подтверждает владелец на Mac." : "This list narrows the agent’s permissions. External changes still require owner review on the Mac.").font(.caption).foregroundStyle(.secondary)
                }
                Section(ru ? "Каналы" : "Channels") {
                    ForEach(channels.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 8) {
                            WorkspaceChoice(title: ru ? "Сервис" : "Service", selection: $channels[index].provider, options: [.init("slack", "Slack"), .init("teams", "Teams")])
                            TextField(ru ? "ID подключения из настроек" : "Connection ID from settings", text: $channels[index].connectionID)
                            TextField(channels[index].provider == "slack" ? "Slack workspace ID" : "Microsoft team ID", text: $channels[index].workspace)
                            TextField(ru ? "ID канала" : "Channel ID", text: $channels[index].channel)
                            TextField(ru ? "Обращение к боту" : "Trigger text", text: $channels[index].trigger)
                            Button(store.t("Delete"), role: .destructive) { channels.remove(at: index) }
                        }
                    }
                    Button(ru ? "Добавить канал" : "Add channel") { channels.append(.init()) }
                }
                if initial != nil { Button(store.t("Delete"), role: .destructive) { deleting = true } }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.disabled(working)

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: "Team Bot Manage") {
                    Button(store.t("Cancel")) { dismiss() }.disabled(working)
                    Button(store.t("Save")) { save() }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(working || agentID == nil || deviceID == nil || name.isEmpty || instructions.isEmpty)
                }
            }.workspaceEditorChrome()
        }
        .onAppear {
            let config = initial?.configuration; name = config?.name ?? ""; instructions = config?.instructions ?? ""; enabled = config?.enabled ?? false
            agentID = config?.agentID ?? store.snapshot.agents.first?.metadata.id; deviceID = config?.executorDeviceID ?? store.snapshot.devices.first { $0.kind == .desktop }?.metadata.id
            tools = Set(config?.allowedTools ?? []); channels = config?.channels ?? []
        }
        .workspaceConfirmationDialog(store.t("Delete") + "?", isPresented: $deleting, titleVisibility: .visible) { Button(store.t("Delete"), role: .destructive) { remove() } }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 650)
        #endif
    }
    private func save() {
        guard let agentID, let deviceID else { return }
        perform { client in _ = try await client.saveBot(team.id, id: initial?.id ?? UUID(), version: initial?.version ?? 0, configuration: .init(name: name, agentID: agentID, executorDeviceID: deviceID, instructions: instructions, allowedTools: tools.sorted(), channels: channels, enabled: enabled)) }
    }
    private func remove() { guard let initial else { return }; perform { try await $0.deleteBot(initial) } }
    private func perform(_ action: @escaping @MainActor (WorkspaceCollaborationClient) async throws -> Void) {
        guard !working, let commands = store.collaborationCommands else { return }; working = true
        _Concurrency.Task { defer { working = false }; do { try await action(commands.collaborationClient()); dismiss() } catch { failure = WorkspaceFailureCopy.message(error) } }
    }
}
