import Foundation

/// Bounded RFC4180-style reader shared by local table previews; quoted newlines stay in their cells.
public struct WorkspaceCSV: Sendable {
    public init() {}
    public func rows(_ text: String) throws -> [[String]] {
        guard text.utf8.count <= 2 * 1024 * 1024 else { throw WorkspaceFileError.tooLarge }
        var rows: [[String]] = [], row: [String] = [], value = ""
        var quoted = false, closed = false, index = text.startIndex
        func finishCell() throws {
            guard row.count < 100 else { throw WorkspaceStorageError.invalidParameters }
            row.append(value); value = ""; closed = false
        }
        while index < text.endIndex {
            let character = text[index]; index = text.index(after: index)
            if quoted {
                if character == "\"" {
                    if index < text.endIndex, text[index] == "\"" { value.append("\""); index = text.index(after: index) }
                    else { quoted = false; closed = true }
                } else { value.append(character) }
            } else if character == "\"", value.isEmpty, !closed { quoted = true }
            else if character == "," { try finishCell() }
            else if character == "\n" || character == "\r" || character == "\r\n" {
                try finishCell(); rows.append(row); row = []
                guard rows.count <= 10_001 else { throw WorkspaceStorageError.invalidParameters }
                if character == "\r", index < text.endIndex, text[index] == "\n" { index = text.index(after: index) }
            } else {
                guard !closed, character != "\"" else { throw WorkspaceFileError.invalidText }
                value.append(character)
            }
        }
        guard !quoted else { throw WorkspaceFileError.invalidText }
        if !row.isEmpty || !value.isEmpty || closed { try finishCell(); rows.append(row) }
        guard rows.count <= 10_001 else { throw WorkspaceStorageError.invalidParameters }
        return rows
    }
}
