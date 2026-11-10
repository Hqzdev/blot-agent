import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

nonisolated struct WorkspaceUnavailableNativeExecutor: NativeExecuting {
    func request(_ request: NativeRequest) async throws -> ChatJSON { throw NativeExecutionError.unavailable }
    func stopAll() async {}
}

@MainActor
protocol WorkspaceNativeProviding {
    func nativeService() async throws -> WorkspaceNativeService
    func delegateProjectTask(conversationID: UUID, agentID: UUID, deviceID: UUID, goal: String, projectID: UUID) async throws -> UUID
}
extension LocalWorkspaceService: WorkspaceNativeProviding {
    func nativeService() async throws -> WorkspaceNativeService {
        if let native { return native }
        let value = WorkspaceNativeService(repository: repository, identity: try await context(), credentials: mcpCredentials,
            files: try await fileService(), makeExecutor: makeNativeExecutor)
        native = value; return value
    }
    func nativeTools() async throws -> WorkspaceNativeTools {
        let identity = try await context(), service = try await nativeService(), center = appleIntegrations.interactions
        return WorkspaceNativeTools(service: service, repository: repository, identity: identity) { title, details in try await center.confirm(title: title, details: details) }
    }
    func delegateProjectTask(conversationID: UUID, agentID: UUID, deviceID: UUID, goal: String, projectID: UUID) async throws -> UUID {
        let identity = try await context(), authority = try requireDeviceAuthority()
        return try await WorkspaceTaskDelegation(repository: repository, identity: identity, authority: authority).create(commandID: UUID(),
            conversationID: conversationID, agentID: agentID, executorID: deviceID, goal: goal, projectID: projectID)
    }
}
extension WorkspaceAccountApplicationService: WorkspaceNativeProviding {
    func nativeService() async throws -> WorkspaceNativeService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }; return try await local.nativeService()
    }
    func delegateProjectTask(conversationID: UUID, agentID: UUID, deviceID: UUID, goal: String, projectID: UUID) async throws -> UUID {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.delegateProjectTask(conversationID: conversationID, agentID: agentID, deviceID: deviceID, goal: goal, projectID: projectID)
    }
}
