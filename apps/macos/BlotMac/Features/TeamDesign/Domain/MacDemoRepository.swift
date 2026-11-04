import Foundation

protocol MacDemoRepository {
    func load() throws -> MacDemoState?
    func save(_ state: MacDemoState) throws
}

struct MacDemoFileRepository: MacDemoRepository {
    let url: URL

    static func applicationRepository() -> Self {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Blot/Demo", isDirectory: true)
        return Self(url: directory.appendingPathComponent("workspace-v1.json"))
    }

    func load() throws -> MacDemoState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let state = try JSONDecoder().decode(MacDemoState.self, from: Data(contentsOf: url))
        guard state.version == 1, !state.agents.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return state
    }

    func save(_ state: MacDemoState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}
