import BlotDomain
import Foundation

public struct WorkspaceAgentDraft: Codable, Equatable, Sendable {
    public var name: String
    public var instructions: String
    public var avatarShape: String
    public var avatarColor: String
    public var modelID: String
    public var toolIDs: [String]
    public var accessMode: BlotV3.AccessMode

    public init(name: String, instructions: String, avatarShape: String = "round", avatarColor: String = "orange",
                modelID: String = "compatible", toolIDs: [String] = [], accessMode: BlotV3.AccessMode = .ask_first) {
        self.name = name; self.instructions = instructions; self.avatarShape = avatarShape; self.avatarColor = avatarColor
        self.modelID = modelID; self.toolIDs = toolIDs; self.accessMode = accessMode
    }

    func validate() throws {
        guard [name, instructions, avatarShape, avatarColor, modelID].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              name.utf8.count <= 800, instructions.utf8.count <= 32 * 1024,
              avatarShape.utf8.count <= 100, avatarColor.utf8.count <= 100, modelID.utf8.count <= 200,
              toolIDs.count <= 100, toolIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 200 }),
              Set(toolIDs).count == toolIDs.count else { throw WorkspaceStorageError.invalidParameters }
    }
}

public struct WorkspaceAgentService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    @discardableResult
    public func save(commandID: UUID, agentID: UUID? = nil, expectedVersion: Int = 0,
                     draft: WorkspaceAgentDraft, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let agentID: UUID?; let expectedVersion: Int; let draft: WorkspaceAgentDraft }
        let command = try WorkspaceCommand(type: "agent.save", workspaceID: identity.workspaceID,
            payload: Input(agentID: agentID, expectedVersion: expectedVersion, draft: draft)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            try draft.validate()
            let id = agentID ?? commandID
            try tx.requireResolved(kind: "AgentProfile", id: id)
            let old = try agentID.map { try tx.require(BlotV3.AgentProfile.self, id: $0, version: expectedVersion) }
            if old == nil && expectedVersion != 0 { throw WorkspaceStorageError.versionConflict }
            let metadata = try tx.metadata(id: id, now: now, replacing: old?.metadata)
            let revisionID = WorkspaceLogicalID.make(kind: "AgentConfigurationRevision", workspaceID: tx.identity.workspaceID,
                parts: [id.uuidString, commandID.uuidString])
            let profile = try BlotV3.AgentProfile(metadata: metadata, name: draft.name, roleId: old?.roleId ?? "custom",
                avatarShape: draft.avatarShape, avatarColor: draft.avatarColor, instructions: draft.instructions,
                modelId: draft.modelID, accessMode: draft.accessMode, configurationId: revisionID)
            let revision = try BlotV3.AgentConfigurationRevision(metadata: tx.metadata(id: revisionID, now: now), agentId: id,
                revision: metadata.version, instructions: draft.instructions, toolIds: draft.toolIDs, modelId: draft.modelID)
            try tx.put(profile, expectedVersion: expectedVersion)
            try tx.put(revision, expectedVersion: 0)
            return id
        }
    }
}
