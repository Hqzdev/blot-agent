import BlotDomain
import Foundation

/// Reduces account records to bounded widget content. Credentials and message bodies never leave the app database.
public struct WidgetSnapshotProjector {
    public init() {}

    public func project(ownerID: UUID?, agents: [BlotV3.AgentProfile], conversations: [BlotV3.Conversation],
                        messages: [BlotV3.Message], tasks: [BlotV3.Task], actions: [BlotV3.PreparedAction],
                        schedules: [WidgetSchedule], language: String, now: Date) -> WidgetSnapshot {
        guard let ownerID else { return WidgetSnapshot(updatedAt: now, language: language) }
        let chats = conversations.filter { $0.metadata.ownerId == ownerID && !$0.archived }
            .sorted { $0.metadata.updatedAt > $1.metadata.updatedAt }
        let chatIDs = Set(chats.map(\.metadata.id))
        let visibleTasks = tasks.filter { $0.metadata.ownerId == ownerID && chatIDs.contains($0.conversationId) }
        let tasksByID = Dictionary(visibleTasks.map { ($0.metadata.id, $0) }, uniquingKeysWith: { first, _ in first })
        let waitingActions = actions.filter {
            $0.metadata.ownerId == ownerID && $0.state == .waiting_approval && $0.expiresAt > now && tasksByID[$0.execution.taskId] != nil
        }.sorted { $0.metadata.createdAt < $1.metadata.createdAt }
        var decisions = waitingActions.compactMap { action -> WidgetDecision? in
            guard let task = tasksByID[action.execution.taskId] else { return nil }
            return .init(id: action.metadata.id, conversationID: task.conversationId,
                         title: String(task.goal.prefix(120)), expiresAt: action.expiresAt)
        }
        let actionTaskIDs = Set(waitingActions.map(\.execution.taskId))
        decisions += visibleTasks.filter { $0.state == .waiting_user && !actionTaskIDs.contains($0.metadata.id) }.map {
            .init(id: $0.metadata.id, conversationID: $0.conversationId, title: String($0.goal.prefix(120)), expiresAt: nil)
        }
        let waitingChats = Set(decisions.map(\.conversationID))
        let tasksByChat = Dictionary(grouping: visibleTasks, by: \.conversationId)
        let messagesByChat = Dictionary(grouping: messages.filter { $0.metadata.ownerId == ownerID && $0.role == .user }, by: \.conversationId)
        let summaries = chats.map { chat -> WidgetConversation in
            let task = tasksByChat[chat.metadata.id]?.max { $0.metadata.updatedAt < $1.metadata.updatedAt }
            let message = messagesByChat[chat.metadata.id]?.max { $0.metadata.createdAt < $1.metadata.createdAt }
            let state: WidgetWorkState
            if waitingChats.contains(chat.metadata.id) { state = .waiting }
            else if let task, task.metadata.updatedAt >= (message?.metadata.updatedAt ?? .distantPast) { state = Self.state(task.state) }
            else { state = message.map { Self.state($0.delivery) } ?? .idle }
            return .init(id: chat.metadata.id, title: String(chat.title.prefix(120)), agentID: chat.agentId, state: state)
        }
        let byAgent = Dictionary(grouping: summaries.compactMap { chat in chat.agentID.map { ($0, chat.state) } }, by: { $0.0 })
        let team = agents.filter { $0.metadata.ownerId == ownerID }.sorted { $0.metadata.createdAt < $1.metadata.createdAt }.prefix(12).map { agent in
            let states = byAgent[agent.metadata.id]?.map { $0.1 } ?? []
            let state: WidgetWorkState = states.contains(.waiting) ? .waiting : states.contains(.running) ? .running : .idle
            return WidgetAgent(id: agent.metadata.id, name: String(agent.name.prefix(60)), shape: agent.avatarShape,
                               color: agent.avatarColor, state: state)
        }
        let prioritized = summaries.sorted { Self.priority($0.state) < Self.priority($1.state) }
        return .init(ownerID: ownerID, updatedAt: now, language: language, agents: team,
                     conversations: Array(prioritized.prefix(8)), decisions: decisions,
                     schedules: Array(schedules.filter { $0.nextRun > now }.sorted { $0.nextRun < $1.nextRun }.prefix(8)),
                     runningCount: summaries.filter { $0.state == .running }.count,
                     completedCount: summaries.filter { $0.state == .completed }.count)
    }

    private static func priority(_ state: WidgetWorkState) -> Int {
        switch state { case .waiting: 0; case .running: 1; default: 2 }
    }
    private static func state(_ value: BlotV3.TaskState) -> WidgetWorkState {
        switch value {
        case .planning, .queued, .running: .running
        case .waiting_approval, .waiting_user: .waiting
        case .completed: .completed
        case .failed, .interrupted: .failed
        case .paused: .paused
        case .draft, .canceled: .idle
        }
    }
    private static func state(_ value: BlotV3.DeliveryState) -> WidgetWorkState {
        switch value {
        case .saved, .delivered, .accepted, .running: .running
        case .completed: .completed
        case .failed, .interrupted: .failed
        case .waiting_connection: .offline
        case .canceled: .idle
        }
    }
}
