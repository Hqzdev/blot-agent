import Foundation

/// Only successfully tested shortcut names are considered connected on this installation.
@MainActor
final class AppleShortcutStore {
    private let file: URL
    private var names: Set<String>
    init(file: URL) throws {
        self.file = file
        names = FileManager.default.fileExists(atPath: file.path) ? Set(try PropertyListDecoder().decode([String].self, from: Data(contentsOf: file))) : []
    }
    var resources: [AppleResource] { names.sorted().map { .init(id: $0, name: $0) } }
    func contains(_ selected: [String]) -> Bool { !selected.isEmpty && Set(selected).isSubset(of: names) }
    func invalidate(_ name: String) throws {
        let updated = names.subtracting([name])
        if FileManager.default.fileExists(atPath: file.path) {
            try PropertyListEncoder().encode(updated.sorted()).write(to: file, options: .atomic)
        }
        names = updated
    }
    func verified(_ name: String) throws {
        let updated = names.union([name])
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListEncoder().encode(updated.sorted()).write(to: file, options: .atomic)
        names = updated
    }
}
