import BlotWorkspace
import Foundation

/// Narrows a delegated task to the Apple apps named in its own brief.
public struct AppleTaskToolScope: Sendable {
    public init() {}
    public func toolIDs(task: String, assigned: Set<String>) -> Set<String> {
        let plugins = plugins(in: task)
        guard !plugins.isEmpty else { return assigned }
        let appleIDs = Set(AppleToolCatalog.all.filter { plugins.contains($0.plugin) }.map { $0.definition.name })
        return assigned.filter { !$0.hasPrefix("apple_") || appleIDs.contains($0) }
    }
    /// Concrete app operations must have matching results before their plan row can be checked.
    public func requiredTools(task: String, discoveryOnly: Bool) -> Set<String> {
        let text = brief(task)
        func matches(_ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        let operation: String
        if discoveryOnly { operation = "resources" }
        else {
            let operations = [
                "create": #"\b(?:create|make|add)\b|созда\p{L}*|добав\p{L}*|подготов\p{L}*[^.]*черновик"#,
                "read": #"\bread\b|прочита\p{L}*|прочти"#,
                "list": #"\b(?:find|search|list)\b|найди|поиск|список"#,
                "update": #"\b(?:update|edit)\b|измени|обнови"#,
                "delete": #"\bdelete\b|удали"#,
                "run": #"\brun\b|запусти"#
            ].filter { matches($0.value) }.map(\.key)
            if operations.count == 1, let value = operations.first { operation = value }
            else if operations.isEmpty, matches(#"ресурс|\bresources?\b|доступ|\baccess\b"#) { operation = "resources" }
            else { return [] }
        }
        return Set(plugins(in: task).compactMap { plugin in
            // A generic workspace document may use document_create instead of Finder.
            if plugin == .files, operation != "resources", !matches(#"\bfinder\b|подключ\p{L}*\s+папк"#) { return nil }
            let action = plugin == .files && operation == "list" ? "search" : operation
            return "apple_" + plugin.rawValue.dropFirst(6) + "_" + action
        })
    }
    private func brief(_ task: String) -> String {
        task.components(separatedBy: ". ").filter { sentence in
            let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return !["не ", "ничего ", "каждый ", "ответ"].contains { text.hasPrefix($0) }
        }.joined(separator: ". ")
    }
    private func plugins(in task: String) -> Set<ApplePluginID> {
        let brief = brief(task)
        let patterns: [ApplePluginID: String] = [
            .calendar: #"\bcalendar\b|календар\p{L}*|событи\p{L}*|встреч\p{L}*"#,
            .reminders: #"\breminders?\b|напоминан\p{L}*"#,
            .mail: #"(?-i:\b(?:Email|Mail)\b)|почт\p{L}*|письм\p{L}*|черновик\p{L}*"#,
            .notes: #"\bnotes\b|заметк\p{L}*"#,
            .contacts: #"\bcontacts?\b|контакт\p{L}*"#,
            .files: #"\bfinder\b|\bfiles?\b|файл\p{L}*"#,
            .shortcuts: #"\bshortcuts\b|команд\p{L}*"#
        ]
        return Set(patterns.compactMap { plugin, pattern in
            brief.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil ? plugin : nil
        })
    }
}
