import BlotDesign
import Foundation

/// Parses the displayed unified diff excerpt without reading or modifying project files.
enum UnifiedDiffParser {
    static func parse(_ patch: String) -> [DiffLine] {
        var old = 0
        var new = 0
        return patch.components(separatedBy: "\n").enumerated().map { index, text in
            if text.hasPrefix("@@") {
                let parts = text.split(separator: " ")
                if parts.count >= 3 {
                    old = Int(parts[1].dropFirst().split(separator: ",").first ?? "0") ?? 0
                    new = Int(parts[2].dropFirst().split(separator: ",").first ?? "0") ?? 0
                }
                return DiffLine(id: index, oldNumber: nil, newNumber: nil, text: text, tone: .header)
            }
            if text.hasPrefix("+") {
                defer { new += 1 }
                return DiffLine(id: index, oldNumber: nil, newNumber: new, text: String(text.dropFirst()), tone: .added)
            }
            if text.hasPrefix("-") {
                defer { old += 1 }
                return DiffLine(id: index, oldNumber: old, newNumber: nil, text: String(text.dropFirst()), tone: .removed)
            }
            defer { old += 1; new += 1 }
            return DiffLine(id: index, oldNumber: old, newNumber: new,
                            text: text.hasPrefix(" ") ? String(text.dropFirst()) : text, tone: .context)
        }
    }
}
