import BlotWorkspace
import Foundation

/// Keep test connections until teardown can close all reopened handles before removing WAL files.
private actor WorkspaceTestConnections {
    static let shared = WorkspaceTestConnections()
    private var repositories: [String: [WorkspaceRepository]] = [:]

    func open(_ url: URL) throws -> WorkspaceRepository {
        let repository = try WorkspaceRepository(url: url)
        repositories[url.standardizedFileURL.resolvingSymlinksInPath().path, default: []].append(repository)
        return repository
    }
    func clean(_ directory: URL) async {
        let prefix = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        let paths = repositories.keys.filter { $0.hasPrefix(prefix) }
        let connections = paths.flatMap { repositories.removeValue(forKey: $0) ?? [] }
        for connection in connections {
            do { try await connection.close() }
            catch { return } // Keep the temporary directory if a connection cannot close safely.
        }
        try? FileManager.default.removeItem(at: directory)
    }
}

func workspaceTestRepository(url: URL) async throws -> WorkspaceRepository {
    try await WorkspaceTestConnections.shared.open(url)
}
func cleanupWorkspaceTestStorage(_ directory: URL) {
    Task { await WorkspaceTestConnections.shared.clean(directory) }
}
