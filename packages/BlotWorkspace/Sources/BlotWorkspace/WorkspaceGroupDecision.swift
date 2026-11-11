import Foundation

public struct WorkspaceGroupDecision: Decodable, Sendable {
    public enum Mode: String, Decodable, Sendable { case conversation, specialist, team }
    public typealias Assignment = WorkspaceGroupPlan.Assignment
    public let mode: Mode
    public let agentID: UUID?
    public let firstToolID: String?
    public let toolSteps: [WorkspaceToolOperation]
    public let summary: String?
    public let assignments: [Assignment]?

    private init(mode: Mode, agentID: UUID?, summary: String?, assignments: [Assignment]?, firstToolID: String? = nil, toolSteps: [WorkspaceToolOperation] = []) {
        self.mode = mode; self.agentID = agentID; self.summary = summary; self.assignments = assignments; self.firstToolID = firstToolID; self.toolSteps = toolSteps
    }

    private enum CodingKeys: String, CodingKey { case mode, agentID, summary, assignments, firstToolID, toolSteps }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let rawAgent = try fields.decodeIfPresent(String.self, forKey: .agentID)
        let agent = rawAgent.flatMap(UUID.init(uuidString:))
        guard rawAgent == nil || rawAgent == "none" || agent != nil else { throw ChatModelError.invalidStream }
        self.init(mode: try fields.decode(Mode.self, forKey: .mode), agentID: agent,
            summary: try fields.decodeIfPresent(String.self, forKey: .summary),
            assignments: try fields.decodeIfPresent([Assignment].self, forKey: .assignments),
            firstToolID: try fields.decodeIfPresent(String.self, forKey: .firstToolID),
            toolSteps: try fields.decodeIfPresent([WorkspaceToolOperation].self, forKey: .toolSteps) ?? [])
    }

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
        let decoded = try JSONDecoder().decode(Self.self, from: Data(text[first...last].utf8))
        let value = Self(mode: decoded.mode, agentID: decoded.agentID, summary: decoded.summary, assignments: decoded.assignments, firstToolID: decoded.toolSteps.first?.toolID ?? (decoded.firstToolID == "none" ? nil : decoded.firstToolID), toolSteps: decoded.toolSteps)
        guard value.toolSteps.count <= 12, value.toolSteps.isEmpty || value.mode != .team,
              value.toolSteps.allSatisfy({ !$0.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.instruction.count <= 4000
                  && $0.toolID.range(of: "^[A-Za-z_][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil }) else { throw ChatModelError.invalidStream }
        if let tool = value.firstToolID {
            guard tool.range(of: "^[A-Za-z_][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil, value.mode != .team else { throw ChatModelError.invalidStream }
        }
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
    public static func routingDefinition(toolIDs: Set<String>, memberIDs: Set<UUID>) -> ChatToolDefinition {
        let string: ChatJSON = .object(["type": .string("string")])
        return .init(name: "select_group_route", description: "Choose the response owner and actual first tool. For a requested check or action choose an assigned tool ID. Use none for text-only conversation, missing required inputs or a team plan.", parameters: .object([
            "type": .string("object"), "properties": .object([
                "mode": .object(["type": .string("string"), "enum": .array(["conversation", "specialist", "team"].map(ChatJSON.string))]),
                "agentID": .object(["type": .string("string"), "enum": .array((["none"] + memberIDs.map(\.uuidString).sorted()).map(ChatJSON.string))]), "summary": .object(["type": .string("string"), "description": .string("For a single agent, resolve references in the latest request: needed filenames, IDs, source content and restrictions. Do not repeat earlier tasks or unverified success claims. For a team, give a short plan.")]),
                "firstToolID": .object(["type": .string("string"), "enum": .array((["none"] + toolIDs.sorted()).map(ChatJSON.string))]),
                "toolSteps": .object(["type": .string("array"), "maxItems": .number(toolIDs.isEmpty ? 0 : 12),
                    "description": .string("For one agent, list only the ordered operations actually required by the latest request. One step per requested file/action/check; include exact targets and source data. Later steps may use preceding tool results. Empty for text-only requests, missing required input or a team plan."),
                    "items": .object(["type": .string("object"), "properties": .object([
                        "toolID": toolIDs.isEmpty ? string : .object(["type": .string("string"), "enum": .array(toolIDs.sorted().map(ChatJSON.string))]),
                        "instruction": string
                    ]), "required": .array(["toolID", "instruction"].map(ChatJSON.string))])]),
                "assignments": .object(["type": .string("array"), "items": .object(["type": .string("object"), "properties": .object([
                    "agentID": string, "task": string, "dependsOn": .object(["type": .string("array"), "items": string])
                ]), "required": .array(["agentID", "task"].map(ChatJSON.string))])])
            ]), "required": .array(["mode", "agentID", "firstToolID", "summary", "toolSteps"].map(ChatJSON.string))
        ]))
    }

    /// Only whole conversational messages use this fast path; a greeting followed by work still needs routing.
    public static func isCasual(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        return ["привет", "всем привет", "привет всем", "здравствуйте", "добрый день", "доброе утро", "добрый вечер", "как дела", "как у вас дела", "как ваши дела", "привет как дела", "всем привет как дела", "спасибо", "спасибо всем", "hello", "hi", "hey", "hi everyone", "how are you", "hello how are you", "thanks", "thank you"].contains(words)
    }
}
