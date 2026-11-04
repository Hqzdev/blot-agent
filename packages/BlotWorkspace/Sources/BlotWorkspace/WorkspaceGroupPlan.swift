import Foundation

/// The coordinator chooses an execution order, never new members or tool permissions.
public struct WorkspaceGroupPlan: Decodable, Sendable {
    public struct Assignment: Decodable, Sendable {
        public let agentID: UUID
        public let task: String
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
              plan.summary.count <= 8_000, plan.assignments.count == memberIDs.count,
              Set(plan.assignments.map(\.agentID)) == memberIDs,
              plan.assignments.allSatisfy({ !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.task.count <= 8_000 }) else {
            throw ChatModelError.invalidStream
        }
        return plan
    }
}
