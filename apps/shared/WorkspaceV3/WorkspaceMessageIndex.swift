import BlotDomain
import BlotWorkspace
import Foundation

/// Message ordering is computed once per snapshot, rather than for every view read.
struct WorkspaceMessageIndex {
    private let conversations: [UUID: [BlotV3.Message]]

    init(_ messages: [BlotV3.Message] = []) {
        conversations = Dictionary(grouping: messages, by: \.conversationId).mapValues(WorkspaceMessageOrder.ordered)
    }

    func messages(in conversationID: UUID?) -> [BlotV3.Message] {
        guard let conversationID else { return [] }
        return conversations[conversationID] ?? []
    }
}
