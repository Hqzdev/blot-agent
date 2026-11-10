import BlotDomain
import Foundation

/// A readable checklist stays in the existing message record, including synchronized updates.
public struct WorkspaceGroupPlanProgress: Equatable, Sendable {
    public struct Step: Equatable, Sendable {
        public let agentID: UUID?
        public let name: String
        public let task: String
        public let completed: Bool
        public init(agentID: UUID?, name: String, task: String, completed: Bool = false) {
            self.agentID = agentID; self.name = name; self.task = task; self.completed = completed
        }
    }
    public let summary: String
    public let steps: [Step]
    public var completedCount: Int { steps.filter(\.completed).count }
    public var allCompleted: Bool { !steps.isEmpty && completedCount == steps.count }
    public init(summary: String, steps: [Step]) { self.summary = summary; self.steps = steps }
    public var markdown: String {
        let description = summary.isEmpty ? "" : "\n\n> " + Self.line(summary)
        return "## Work plan" + description + "\n\n" + steps.map {
            "- [\($0.completed ? "x" : " ")] @\(Self.line($0.name)) — \(Self.line($0.task))"
        }.joined(separator: "\n")
    }
    public func updating(agentID: UUID, completed: Bool) -> Self {
        Self(summary: summary, steps: steps.map {
            $0.agentID == agentID ? Step(agentID: $0.agentID, name: $0.name, task: $0.task, completed: completed) : $0
        })
    }
    public static func decode(_ text: String, agents: [BlotV3.AgentProfile] = []) -> Self? {
        guard text.hasPrefix("## Work plan\n"), let regex = try? NSRegularExpression(pattern: #"^- \[([ x])\] @(.+?) — (.+)$"#) else { return nil }
        var summary: [String] = [], steps: [Step] = []
        for line in text.components(separatedBy: .newlines).dropFirst() where !line.isEmpty {
            if line.hasPrefix("> ") { summary.append(String(line.dropFirst(2))); continue }
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.utf16.count)) else { return nil }
            let value = line as NSString
            let name = value.substring(with: match.range(at: 2)), task = value.substring(with: match.range(at: 3))
            guard !steps.contains(where: { $0.name == name }), steps.count < 12, task.count <= 8_000 else { return nil }
            steps.append(.init(agentID: agents.first { $0.name == name }?.metadata.id, name: name, task: task,
                completed: value.substring(with: match.range(at: 1)) == "x"))
        }
        guard steps.count >= 2 else { return nil }
        return Self(summary: summary.joined(separator: "\n"), steps: steps)
    }
    public static func legacy(_ text: String, agents: [BlotV3.AgentProfile]) -> Self? {
        var summary: [String] = [], steps: [Step] = []
        for line in text.components(separatedBy: .newlines) {
            if let agent = agents.sorted(by: { $0.name.count > $1.name.count }).first(where: { line.hasPrefix("@" + $0.name + " — ") }) {
                guard !steps.contains(where: { $0.agentID == agent.metadata.id }) else { return nil }
                steps.append(.init(agentID: agent.metadata.id, name: agent.name, task: String(line.dropFirst(agent.name.count + 4))))
            } else if steps.isEmpty { summary.append(line) }
            else if !line.isEmpty, let last = steps.popLast() {
                steps.append(.init(agentID: last.agentID, name: last.name, task: last.task + " " + line))
            }
        }
        guard steps.count >= 2 else { return nil }
        return Self(summary: summary.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), steps: steps)
    }
    private static func line(_ text: String) -> String { text.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
}
