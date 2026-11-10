import BlotDomain
import BlotWidgetSupport
import Foundation

@MainActor
extension WorkspaceStore {
    @discardableResult func handleWidgetURL(_ url: URL) -> Bool {
        guard let destination = WidgetDestination(url: url) else { return false }
        _Concurrency.Task {
            await loadWorkspace()
            guard mode == .live, snapshot.ownerID != nil, !isRestoringSession, !busy else { return }
            switch destination {
            case .compose:
                await startNewChat()
            case .agents:
                selectTab(.chats); navigate(.agents)
            case .schedules:
                selectTab(.schedules)
            case .overview:
                selectTab(.overview)
            case .conversation(let id):
                guard snapshot.conversations.contains(where: { $0.metadata.id == id && !$0.archived }) else {
                    selectTab(.chats); return
                }
                openConversation(id)
            case .agent(let id):
                guard snapshot.agents.contains(where: { $0.metadata.id == id }) else { selectTab(.chats); navigate(.agents); return }
                await openAgentChat(id)
            }
        }
        return true
    }

    func publishWidgets(immediately: Bool = false) {
        guard mode == .live else { return }
        widgetPublisher.update(snapshot, language: language, immediately: immediately)
    }
}
