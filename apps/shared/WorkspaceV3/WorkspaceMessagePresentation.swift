import BlotDomain

/// Pending assistant records reserve ordering, but only settled messages enter the conversation.
nonisolated enum WorkspaceMessagePresentation {
    static func isVisible(_ message: BlotV3.Message) -> Bool {
        guard message.role == .assistant else { return true }
        switch message.delivery {
        case .saved, .waiting_connection, .delivered, .accepted, .running: return false
        default: return !message.content.isEmpty || !message.artifactIds.isEmpty
        }
    }
}
