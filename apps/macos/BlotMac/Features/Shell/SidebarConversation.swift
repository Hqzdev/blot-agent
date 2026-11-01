import BlotDesign
import Foundation

struct SidebarConversation: Identifiable {
    enum Kind { case task, team, chat }
    let id: String
    let title: String
    let project: String
    let taskID: String
    let running: Bool
    let kind: Kind
}

extension AppState {
    var currentConversation: SidebarConversation? {
        guard activeTool == nil, !profileVisible, !showingSettings else { return nil }
        if product == .work, let chat = currentWorkChat {
            return SidebarConversation(id: "chat:" + chat.id, title: chat.title, project: chat.projectID ?? "",
                                       taskID: chat.id, running: false, kind: .chat)
        }
        if isMotes, shellHasConversation, let run = currentWorkSession {
            return SidebarConversation(id: "motes:" + run.id, title: run.title, project: run.projectID,
                                       taskID: run.id, running: run.status == .running, kind: .team)
        }
        if product == .code, let task = currentTask {
            return SidebarConversation(id: "code:" + shellProjectID + ":" + task.id, title: task.title,
                                       project: shellProjectID, taskID: task.id, running: task.isRunning, kind: .task)
        }
        return nil
    }

    func openConversation(_ item: SidebarConversation) {
        switch item.kind {
        case .chat: openWorkChat(item.taskID)
        case .task: openTask(projectID: item.project, taskID: item.taskID)
        case .team: openWorkRun(item.taskID)
        }
    }

    func renameConversation(_ item: SidebarConversation, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if item.kind == .chat { workChat.session(item.taskID)?.rename(title) }
    }
}
