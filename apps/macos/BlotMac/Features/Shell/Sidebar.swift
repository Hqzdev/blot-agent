import BlotDesign
import SwiftUI

struct Sidebar: View {
    @Environment(AppState.self) private var app
    @State private var creatingProject = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Blot").font(KFont.sidebarTitle()).foregroundStyle(K.text)
                Spacer()
                IconButton(icon: "magnifyingglass", help: "Поиск · ⌘K") { app.openCommandPalette() }
            }.padding(.leading, 18).padding(.trailing, 10).frame(height: K.headerHeight)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SidebarItem(icon: "square.and.pencil", label: "Новый чат", meta: "⌘N",
                                active: app.isNewConversation && app.product == .work && app.workChat.selectedProjectID == nil) {
                        app.openQuickChat()
                    }
                    SidebarItem(icon: "folder.badge.plus", label: "Создать проект") { creatingProject = true }
                    switch app.shellSection {
                    case .scheduled: AutomationsSidebar()
                    case .skills: SkillsSidebar()
                    default: conversationList
                    }
                }.padding(.horizontal, 10).padding(.bottom, 16)
            }.scrollIndicators(.never)
            HDivider()
            VStack(spacing: 2) {
                SidebarItem(icon: "clock", label: "Автоматизации", active: app.shellSection == .scheduled) {
                    app.openSection(.scheduled)
                }
                SidebarItem(icon: "puzzlepiece.extension", label: "Навыки", active: app.shellSection == .skills) {
                    app.openSection(.skills)
                }
                SidebarItem(icon: "terminal", label: "Работа с кодом", active: app.product == .code && !app.isMotes && app.activeTool == nil) {
                    app.openHome()
                }
                SidebarItem(icon: "person.2", label: "Команда агентов", active: app.isMotes) { app.openNewRun() }
            }.padding(10)
            HStack(spacing: 6) {
                ProfileMenuButton()
                Text(app.currentUser?.name ?? "Blot").font(KFont.label()).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WorkspaceMoreMenu()
                IconButton(icon: "gearshape", help: "Настройки · ⌘,") { app.openProfileSettings(.general) }
            }.padding(.horizontal, 12).padding(.bottom, 12)
        }
        .background(K.bgSidebar.ignoresSafeArea())
        .sheet(isPresented: $creatingProject) { ProjectCreationView() }
    }

    private var conversationList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !pinned.isEmpty {
                SectionLabel(title: "Закреплено")
                ForEach(pinned) { row($0) }
            }
            SectionLabel(title: "Проекты")
            if app.workChat.projects.isEmpty {
                Text("Материалы и чаты для ваших задач")
                    .font(KFont.caption()).foregroundStyle(K.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
            ForEach(app.workChat.projects) { project in
                SidebarItem(icon: "folder", label: project.name,
                            active: app.product == .work && app.workChat.selectedProjectID == project.id && app.currentWorkChat == nil) {
                    app.openWorkChatProject(project.id)
                }
                if app.workChat.expandedProjectID == project.id {
                    ForEach(conversations.filter { $0.project == project.id && !app.shell.pins.contains($0.id) }) {
                        row($0, indented: true)
                    }
                }
            }
            let ungrouped = conversations.filter { $0.project.isEmpty && !app.shell.pins.contains($0.id) }
            if !ungrouped.isEmpty {
                SectionLabel(title: "Чаты")
                ForEach(ungrouped) { row($0) }
            }
            if !archived.isEmpty {
                SectionDisclosure(title: "Архив", expanded: Binding(get: { app.shell.archiveExpanded }, set: { app.shell.archiveExpanded = $0 }))
                if app.shell.archiveExpanded { ForEach(archived) { row($0) } }
            }
        }
    }

    private var allConversations: [SidebarConversation] {
        let chats = app.workChat.sessions.map {
            SidebarConversation(id: "chat:" + $0.id, title: $0.title, project: $0.projectID ?? "",
                                taskID: $0.id, running: $0.isSending, kind: .chat)
        }
        let tasks = app.projects.flatMap { project in project.tasks.map {
            SidebarConversation(id: "code:" + project.id + ":" + $0.id, title: $0.title, project: project.id,
                                taskID: $0.id, running: $0.isRunning, kind: .task)
        }}
        return chats + tasks
    }
    private var conversations: [SidebarConversation] { allConversations.filter { !app.shell.archived.contains($0.id) } }
    private var archived: [SidebarConversation] { allConversations.filter { app.shell.archived.contains($0.id) } }
    private var pinned: [SidebarConversation] { conversations.filter { app.shell.pins.contains($0.id) } }

    private func row(_ item: SidebarConversation, indented: Bool = false) -> some View {
        ConversationRow(item: item, selected: selected(item), indented: indented) {
            switch item.kind {
            case .chat: app.openWorkChat(item.taskID)
            case .task: app.openTask(projectID: item.project, taskID: item.taskID)
            case .team: app.openWorkRun(item.taskID)
            }
        }
    }
    private func selected(_ item: SidebarConversation) -> Bool {
        guard !app.showingSettings, !app.profileVisible, app.activeTool == nil else { return false }
        switch item.kind {
        case .chat: return app.product == .work && app.workRoute == .chat(id: item.taskID)
        case .task: return app.product == .code && app.codeRoute == .task(projectID: item.project, taskID: item.taskID)
        case .team: return app.isMotes && app.teamRoute == .chat(runID: item.taskID)
        }
    }
}
