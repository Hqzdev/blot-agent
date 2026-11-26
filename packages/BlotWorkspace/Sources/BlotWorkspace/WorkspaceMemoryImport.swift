import BlotDomain
import Foundation

/// An import is an explicit, reviewed set of facts, never executable instructions.
public struct WorkspaceMemoryImport: Sendable {
    public static func facts(from text: String) -> [String] {
        var seen: Set<String> = []
        return text.components(separatedBy: .newlines).compactMap { line in
            let fact = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, with: "", options: .regularExpression)
            guard !fact.isEmpty, fact.utf8.count <= 8_192, seen.insert(fact).inserted else { return nil }
            return fact
        }
    }

    public static func save(commandID: UUID, facts: [String], sourceID: UUID,
                            repository: WorkspaceRepository, identity: WorkspaceIdentity) async throws {
        struct Input: Encodable { let facts: [String]; let sourceID: UUID }
        let command = try WorkspaceCommand(type: "memory.import", workspaceID: identity.workspaceID,
            payload: Input(facts: facts, sourceID: sourceID)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard (1...100).contains(facts.count), facts.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf8.count <= 8_192 }),
                  Set(facts).count == facts.count else { throw WorkspaceStorageError.invalidParameters }
            _ = try tx.require(BlotV3.Artifact.self, id: sourceID)
            let now = Date()
            for (index, fact) in facts.enumerated() {
                let id = WorkspaceLogicalID.make(kind: "ImportedMemory", workspaceID: identity.workspaceID,
                    parts: [commandID.uuidString, String(index)])
                let memory = try BlotV3.MemoryEntry(metadata: tx.metadata(id: id, now: now), scope: .personal,
                    content: fact, sourceId: sourceID, state: .active)
                try tx.put(memory, expectedVersion: 0)
            }
            return sourceID
        }
    }
}
