import Foundation

@MainActor
protocol WorkspaceMessagePinProviding {
    func setMessagePinned(_ messageID: UUID, pinned: Bool) async throws -> WorkspaceSnapshot
}
