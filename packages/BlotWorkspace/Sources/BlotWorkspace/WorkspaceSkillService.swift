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
                  name.utf8.count <= 800, instructions.utf8.count <= 32 * 1024, parameters.count <= 32, toolIDs.count <= 100,
                  Set(parameters.map(\.name)).count == parameters.count, Set(toolIDs).count == toolIDs.count,
                  toolIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 200 }), parameters.allSatisfy({ Self.validParameterName($0.name) }) else {
                throw WorkspaceStorageError.invalidParameters
            }
            try Self.validateTemplate(instructions, parameters: parameters)
            let id = skillID ?? commandID
            try tx.requireResolved(kind: "Skill", id: id)
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

    public func setArchived(commandID: UUID, skillID: UUID, expectedVersion: Int, archived: Bool) async throws {
        try await update(commandID: commandID, skillID: skillID, expectedVersion: expectedVersion, revisionID: nil, archived: archived)
    }
    public func activate(commandID: UUID, skillID: UUID, expectedVersion: Int, revisionID: UUID) async throws {
        try await update(commandID: commandID, skillID: skillID, expectedVersion: expectedVersion, revisionID: revisionID, archived: nil)
    }
    private func update(commandID: UUID, skillID: UUID, expectedVersion: Int, revisionID: UUID?, archived: Bool?) async throws {
        struct Input: Encodable { let skillID: UUID; let expectedVersion: Int; let revisionID: UUID?; let archived: Bool? }
        let command = try WorkspaceCommand(type: "skill.update", workspaceID: identity.workspaceID,
            payload: Input(skillID: skillID, expectedVersion: expectedVersion, revisionID: revisionID, archived: archived)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let old = try tx.require(BlotV3.Skill.self, id: skillID, version: expectedVersion)
            try tx.requireResolved(kind: "Skill", id: skillID)
            if let revisionID {
                let revision = try tx.require(BlotV3.SkillRevision.self, id: revisionID)
                guard revision.skillId == skillID else { throw WorkspaceSkillError.revisionUnavailable }
            }
            try tx.put(BlotV3.Skill(metadata: tx.metadata(id: skillID, now: Date(), replacing: old.metadata), name: old.name,
                activeRevisionId: revisionID ?? old.activeRevisionId, archived: archived ?? old.archived), expectedVersion: expectedVersion)
            return skillID
        }
    }

    public static func parameters(_ revision: BlotV3.SkillRevision) throws -> [SkillParameter] {
        try WorkspaceCoding.decode([SkillParameter].self, from: Data(revision.parametersJSON.utf8))
    }

    public func render(revisionID: UUID, values: [String: String]) async throws -> String {
        guard let revision = try await repository.record(BlotV3.SkillRevision.self, id: revisionID, workspaceID: identity.workspaceID) else {
            throw WorkspaceStorageError.missingRecord
        }
        return try Self.render(revision, values: values)
    }

    static func render(_ revision: BlotV3.SkillRevision, values: [String: String]) throws -> String {
        let parameters = try Self.parameters(revision)
        guard parameters.count <= 32, Set(parameters.map(\.name)).count == parameters.count,
              parameters.allSatisfy({ validParameterName($0.name) }) else { throw WorkspaceStorageError.invalidParameters }
        try validateTemplate(revision.instructions, parameters: parameters)
        guard Set(values.keys).isSubset(of: Set(parameters.map(\.name))),
              values.values.allSatisfy({ $0.utf8.count <= 32 * 1024 }),
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
        guard output.utf8.count <= 32 * 1024 else { throw WorkspaceStorageError.invalidParameters }
        return output
    }

    private static func validateTemplate(_ instructions: String, parameters: [SkillParameter]) throws {
        let regex = try NSRegularExpression(pattern: #"\{\{([^{}]*)\}\}"#)
        let source = instructions as NSString
        let matches = regex.matches(in: instructions, range: NSRange(location: 0, length: source.length))
        let names = Set(parameters.map(\.name))
        guard matches.allSatisfy({ names.contains(source.substring(with: $0.range(at: 1))) }) else { throw WorkspaceSkillError.invalidTemplate }
        let residue = regex.stringByReplacingMatches(in: instructions, range: NSRange(location: 0, length: source.length), withTemplate: "")
        guard !residue.contains("{{"), !residue.contains("}}") else { throw WorkspaceSkillError.invalidTemplate }
    }

    private static func validParameterName(_ value: String) -> Bool {
        value.utf8.count <= 64 && value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }
}
