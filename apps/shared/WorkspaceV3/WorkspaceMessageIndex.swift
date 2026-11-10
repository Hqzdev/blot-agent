import BlotDomain
import BlotWorkspace
import Foundation

/// Message ordering is computed once per snapshot, rather than for every view read.
struct WorkspaceMessageIndex {
    private let conversations: [UUID: [BlotV3.Message]]
    private let visible: [UUID: [BlotV3.Message]]
    private let byID: [UUID: BlotV3.Message]
    private let orderedIDs: [UUID: [UUID]]
    private let lastUsers: [UUID: BlotV3.Message]
    private let runningResponses: [UUID: [BlotV3.Message]]

    init(_ messages: [BlotV3.Message] = []) {
        conversations = Dictionary(grouping: messages, by: \.conversationId).mapValues(WorkspaceMessageOrder.ordered)
        visible = conversations.mapValues { $0.filter(WorkspaceMessagePresentation.isVisible) }
        byID = Dictionary(messages.map { ($0.metadata.id, $0) }, uniquingKeysWith: { _, latest in latest })
        orderedIDs = conversations.mapValues { $0.map(\.metadata.id) }
        lastUsers = conversations.compactMapValues { $0.last { $0.role == .user } }
        runningResponses = conversations.mapValues { messages in
            guard let source = messages.last(where: { $0.role == .user }) else { return [] }
            return messages.filter { $0.role == .assistant && $0.commandId == source.commandId && $0.delivery == .running }
        }
    }

    func messages(in conversationID: UUID?) -> [BlotV3.Message] {
        guard let conversationID else { return [] }
        return conversations[conversationID] ?? []
    }
    func visibleMessages(in conversationID: UUID?) -> [BlotV3.Message] {
        guard let conversationID else { return [] }
        return visible[conversationID] ?? []
    }
    func message(_ id: UUID) -> BlotV3.Message? { byID[id] }
    func ids(in conversationID: UUID?) -> [UUID] { conversationID.flatMap { orderedIDs[$0] } ?? [] }
    func lastUser(in conversationID: UUID) -> BlotV3.Message? { lastUsers[conversationID] }
    func activeResponses(in conversationID: UUID) -> [BlotV3.Message] { runningResponses[conversationID] ?? [] }
}
