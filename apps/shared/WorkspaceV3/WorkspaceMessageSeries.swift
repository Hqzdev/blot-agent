import BlotDomain
import Foundation

/// A reply remains one author series across long tool calls, but never across another speaker or request.
nonisolated enum WorkspaceMessageSeries {
    static func starts(_ message: BlotV3.Message, after previous: BlotV3.Message?) -> Bool {
        guard message.role == .assistant else { return false }
        guard let previous else { return true }
        return previous.role != .assistant || previous.authorAgentId != message.authorAgentId
            || previous.commandId != message.commandId || previous.conversationId != message.conversationId
    }
    static func authorIDs(in messages: [BlotV3.Message]) -> Set<UUID> {
        var previous: BlotV3.Message?
        return Set(messages.compactMap { message in
            defer { previous = message }
            return starts(message, after: previous) ? message.metadata.id : nil
        })
    }
}
