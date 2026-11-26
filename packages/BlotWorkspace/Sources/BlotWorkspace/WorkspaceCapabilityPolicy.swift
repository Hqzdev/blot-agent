import Foundation

/// Required bootstrap steps for explicit skill/setup requests. The model still
/// chooses arguments; only real tool results satisfy a step.
public struct WorkspaceCapabilityPolicy: Sendable {
    private let text: String
    public init(userRequest: String) { text = userRequest.lowercased() }
    private func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }
    private var informational: Bool { matches(#"^\s*(?:как\b|how\b|объясни\b|расскажи\b)"#) }
    public var createsSkill: Bool {
        !informational && !matches(#"не\s+(?:создавай|сохраняй)|do\s+not\s+(?:create|save)"#)
            && matches(#"(?:создай|сохрани|создайте|сохраните|сделай|\bcreate\b|\bsave\b|\bbuild\b)[^.!?\n]{0,180}(?:навык|скилл|\bskill\b)"#)
    }
    public var createsLocalDocument: Bool {
        guard !informational, WorkspaceToolRestrictions(userRequest: text).allows(operation: "create") else { return false }
        let create = matches(#"(?:создай|создайте|сделай|подготовь|\bcreate\b|\bmake\b|\bgenerate\b)[^.!?\n]{0,180}(?:документ|таблиц|презентац|отч[её]т|document_create|\bpdf\b|\bcsv\b|\bmarkdown\b|\bdocument\b|\bspreadsheet\b|\bpresentation\b|\breport\b)"#)
        let cloud = matches(#"google|гугл|\bdrive\b|облак"#)
        let local = matches(#"локаль|\blocal\b|без\s+(?:google|гугл)|without\s+google|внутри\s+blot"#)
        return create && (!cloud || local)
    }
    public var requestsAction: Bool {
        !informational && matches(#"(?:подключи|подключить|создай|сохрани|найди|прочитай|отправь|добавь|запиши|проверь|проверить|посмотри|покажи|открой|вызови|получи|\bconnect\b|\bcreate\b|\bsave\b|\bfind\b|\bread\b|\bsend\b|\badd\b|\bcheck\b|\bverify\b|\bcall\b|\bget\b)"#)
    }
    public var usesSkill: Bool {
        !informational && !forbidsSkillRun && matches(#"(?:запусти|примени|выполни|используй|\brun\b|\bapply\b|\buse\b)[^.!?\n]{0,140}(?:навык|скилл|\bskill\b)"#)
    }
    public var queriesSkills: Bool {
        !informational && matches(#"(?:какие|покажи|найди|\blist\b|\bshow\b)[^.!?\n]{0,100}(?:навык|скилл|\bskills?\b)"#)
    }
    public var queriesConnections: Bool {
        !informational && matches(#"(?:плагин|приложени|интеграци|подключени|\bplugins?\b|\bintegrations?\b|\bconnections?\b)"#)
            && matches(#"(?:какие|проверь|покажи|список|подключ|\bcheck\b|\blist\b|\bshow\b|\bconnect)"#)
    }
    public var forbidsSkillRun: Bool {
        matches(#"не\s+(?:запускай|выполняй)\s+(?:его|навык|скилл)|do\s+not\s+run|don.t\s+run"#)
            || createsSkill && !matches(#"(?:и|затем)\s+(?:запусти|выполни)|(?:and|then)\s+(?:run|execute)"#)
    }
    public func mentions(id: String, name: String) -> Bool {
        let names = [id, id.components(separatedBy: ".").last ?? id, name].map { $0.lowercased() }
        return names.contains { value in
            let word = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: value) + "(?![\\p{L}\\p{N}_])"
            if text.range(of: word, options: .regularExpression) != nil { return true }
            return value.count >= 5 && value.range(of: #"^[а-яё]+$"#, options: .regularExpression) != nil && text.contains(String(value.dropLast()))
        }
    }
    public func requiredTool(initial: String?, results: [(name: String, value: ChatJSON)]) -> String? {
        guard let initial else { return nil }
        if initial == "document_create" {
            return results.contains { $0.name == initial && Self.fields($0.value)["artifact_id"] != nil } ? nil : initial
        }
        if initial == "google_accounts" {
            return results.contains { $0.name == initial && Self.fields($0.value)["error"] == nil } ? nil : initial
        }
        if initial == "skill_list" {
            if results.contains(where: { $0.name == "skill_create" && Self.fields($0.value)["state"] == .string("saved") }) { return nil }
            guard let listing = results.last(where: { $0.name == "skill_list" }) else { return "skill_list" }
            if !createsSkill {
                guard usesSkill, case .array(let skills) = Self.fields(listing.value)["skills"], skills.contains(where: {
                    if case .string(let name) = Self.fields($0)["name"] { return text.contains(name.lowercased()) }; return false
                }) else { return nil }
                if results.contains(where: { $0.name == "skill_run" }) { return nil }
                return results.contains(where: { $0.name == "skill_read" }) ? "skill_run" : "skill_read"
            }
            if case .array(let skills) = Self.fields(listing.value)["skills"], skills.contains(where: {
                if case .string(let name) = Self.fields($0)["name"] { return text.contains(name.lowercased()) }; return false
            }) {
                return results.contains(where: { $0.name == "skill_read" }) ? nil : "skill_read"
            }
            return "skill_create"
        }
        if initial == "plugin_catalog" {
            guard let listing = results.last(where: { $0.name == "plugin_catalog" }) else { return "plugin_catalog" }
            guard requestsAction, case .array(let plugins) = Self.fields(listing.value)["plugins"] else { return nil }
            let attempted = Set(results.filter { $0.name == "plugin_connect" }.compactMap { item -> String? in
                if case .string(let id) = Self.fields(item.value)["plugin_id"] { return id }; return nil
            })
            let query: String
            if case .string(let value) = Self.fields(listing.value)["query"] { query = value } else { query = "" }
            return plugins.contains(where: { plugin in
                let fields = Self.fields(plugin)
                guard case .string(let id) = fields["plugin_id"], case .string(let name) = fields["name"],
                      fields["can_connect"] == .bool(true), fields["connected_for_agent"] == .bool(false), !attempted.contains(id) else { return false }
                return mentions(id: id, name: name) || !query.isEmpty
            }) ? "plugin_connect" : nil
        }
        return nil
    }
    private static func fields(_ value: ChatJSON) -> [String: ChatJSON] {
        if case .object(let fields) = value { return fields }; return [:]
    }
}
