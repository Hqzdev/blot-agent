import BlotDesign
import Foundation

extension AppState {
    @discardableResult func forkConversation(_ item: SidebarConversation) -> SidebarConversation? {
        let id = UUID().uuidString
        let title = "Fork · " + item.title
        switch item.kind {
        case .chat:
            guard let source = workChat.session(item.taskID) else { return nil }
            let chat = WorkChatSession(id: id, title: title, projectID: source.projectID,
                                       messages: source.messages, assistant: source.assistant)
            workChat.add(chat)
            let result = SidebarConversation(id: "chat:" + id, title: title, project: item.project,
                                             taskID: id, running: false, kind: .chat)
            openConversation(result)
            return result
        case .task, .team:
            return nil

        }
    }

    func createSideChat(for item: SidebarConversation) -> WorkChatSession {
        let project = workChat.projects.contains { $0.id == item.project } ? item.project : nil
        let session = WorkChatSession(title: "Side chat · " + item.title, projectID: project,
            messages: [WorkChatMessage(text: "Context from \(item.title):\n\n" + transcript(for: item), fromUser: false)])
        workChat.add(session)
        return session
    }
}
