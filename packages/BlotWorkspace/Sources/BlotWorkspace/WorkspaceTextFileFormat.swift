import Foundation

/// Recognizes editable text without evaluating markup, scripts or document macros.
enum WorkspaceTextFileFormat {
    static func accepts(name: String, mediaType: String) -> Bool {
        let type = mediaType.lowercased().components(separatedBy: ";")[0].trimmingCharacters(in: .whitespaces)
        if type.hasPrefix("text/") || type == "application/octet-stream" { return true }
        if ["application/json", "application/ld+json", "application/xml", "application/javascript", "application/yaml", "application/x-yaml", "application/toml", "application/sql"].contains(type) { return true }
        return WorkspaceFileFormat.textExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func decode(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { return nil }
        return text
    }
}
