import BlotWorkspace
import Foundation

public struct AppleTool: Sendable {
    public let plugin: ApplePluginID
    public let operation: String
    public let definition: ChatToolDefinition
    public var needsConfirmation: Bool { ["delete", "send", "move", "run"].contains(operation) }
    public var writes: Bool { !["list", "read", "search", "resources"].contains(operation) }
}

public enum AppleToolCatalog {
    public static let all: [AppleTool] = {
        var tools: [AppleTool] = []
        func add(_ plugin: ApplePluginID, _ operation: String, _ description: String, _ fields: [String], required: [String]) {
            var properties: [String: ChatJSON] = [:]
            for field in fields { properties[field] = .object(["type": .string("string")]) }
            tools.append(.init(plugin: plugin, operation: operation, definition: .init(
                name: "apple_" + plugin.rawValue.dropFirst(6) + "_" + operation,
                description: "App: @\(plugin.name). " + description + ([ApplePluginID.calendar, .reminders].contains(plugin) ? " Dates: ISO 8601 with timezone." : ""),
                parameters: .object(["type": .string("object"), "properties": .object(properties),
                    "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))))
        }
        for plugin in ApplePluginID.allCases where plugin.available { add(plugin, "resources", "Discover selected resource IDs and enable this app's operation tools for the next turn. For an access check, this is sufficient: report the result without listing or reading content.", [], required: []) }
        add(.calendar, "list", "Find events in an authorized calendar (at most 366 days).", ["resource_id", "start", "end", "query"], required: ["resource_id", "start", "end"])
        add(.calendar, "create", "Create a calendar event.", ["resource_id", "title", "start", "end", "notes", "location"], required: ["resource_id", "title", "start", "end"])
        add(.calendar, "update", "Edit one event occurrence; unspecified fields stay unchanged.", ["resource_id", "id", "occurrence_start", "title", "start", "end", "notes", "location"], required: ["resource_id", "id"])
        add(.calendar, "delete", "Delete one event occurrence after user confirmation. Supply occurrence_start from list results for recurring events.", ["resource_id", "id", "occurrence_start"], required: ["resource_id", "id"])
        add(.reminders, "list", "Find reminders in an authorized list.", ["resource_id", "query"], required: ["resource_id"])
        add(.reminders, "create", "Create a reminder.", ["resource_id", "title", "notes", "due"], required: ["resource_id", "title"])
        add(.reminders, "update", "Edit or complete a reminder. completed is true or false.", ["resource_id", "id", "title", "notes", "due", "completed"], required: ["resource_id", "id"])
        add(.reminders, "delete", "Delete a reminder after user confirmation.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.contacts, "list", "Find accessible contacts by name, email or phone.", ["resource_id", "query"], required: ["resource_id"])
        add(.contacts, "create", "Create a contact in the default contact container.", ["resource_id", "given_name", "family_name", "email", "phone"], required: ["resource_id", "given_name"])
        add(.contacts, "update", "Edit an accessible contact.", ["resource_id", "id", "given_name", "family_name", "email", "phone"], required: ["resource_id", "id"])
        add(.contacts, "delete", "Delete an accessible contact after user confirmation.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.files, "list", "List files in a selected folder. path is relative to its root.", ["resource_id", "path"], required: ["resource_id"])
        add(.files, "search", "Search file names recursively inside an authorized folder. Reports truncation after 100 matches or 10000 inspected entries.", ["resource_id", "query", "path"], required: ["resource_id", "query"])
        add(.files, "read", "Read a UTF-8 text file, at most 48 KiB.", ["resource_id", "path"], required: ["resource_id", "path"])
        add(.files, "create", "Create a new UTF-8 file without overwriting an existing file.", ["resource_id", "path", "content"], required: ["resource_id", "path", "content"])
        add(.files, "update", "Replace a UTF-8 file's contents.", ["resource_id", "path", "content"], required: ["resource_id", "path", "content"])
        add(.files, "move", "Move a file within a selected folder after confirmation. destination is relative.", ["resource_id", "path", "destination"], required: ["resource_id", "path", "destination"])
        add(.files, "delete", "Delete a file or empty directory after user confirmation.", ["resource_id", "path"], required: ["resource_id", "path"])
        add(.shortcuts, "run", "Run one explicitly selected shortcut after confirmation. May open Shortcuts.", ["resource_id", "input"], required: ["resource_id"])
        #if os(macOS)
        add(.mail, "list", "Find mail by subject or sender. Returns a page of metadata, has_more and next_offset. limit defaults to 20 (max 50); offset defaults to 0. Not needed for access checks.", ["resource_id", "query", "limit", "offset"], required: ["resource_id"])
        add(.mail, "read", "Read a message in the authorized account.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.mail, "create", "Prepare a mail draft. recipient is one email address.", ["resource_id", "recipient", "subject", "body"], required: ["resource_id", "recipient", "subject", "body"])
        add(.mail, "reply", "Prepare a reply draft; does not send it.", ["resource_id", "id", "body"], required: ["resource_id", "id", "body"])
        add(.mail, "send", "Send a prepared mail draft after user confirmation.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.mail, "move", "Move a message to a named mailbox in the same account after confirmation.", ["resource_id", "id", "destination"], required: ["resource_id", "id", "destination"])
        add(.mail, "delete", "Move a message to trash after user confirmation.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.notes, "list", "Find unlocked notes in an authorized folder. Returns a page of metadata, has_more and next_offset. limit defaults to 20 (max 50); offset defaults to 0. Not needed for access checks.", ["resource_id", "query", "limit", "offset"], required: ["resource_id"])
        add(.notes, "read", "Read an unlocked note's text.", ["resource_id", "id"], required: ["resource_id", "id"])
        add(.notes, "create", "Create a plain text note.", ["resource_id", "title", "body"], required: ["resource_id", "title", "body"])
        add(.notes, "update", "Replace an unlocked note with plain text. Existing formatting will be replaced.", ["resource_id", "id", "title", "body"], required: ["resource_id", "id", "title", "body"])
        add(.notes, "delete", "Delete an unlocked note after confirmation.", ["resource_id", "id"], required: ["resource_id", "id"])
        #else
        add(.mail, "create", "Open a system mail editor. The user sends the message; no inbox access.", ["resource_id", "recipient", "subject", "body"], required: ["resource_id", "recipient", "subject", "body"])
        #endif
        return tools
    }()
    public static func tools(for plugin: ApplePluginID) -> [AppleTool] { all.filter { $0.plugin == plugin } }
}

struct AppleArguments {
    let fields: [String: ChatJSON]
    init(_ json: ChatJSON) throws {
        guard case .object(let fields) = json else { throw AppleIntegrationError.invalidArguments }
        self.fields = fields
    }
    subscript(_ key: String) -> String? { if case .string(let value) = fields[key] { value } else { nil } }
    func required(_ key: String) throws -> String {
        guard let value = self[key], !value.isEmpty else { throw AppleIntegrationError.invalidArguments }
        return value
    }
    func date(_ key: String) throws -> Date {
        let value = try required(key), formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else { throw AppleIntegrationError.invalidArguments }
        return date
    }
}

func appleObject(_ fields: [String: String]) -> ChatJSON { .object(fields.mapValues(ChatJSON.string)) }
