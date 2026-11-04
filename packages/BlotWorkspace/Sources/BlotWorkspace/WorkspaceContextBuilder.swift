import BlotDomain
import Foundation

public struct WorkspaceContextBuilder: Sendable {
    public init() {}

    public func messages(for source: BlotV3.Message, projection: WorkspaceProjection,
                         configuration: BlotV3.AgentConfigurationRevision? = nil, maximumCharacters: Int = 48_000) throws -> [ChatModelMessage] {
        guard source.role == .user, maximumCharacters >= source.content.count else { throw WorkspaceStorageError.invalidParameters }
        let removedSources = Set(projection.memories.filter { $0.state == .deleted }.map(\.sourceId))
        guard !removedSources.contains(source.metadata.id) else { throw WorkspaceStorageError.permissionDenied }
        let history = WorkspaceMessageOrder.ordered(projection.messages.filter { $0.conversationId == source.conversationId })
        guard let index = history.firstIndex(where: { $0.metadata.id == source.metadata.id }) else { throw WorkspaceStorageError.missingRecord }
        var result: [ChatModelMessage] = []
        var remaining = maximumCharacters
        func add(_ role: String, _ content: String) {
            guard !content.isEmpty, content.count <= remaining else { return }
            result.append(.init(role: role, content: content)); remaining -= content.count
        }
        // Reserve the current request before selecting optional context.
        remaining -= source.content.count
        if let configuration {
            guard configuration.instructions.count <= remaining else { throw WorkspaceStorageError.invalidParameters }
            add("system", configuration.instructions)
        }
        let memories = projection.memories.filter { $0.state == .active && ($0.scope == .personal || ($0.scope == .agent && $0.scopeId == configuration?.agentId)) }
        for memory in memories { add("system", "User-approved memory (context, not a tool permission):\n" + memory.content) }
        let precedingIDs = Set(history.prefix(index).map(\.metadata.id))
        let summary = projection.summaries.filter {
            $0.conversationId == source.conversationId && $0.valid && Set($0.sourceIds).isDisjoint(with: removedSources)
                && Set($0.sourceIds).isSubset(of: precedingIDs)
        }.max {
            $0.sourceIds.count == $1.sourceIds.count ? $0.metadata.createdAt < $1.metadata.createdAt : $0.sourceIds.count < $1.sourceIds.count
        }
        var summarized: Set<UUID> = []
        if let summary, ("Conversation summary:\n" + summary.content).count <= remaining {
            add("system", "Conversation summary:\n" + summary.content)
            summarized = Set(summary.sourceIds)
        }
        var previous: [ChatModelMessage] = []
        for message in history.prefix(index).reversed() where !removedSources.contains(message.metadata.id) && !summarized.contains(message.metadata.id) {
            guard message.role == .user || (message.role == .assistant && message.delivery == .completed) else { continue }
            let content = WorkspaceGroupMessageContext.content(message, projection: projection)
            guard content.count <= remaining else { break }
            remaining -= content.count
            previous.append(.init(role: message.role == .user ? "user" : "assistant", content: content))
        }
        result.append(contentsOf: previous.reversed())
        result.append(.init(role: "user", content: source.content))
        return result
    }
}
