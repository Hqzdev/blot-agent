import BlotDomain

/// Multiple speakers share the assistant role in a group; keep their identity in model context.
enum WorkspaceGroupMessageContext {
    static func content(_ message: BlotV3.Message, projection: WorkspaceProjection) -> String {
        guard message.role == .assistant,
              projection.conversations.contains(where: { $0.metadata.id == message.conversationId && $0.kind == .group }) else {
            return message.content
        }
        let name = projection.agents.first { $0.metadata.id == message.authorAgentId }?.name ?? "Agent"
        return "[" + name + "]\n" + message.content
    }
}
