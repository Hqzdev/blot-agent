import BlotWorkspace
import BlotDesign
import BlotDomain
import SwiftUI

struct MacLiveTeamInspector: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.workspacePanelNavigation) private var panelNavigation
    @State private var editingGroup = false
    @State private var tab = "Обзор"
    private var isGroup: Bool { store.currentConversation?.kind == .group }
    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == (store.currentConversation?.agentId ?? store.selectedAgentID) }
    }
    private var members: [BlotV3.AgentProfile] {
        let ids = Set((store.snapshot.participants ?? []).filter { $0.conversationId == store.selectedConversationID && !$0.removed }.map(\.participantId))
        return store.snapshot.agents.filter { ids.contains($0.metadata.id) }
    }
    var body: some View {
        VStack(spacing: 0) {
            WorkspaceLocalizedText(isGroup ? "О группе" : "Об агенте").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).frame(height: 52)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        if isGroup { MacLiveTeamGroupAvatar(agents: members, size: 68) }
                        else if let agent { WorkspaceAvatarView(agent: agent, size: 68) }
                        else { WorkspaceAvatar(size: 68) }
                        Text(store.currentConversation?.title ?? agent?.name ?? "Ваша команда")
                            .font(.system(size: 21, weight: .medium)).multilineTextAlignment(.center)
                        if isGroup { Text("Участников: \(members.count)").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }.padding(.top, 12)
                    MacTeamSegmentedControl(title: "Раздел агента", options: ["Обзор", "Память", "Навыки"], selection: $tab)
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 18) {
                            switch tab {
                            case "Память":
                                ForEach(store.snapshot.memories.filter { $0.scopeId == agent?.metadata.id || $0.scopeId == nil }, id: \.metadata.id) { memory in
                                    Text(memory.content).font(.system(size: 12)).textSelection(.enabled)
                                }
                                Button("Вся память") { navigate(.memory) }.buttonStyle(.plain)
                            case "Навыки":
                                ForEach((store.snapshot.skills ?? []).filter { skill in !skill.archived && (store.snapshot.skillAssignments ?? []).contains { $0.skillID == skill.metadata.id && $0.agentID == agent?.metadata.id && $0.assigned } }, id: \.metadata.id) { skill in
                                    Label(skill.name, systemImage: "shippingbox")
                                }
                                Button("Навыки агента") { navigate(.skills) }
                                    .buttonStyle(.plain).disabled(agent == nil)
                            default: overview
                            }
                        }.id(tab).transition(.opacity).frame(maxWidth: .infinity, alignment: .leading)
                    }.kAnimation(KMotion.standard, value: tab)
                }.padding(18)
            }.scrollIndicators(.hidden)
        }
    }
    private func navigate(_ route: WorkspaceRoute) {
        if let panelNavigation { panelNavigation.open(route) } else { store.navigate(route) }
    }
    private func editAgent(_ id: UUID) {
        store.selectAgent(id, destination: .editAgent, navigating: panelNavigation == nil)
        panelNavigation?.open(.editAgent)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !members.isEmpty {
                Text("Участники").foregroundStyle(.secondary)
                ForEach(members, id: \.metadata.id) { member in
                    Button { editAgent(member.metadata.id) } label: {
                        HStack(spacing: 10) { WorkspaceAvatarView(agent: member, size: 30); Text(member.name); Spacer(); Image(systemName: "chevron.right") }
                    }.buttonStyle(.plain)
                }
            }
            if isGroup, let group = store.currentConversation {
                Button("Управлять участниками") { if panelNavigation != nil { editingGroup = true } else { store.editGroup(group.metadata.id) } }
                    .buttonStyle(WorkspaceButtonStyle(.secondary))
                if let agent { Text("Координатор: " + agent.name).font(.caption).foregroundStyle(.secondary) }
            } else if let agent {
                Text(agent.instructions).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
                Button("Настроить агента") { editAgent(agent.metadata.id) }.buttonStyle(.plain)
            }
            HStack {
                Text("Расписания").foregroundStyle(.secondary)
                Spacer()
                MacTeamIconButton(title: "Новое расписание", symbol: "plus") { navigate(.createSchedule) }
            }
            ForEach(store.snapshot.schedules.filter { $0.agentId == agent?.metadata.id }, id: \.metadata.id) { schedule in
                Button { store.selectedRecordID = schedule.metadata.id; navigate(.schedules) } label: {
                    Label(schedule.name, systemImage: "clock.arrow.circlepath")
                }.buttonStyle(.plain)
            }
            Button("Все расписания") { navigate(.schedules) }.buttonStyle(.plain)
            Text("Подключения").foregroundStyle(.secondary)
            Button("Все приложения") { navigate(.marketplace) }.buttonStyle(.plain)
            Button { navigate(.files) } label: { Label("Файлы и документы", systemImage: "folder") }.buttonStyle(.plain)
        }.font(.system(size: 12))
        .workspacePanelSheet(isPresented: $editingGroup) {
            WorkspaceGroupEditor(conversation: store.currentConversation, participants: store.snapshot.participants ?? [])
        }
    }
}
