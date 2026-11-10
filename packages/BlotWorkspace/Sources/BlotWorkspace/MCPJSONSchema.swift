import Foundation

/// Common JSON Schema assertions, including local references and unions. The MCP server also validates its inputs.
enum MCPJSONSchema {
    static func validate(_ value: ChatJSON, schema: ChatJSON) throws {
        var budget = 10_000
        try check(value, schema: schema, root: schema, depth: 0, budget: &budget)
    }
    private static func check(_ value: ChatJSON, schema: ChatJSON, root: ChatJSON, depth: Int, budget: inout Int) throws {
        budget -= 1
        guard depth <= 32, budget >= 0 else { throw WorkspaceToolError.invalidArguments }
        if case .bool(let allowed) = schema { guard allowed else { throw WorkspaceToolError.invalidArguments }; return }
        guard case .object(let spec) = schema else { throw WorkspaceToolError.invalidArguments }
        func nested(_ value: ChatJSON, _ schema: ChatJSON) throws { try check(value, schema: schema, root: root, depth: depth + 1, budget: &budget) }
        if let ref = spec["$ref"]?.mcpString {
            guard ref.hasPrefix("#/") else { throw WorkspaceToolError.invalidArguments }
            var target = root
            for raw in ref.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
                let key = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                guard let next = target.mcpFields[key] else { throw WorkspaceToolError.invalidArguments }; target = next
            }
            try nested(value, target)
        }
        if let constant = spec["const"], value != constant { throw WorkspaceToolError.invalidArguments }
        if case .array(let options) = spec["enum"], !options.contains(value) { throw WorkspaceToolError.invalidArguments }
        for mode in ["allOf", "anyOf", "oneOf"] {
            if case .array(let schemas) = spec[mode] {
                let matches = schemas.filter { (try? nested(value, $0)) != nil }.count
                guard mode == "allOf" ? matches == schemas.count : mode == "oneOf" ? matches == 1 : matches > 0 else { throw WorkspaceToolError.invalidArguments }
            }
        }
        if let forbidden = spec["not"], (try? nested(value, forbidden)) != nil { throw WorkspaceToolError.invalidArguments }
        if let condition = spec["if"] {
            if let branch = spec[(try? nested(value, condition)) != nil ? "then" : "else"] { try nested(value, branch) }
        }
        if let type = spec["type"] {
            let types: [String]
            if case .array(let values) = type { types = values.compactMap(\.mcpString) }
            else { types = type.mcpString.map { [$0] } ?? [] }
            guard types.contains(where: { matches(value, type: $0) }) else { throw WorkspaceToolError.invalidArguments }
        }
        func bound(_ key: String, _ number: Double, minimum: Bool) throws {
            if case .number(let limit) = spec[key], minimum ? number < limit : number > limit { throw WorkspaceToolError.invalidArguments }
        }
        switch value {
        case .object(let fields):
            let properties = spec["properties"]?.mcpFields ?? [:], patterns = spec["patternProperties"]?.mcpFields ?? [:]
            if case .array(let required) = spec["required"] {
                guard required.allSatisfy({ $0.mcpString.map { fields[$0] != nil } == true }) else { throw WorkspaceToolError.invalidArguments }
            }
            try bound("minProperties", Double(fields.count), minimum: true); try bound("maxProperties", Double(fields.count), minimum: false)
            for (name, field) in fields {
                var known = false
                if let property = properties[name] { try nested(field, property); known = true }
                for (pattern, schema) in patterns {
                    if try matching(name, pattern: pattern) { try nested(field, schema); known = true }
                }
                if !known, let additional = spec["additionalProperties"] { try nested(field, additional) }
            }
        case .array(let items):
            guard items.count <= 1000 else { throw WorkspaceToolError.invalidArguments }
            try bound("minItems", Double(items.count), minimum: true); try bound("maxItems", Double(items.count), minimum: false)
            if spec["uniqueItems"] == .bool(true) {
                for i in items.indices where items[..<i].contains(items[i]) { throw WorkspaceToolError.invalidArguments }
            }
            var prefix = 0
            if case .array(let schemas) = spec["prefixItems"] {
                prefix = schemas.count
                for (item, schema) in zip(items, schemas) { try nested(item, schema) }
            }
            if let schema = spec["items"] { for item in items.dropFirst(prefix) { try nested(item, schema) } }
        case .string(let text):
            guard text.utf8.count <= 48 * 1024 else { throw WorkspaceToolError.invalidArguments }
            try bound("minLength", Double(text.unicodeScalars.count), minimum: true); try bound("maxLength", Double(text.unicodeScalars.count), minimum: false)
            if let pattern = spec["pattern"]?.mcpString {
                guard try matching(text, pattern: pattern) else { throw WorkspaceToolError.invalidArguments }
            }
        case .number(let number):
            guard number.isFinite else { throw WorkspaceToolError.invalidArguments }
            try bound("minimum", number, minimum: true); try bound("maximum", number, minimum: false)
            if case .number(let limit) = spec["exclusiveMinimum"], number <= limit { throw WorkspaceToolError.invalidArguments }
            if case .number(let limit) = spec["exclusiveMaximum"], number >= limit { throw WorkspaceToolError.invalidArguments }
        default: break
        }
    }
    private static func matching(_ text: String, pattern: String) throws -> Bool {
        guard pattern.utf8.count <= 2048, let regex = try? NSRegularExpression(pattern: pattern) else { throw WorkspaceToolError.invalidArguments }
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(50))
        var matched = false, expired = false
        regex.enumerateMatches(in: text, options: [.reportProgress], range: NSRange(text.startIndex..., in: text)) { result, _, stop in
            if ContinuousClock.now > deadline { expired = true; stop.pointee = true }
            else if result != nil { matched = true; stop.pointee = true }
        }
        guard !expired else { throw WorkspaceToolError.invalidArguments }
        return matched
    }
    private static func matches(_ value: ChatJSON, type: String) -> Bool {
        switch (type, value) {
        case ("object", .object), ("array", .array), ("string", .string), ("number", .number), ("boolean", .bool), ("null", .null): true
        case ("integer", .number(let number)): number.isFinite && number.rounded() == number
        default: false
        }
    }
}
