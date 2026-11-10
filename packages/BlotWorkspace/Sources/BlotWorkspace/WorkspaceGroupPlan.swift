import Foundation

/// The coordinator chooses an execution order, never new members or tool permissions.
public struct WorkspaceGroupPlan: Decodable, Sendable {
    public struct Assignment: Decodable, Sendable {
        public let agentID: UUID
        public let task: String
        public let dependsOn: [UUID]
        public init(agentID: UUID, task: String, dependsOn: [UUID] = []) { self.agentID = agentID; self.task = task; self.dependsOn = dependsOn }
        private enum CodingKeys: String, CodingKey { case agentID, task, dependsOn }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(agentID: try c.decode(UUID.self, forKey: .agentID), task: try c.decode(String.self, forKey: .task), dependsOn: try c.decodeIfPresent([UUID].self, forKey: .dependsOn) ?? [])
        }
    }
    public let summary: String
    public let assignments: [Assignment]

    public static func decode(_ text: String, memberIDs: Set<UUID>) throws -> Self {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first <= last else {
            throw ChatModelError.invalidStream
        }
        guard let plan = try? JSONDecoder().decode(Self.self, from: Data(text[first...last].utf8)) else {
            throw ChatModelError.invalidStream
        }
        guard !plan.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.summary.count <= 8_000, !plan.assignments.isEmpty, plan.assignments.count <= min(12, memberIDs.count),
              Set(plan.assignments.map(\.agentID)).count == plan.assignments.count,
              Set(plan.assignments.map(\.agentID)).isSubset(of: memberIDs),
              plan.assignments.allSatisfy({ !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.task.count <= 8_000 }) else {
            throw ChatModelError.invalidStream
        }
        let ids = Set(plan.assignments.map(\.agentID))
        guard plan.assignments.allSatisfy({ Set($0.dependsOn).count == $0.dependsOn.count && !$0.dependsOn.contains($0.agentID) && Set($0.dependsOn).isSubset(of: ids) }) else { throw ChatModelError.invalidStream }
        var resolved: Set<UUID> = []
        while resolved.count < ids.count {
            let next = Set(plan.assignments.filter { Set($0.dependsOn).isSubset(of: resolved) }.map(\.agentID)).subtracting(resolved)
            guard !next.isEmpty else { throw ChatModelError.invalidStream }; resolved.formUnion(next)
        }
        return plan
    }
}
