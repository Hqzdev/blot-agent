import BlotDomain
import Foundation

/// Selecting a version is an explicit command; a newly arrived version invalidates the displayed choice.
public struct WorkspaceConflictService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func resolve(commandID: UUID, selectedRevisionID: UUID, displayedRevisionIDs: Set<UUID>, now: Date = Date()) async throws {
        struct Input: Encodable { let selectedRevisionID: UUID; let displayedRevisionIDs: [UUID] }
        let command = try WorkspaceCommand(type: "conflict.resolve", workspaceID: identity.workspaceID,
            payload: Input(selectedRevisionID: selectedRevisionID, displayedRevisionIDs: displayedRevisionIDs.sorted { $0.uuidString < $1.uuidString })).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let selected = try tx.require(BlotV3.ConflictingRevision.self, id: selectedRevisionID)
            let revisions = try tx.records(BlotV3.ConflictingRevision.self).filter {
                !$0.resolved && $0.recordKind == selected.recordKind && $0.recordId == selected.recordId
            }
            guard !selected.resolved, Set(revisions.map(\.metadata.id)) == displayedRevisionIDs,
                  displayedRevisionIDs.contains(selectedRevisionID) else { throw WorkspaceStorageError.versionConflict }
            switch selected.recordKind {
            case "AgentProfile":
                let current = try tx.require(BlotV3.AgentProfile.self, id: selected.recordId)
                let chosen = try Self.rebase(BlotV3.AgentProfile.self, selected: selected, current: current, tx: tx, now: now)
                if let configurationID = chosen.configurationId {
                    let configuration = try tx.require(BlotV3.AgentConfigurationRevision.self, id: configurationID)
                    guard configuration.agentId == current.metadata.id else { throw WorkspaceStorageError.invalidRecord }
                } else { throw WorkspaceStorageError.invalidRecord }
                try tx.put(chosen, expectedVersion: current.metadata.version)
            case "Automation":
                let current = try tx.require(BlotV3.Automation.self, id: selected.recordId)
                let chosen = try Self.rebase(BlotV3.Automation.self, selected: selected, current: current, tx: tx, now: now)
                if let agentID = chosen.agentId { _ = try tx.require(BlotV3.AgentProfile.self, id: agentID) }
                if let skillID = chosen.skillRevisionId { _ = try tx.require(BlotV3.SkillRevision.self, id: skillID) }
                try tx.put(chosen, expectedVersion: current.metadata.version)
            default: throw WorkspaceSyncError.unsupportedRecord
            }
            for revision in revisions {
                let resolved = try BlotV3.ConflictingRevision(metadata: tx.metadata(id: revision.metadata.id, now: now, replacing: revision.metadata),
                    recordKind: revision.recordKind, recordId: revision.recordId, baseVersion: revision.baseVersion,
                    originDeviceId: revision.originDeviceId, payloadJSON: revision.payloadJSON, resolved: true)
                try tx.put(resolved, expectedVersion: revision.metadata.version)
            }
            return selected.recordId
        }
    }

    private static func rebase<T: BlotWorkspaceRecord>(_ type: T.Type, selected: BlotV3.ConflictingRevision, current: T,
        tx: WorkspaceTransaction, now: Date) throws -> T {
        let original = try WorkspaceCoding.decode(type, from: Data(selected.payloadJSON.utf8))
        guard original.metadata.id == current.metadata.id, original.metadata.ownerId == current.metadata.ownerId,
              original.metadata.workspaceId == current.metadata.workspaceId else { throw WorkspaceStorageError.invalidRecord }
        var object = try JSONFields.object(selected.payloadJSON)
        object["metadata"] = try JSONSerialization.jsonObject(with: WorkspaceCoding.encode(tx.metadata(id: current.metadata.id, now: now, replacing: current.metadata)))
        return try WorkspaceCoding.decode(type, from: Data(JSONFields.string(object).utf8))
    }
}
