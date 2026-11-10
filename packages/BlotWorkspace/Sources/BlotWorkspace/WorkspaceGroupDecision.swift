import Foundation

public struct WorkspaceGroupDecision: Decodable, Sendable {
    public enum Mode: String, Decodable, Sendable { case conversation, specialist, team }
    public typealias Assignment = WorkspaceGroupPlan.Assignment
    public let mode: Mode
    public let agentID: UUID?
    public let summary: String?
    public let assignments: [Assignment]?

    public static func specialist(_ id: UUID) -> Self { .init(mode: .specialist, agentID: id, summary: nil, assignments: nil) }
    public static var conversation: Self { .init(mode: .conversation, agentID: nil, summary: nil, assignments: nil) }
    /// Explicit `Name — task` clauses belong to the named members, not to a model's role guess.
    public static func addressedTasks(_ text: String, members: [UUID: String]) -> Self? {
        let input = text as NSString
        var clauses: [(id: UUID, range: NSRange)] = []
        for (id, name) in members {
            let pattern = #"(?<![\p{L}\p{N}_])@?"# + NSRegularExpression.escapedPattern(for: name)
                + #"\s*(?:—|–|:|-(?=\s))\s*"#
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            clauses += expression.matches(in: text, range: NSRange(location: 0, length: input.length)).map { (id, $0.range) }
        }
        clauses.sort { $0.range.location < $1.range.location }
        guard clauses.count >= 2, Set(clauses.map(\.id)).count == clauses.count else { return nil }
        let assignments = clauses.enumerated().map { index, clause in
            let start = NSMaxRange(clause.range)
            let end = index + 1 < clauses.count ? clauses[index + 1].range.location : input.length
            let task = input.substring(with: NSRange(location: start, length: end - start)).trimmingCharacters(in: .whitespacesAndNewlines)
            let needsInput = task.range(of: #"(?:после|результат|на основе|using|after|depends|based on)"#, options: [.regularExpression, .caseInsensitive]) != nil
            let dependencies = needsInput ? members.filter { other, name in
                other != clause.id && task.range(of: #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: name) + #"(?![\p{L}\p{N}_])"#, options: [.regularExpression, .caseInsensitive]) != nil
            }.keys.sorted { $0.uuidString < $1.uuidString } : []
            return Assignment(agentID: clause.id, task: task, dependsOn: dependencies)
        }
        guard assignments.allSatisfy({ !$0.task.isEmpty && $0.task.count <= 8_000 }) else { return nil }
        let ids = Set(assignments.map(\.agentID))
        guard assignments.allSatisfy({ Set($0.dependsOn).isSubset(of: ids) }) else { return nil }
        var ready: Set<UUID> = []
        while ready.count < ids.count {
            let next = Set(assignments.filter { Set($0.dependsOn).isSubset(of: ready) }.map(\.agentID)).subtracting(ready)
            guard !next.isEmpty else { return nil }; ready.formUnion(next)
        }
        return .init(mode: .team, agentID: nil, summary: "", assignments: assignments)
    }
    public static func decode(_ text: String, members: Set<UUID>) throws -> Self {
        guard let first = text.firstIndex(of: "{"), let last = text.lastIndex(of: "}"), first <= last else { throw ChatModelError.invalidStream }
        let value = try JSONDecoder().decode(Self.self, from: Data(text[first...last].utf8))
        switch value.mode {
        case .conversation:
            guard value.agentID == nil, value.assignments?.isEmpty != false else { throw ChatModelError.invalidStream }
        case .specialist:
            guard let id = value.agentID, members.contains(id), value.assignments?.isEmpty != false else { throw ChatModelError.invalidStream }
        case .team:
            guard members.count >= 2, let assignments = value.assignments, assignments.count >= 2 else { throw ChatModelError.invalidStream }
            _ = try WorkspaceGroupPlan.decode(text, memberIDs: members)
        }
        return value
    }
    /// Only whole conversational messages use this fast path; a greeting followed by work still needs routing.
    public static func isCasual(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        return ["привет", "всем привет", "привет всем", "здравствуйте", "добрый день", "доброе утро", "добрый вечер", "как дела", "как у вас дела", "как ваши дела", "привет как дела", "всем привет как дела", "спасибо", "спасибо всем", "hello", "hi", "hey", "hi everyone", "how are you", "hello how are you", "thanks", "thank you"].contains(words)
    }
}
