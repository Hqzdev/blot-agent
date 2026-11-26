import Foundation

public enum WorkspaceMarkdownBlock: Equatable, Sendable {
    case text(String)
    case heading(level: Int, text: String)
    case code(language: String, text: String)
    case table(headers: [String], rows: [[String]])
}

/// A bounded block tokenizer; inline formatting and links remain the native text renderer's job.
public struct WorkspaceMarkdownBlocks: Sendable {
    public init() {}
    public func parse(_ text: String) -> [WorkspaceMarkdownBlock] {
        guard text.utf8.count <= 262_144 else { return [.text(text)] }
        let lines = text.components(separatedBy: "\n")
        var result: [WorkspaceMarkdownBlock] = [], paragraph: [String] = []
        var index = 0
        func flush() { if !paragraph.isEmpty { result.append(.text(paragraph.joined(separator: "\n"))); paragraph.removeAll() } }
        while index < lines.count {
            let line = lines[index], trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence(trimmed) {
                flush(); var code: [String] = []; index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.count >= marker.count, candidate.allSatisfy({ $0 == marker.character }) { index += 1; break }
                    code.append(lines[index]); index += 1
                }
                result.append(.code(language: String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces), text: code.joined(separator: "\n")))
                continue
            }
            if index + 1 < lines.count, let headers = row(line), let separator = row(lines[index + 1]),
               headers.count == separator.count, separator.allSatisfy(isSeparator) {
                flush(); index += 2; var rows: [[String]] = []
                while index < lines.count, let cells = row(lines[index]), cells.count == headers.count {
                    rows.append(cells); index += 1
                }
                result.append(.table(headers: headers, rows: rows)); continue
            }
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if (1...6).contains(level), trimmed.dropFirst(level).first == " " {
                flush(); result.append(.heading(level: level, text: String(trimmed.dropFirst(level + 1)))); index += 1; continue
            }
            if trimmed.isEmpty { flush() } else { paragraph.append(line) }
            index += 1
        }
        flush()
        return result
    }
    private func fence(_ line: String) -> (character: Character, count: Int)? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let count = line.prefix(while: { $0 == first }).count
        return count >= 3 ? (first, count) : nil
    }
    private func isSeparator(_ cell: String) -> Bool {
        let value = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }
    private func row(_ line: String) -> [String]? {
        var cells: [String] = [], cell = "", escaped = false, code = false, separators = 0
        for character in line {
            if escaped { cell.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; cell.append(character); continue }
            if character == "`" { code.toggle() }
            if character == "|", !code { cells.append(cell.trimmingCharacters(in: .whitespaces)); cell = ""; separators += 1 }
            else { cell.append(character) }
        }
        guard separators > 0 else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|") { cells.removeFirst() }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|") { cells.removeLast() }
        return cells.isEmpty || cells.count > 24 ? nil : cells
    }
}
