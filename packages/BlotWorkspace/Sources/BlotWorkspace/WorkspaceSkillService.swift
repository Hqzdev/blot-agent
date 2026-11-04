import BlotDomain
import Foundation

public struct SkillParameter: Codable, Equatable, Sendable {
    public let name: String
    public let required: Bool
    public init(name: String, required: Bool = true) { self.name = name; self.required = required }
}

public struct WorkspaceSkillService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func save(commandID: UUID, skillID: UUID? = nil, expectedVersion: Int = 0, name: String,
                     instructions: String, parameters: [SkillParameter], toolIDs: [String], now: Date = Date()) async throws -> UUID {
        struct Input: Encodable {
            let skillID: UUID?; let expectedVersion: Int; let name: String; let instructions: String
            let parameters: [SkillParameter]; let toolIDs: [String]
        }
        let command = try WorkspaceCommand(type: "skill.save", workspaceID: identity.workspaceID,
            payload: Input(skillID: skillID, expectedVersion: expectedVersion, name: name, instructions: instructions, parameters: parameters, toolIDs: toolIDs)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(parameters.map(\.name)).count == parameters.count, Set(toolIDs).count == toolIDs.count,
                  toolIDs.allSatisfy({ !$0.isEmpty }), parameters.allSatisfy({ Self.validParameterName($0.name) }) else {
                throw WorkspaceStorageError.invalidParameters
            }
            let id = skillID ?? commandID
            let old = try skillID.map { try tx.require(BlotV3.Skill.self, id: $0, version: expectedVersion) }
            if old == nil && expectedVersion != 0 { throw WorkspaceStorageError.versionConflict }
            let metadata = try tx.metadata(id: id, now: now, replacing: old?.metadata)
            let revisionID = WorkspaceLogicalID.make(kind: "SkillRevision", workspaceID: tx.identity.workspaceID,
                parts: [id.uuidString, commandID.uuidString])
            let revision = try BlotV3.SkillRevision(metadata: tx.metadata(id: revisionID, now: now), skillId: id,
                instructions: instructions, parametersJSON: String(decoding: WorkspaceCoding.encode(parameters), as: UTF8.self), toolIds: toolIDs)
            let skill = try BlotV3.Skill(metadata: metadata, name: name, activeRevisionId: revisionID, archived: old?.archived ?? false)
            try tx.put(revision, expectedVersion: 0)
            try tx.put(skill, expectedVersion: expectedVersion)
            return id
        }
    }

    public func render(revisionID: UUID, values: [String: String]) async throws -> String {
        guard let revision = try await repository.record(BlotV3.SkillRevision.self, id: revisionID, workspaceID: identity.workspaceID) else {
            throw WorkspaceStorageError.missingRecord
        }
        return try Self.render(revision, values: values)
    }

    static func render(_ revision: BlotV3.SkillRevision, values: [String: String]) throws -> String {
        let parameters = try WorkspaceCoding.decode([SkillParameter].self, from: Data(revision.parametersJSON.utf8))
        guard Set(values.keys).isSubset(of: Set(parameters.map(\.name))),
              parameters.allSatisfy({ !$0.required || !(values[$0.name]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) else {
            throw WorkspaceStorageError.invalidParameters
        }
        // Replace tokens in the original text only; supplied values cannot introduce additional substitutions.
        let pattern = #"\{\{([A-Za-z_][A-Za-z0-9_]*)\}\}"#
        let regex = try NSRegularExpression(pattern: pattern)
        var output = revision.instructions
        for match in regex.matches(in: revision.instructions, range: NSRange(revision.instructions.startIndex..., in: revision.instructions)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: revision.instructions), let range = Range(match.range, in: output) else {
                throw WorkspaceStorageError.invalidParameters
            }
            let name = String(revision.instructions[keyRange])
            guard parameters.contains(where: { $0.name == name }) else { throw WorkspaceStorageError.invalidParameters }
            output.replaceSubrange(range, with: values[name] ?? "")
        }
        return output
    }

    private static func validParameterName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}
