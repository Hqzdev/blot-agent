import BlotDomain
import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceAccountService {
    var isAuthenticated: Bool { get }
    var profile: WorkspaceAccountProfile? { get }
    func signOut() async throws
}

@MainActor
protocol WorkspaceObservationService {
    func currentSnapshot() async throws -> WorkspaceSnapshot
    func changes() async -> AsyncStream<Void>
    func presentationState() async throws -> Data?
    func savePresentationState(_ data: Data) async throws
}

@MainActor
protocol WorkspaceExecutionService {
    func responses(to message: BlotV3.Message) async throws -> AsyncThrowingStream<BlotV3.Message, Error>
    func cancelResponse(in conversationID: UUID) async throws -> WorkspaceSnapshot
    func stopAll() async
}

@MainActor
protocol WorkspaceCommandService: WorkspaceObservationService, WorkspaceExecutionService {
    func updateConversation(_ chat: BlotV3.Conversation, title: String?, pinned: Bool?, archived: Bool?, deleting: Bool) async throws -> WorkspaceSnapshot
    func setReaction(messageID: UUID, emoji: String, removed: Bool) async throws -> WorkspaceSnapshot
    func markRead(conversationID: UUID, messageID: UUID) async throws -> WorkspaceSnapshot
    func deleteMemory(_ memory: BlotV3.MemoryEntry) async throws -> WorkspaceSnapshot
    func createGroup(commandID: UUID, title: String, agentIDs: [UUID]) async throws -> WorkspaceSnapshot
    func updateGroup(_ id: UUID, expectedVersion: Int, title: String, agentIDs: [UUID]) async throws -> WorkspaceSnapshot
    func fileURL(_ id: UUID) async throws -> URL
    func enqueueDueSchedules() async throws -> WorkspaceSnapshot
    func runScheduleManually(_ id: UUID) async throws -> WorkspaceSnapshot
    func searchMessages(_ query: String) async throws -> [BlotV3.Message]
    func fileText(_ id: UUID) async throws -> String
    func resolveConflict(_ selectedID: UUID, displayedIDs: Set<UUID>) async throws -> WorkspaceSnapshot
    func export(_ message: BlotV3.Message, format: WorkspaceExportFormat) async throws -> WorkspaceSnapshot
}

@MainActor
protocol WorkspaceCommandProviding { var workspaceCommands: (any WorkspaceCommandService)? { get } }
