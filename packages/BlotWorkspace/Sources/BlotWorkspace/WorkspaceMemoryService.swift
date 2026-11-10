import BlotDomain
import Foundation

public struct WorkspaceMemoryService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func create(commandID: UUID, content: String, sourceID: UUID, agentID: UUID? = nil,
                       candidate: Bool = false, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let content: String; let sourceID: UUID; let agentID: UUID?; let candidate: Bool }
        let command = try WorkspaceCommand(type: "memory.create", workspaceID: identity.workspaceID,
            payload: Input(content: content, sourceID: sourceID, agentID: agentID, candidate: candidate)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidParameters }
            guard try tx.record(BlotV3.Message.self, id: sourceID) != nil || tx.record(BlotV3.Artifact.self, id: sourceID) != nil else {
                throw WorkspaceStorageError.missingRecord
            }
            if let agentID { _ = try tx.require(BlotV3.AgentProfile.self, id: agentID) }
            let memory = try BlotV3.MemoryEntry(metadata: tx.metadata(id: commandID, now: now), scope: agentID == nil ? .personal : .agent,
                scopeId: agentID, content: content, sourceId: sourceID, state: candidate ? .candidate : .active)
            try tx.put(memory, expectedVersion: 0)
            return commandID
        }
    }

    public func revise(commandID: UUID, memoryID: UUID, expectedVersion: Int, content: String? = nil,
                       accepting: Bool = false, deleting: Bool = false, now: Date = Date()) async throws {
        struct Input: Encodable { let memoryID: UUID; let expectedVersion: Int; let content: String?; let accepting: Bool; let deleting: Bool }
        let command = try WorkspaceCommand(type: "memory.revise", workspaceID: identity.workspaceID,
            payload: Input(memoryID: memoryID, expectedVersion: expectedVersion, content: content, accepting: accepting, deleting: deleting)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.MemoryEntry.self, id: memoryID, version: expectedVersion)
            guard old.state != .deleted else { throw WorkspaceStorageError.deletedRecord }
            if let content, content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw WorkspaceStorageError.invalidParameters }
            let memory = try BlotV3.MemoryEntry(metadata: tx.metadata(id: memoryID, now: now, replacing: old.metadata),
                scope: old.scope, scopeId: old.scopeId, content: deleting ? "" : content ?? old.content, sourceId: old.sourceId,
                state: deleting ? .deleted : accepting ? .active : old.state)
            try tx.put(memory, expectedVersion: expectedVersion)
            // A summary can contain paraphrased facts: conservatively invalidate every summary on edits/deletion.
            if deleting || content != nil {
                for summary in try tx.records(BlotV3.ContextSummary.self) where summary.valid {
                    let updated = try BlotV3.ContextSummary(metadata: tx.metadata(id: summary.metadata.id, now: now, replacing: summary.metadata),
                        conversationId: summary.conversationId, content: summary.content, sourceIds: summary.sourceIds, valid: false)
                    try tx.put(updated, expectedVersion: summary.metadata.version)
                }
            }
            return memoryID
        }
    }

    public func saveSummary(commandID: UUID, conversationID: UUID, content: String, sourceIDs: [UUID], now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let conversationID: UUID; let content: String; let sourceIDs: [UUID] }
        let command = try WorkspaceCommand(type: "context.summary.save", workspaceID: identity.workspaceID,
            payload: Input(conversationID: conversationID, content: content, sourceIDs: sourceIDs)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            _ = try tx.require(BlotV3.Conversation.self, id: conversationID)
            guard !sourceIDs.isEmpty, Set(sourceIDs).count == sourceIDs.count,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidParameters }
            let removedSources = Set(try tx.records(BlotV3.MemoryEntry.self).filter { $0.state == .deleted }.map(\.sourceId))
            let index = WorkspaceDirectConversations(try tx.records(BlotV3.Conversation.self))
            for id in sourceIDs {
                let source = try tx.require(BlotV3.Message.self, id: id)
                guard index.canonicalID(source.conversationId) == index.canonicalID(conversationID), !removedSources.contains(id) else { throw WorkspaceStorageError.permissionDenied }
            }
            let summary = try BlotV3.ContextSummary(metadata: tx.metadata(id: commandID, now: now), conversationId: conversationID,
                content: content, sourceIds: sourceIDs, valid: true)
            try tx.put(summary, expectedVersion: 0)
            return commandID
        }
    }
}
