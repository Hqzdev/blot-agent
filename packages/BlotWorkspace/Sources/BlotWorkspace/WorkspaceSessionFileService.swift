import BlotDomain
import Foundation

public struct WorkspaceDirectoryChoice: Sendable {
    public let path: String
    public let bookmark: Data
    public init(path: String, bookmark: Data) { self.path = path; self.bookmark = bookmark }
}
public struct WorkspaceSessionDirectoryGrant: Identifiable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let agentID: UUID
    public let path: String
}

/// Built-in file access is limited to one chat's default folder and owner-selected external folders.
public actor WorkspaceSessionFileService {
    private struct Grant: Codable {
        let id: UUID
        let conversation: UUID
        let agent: UUID
        let path: String
        let bookmark: Data
    }
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let makeExecutor: @Sendable () -> any NativeExecuting
    private let choose: @Sendable (String, String?) async throws -> WorkspaceDirectoryChoice?
    private var executor: (any NativeExecuting)?
    private var grants: [Grant]?
    private var scopes: [UUID: URL] = [:]
    private var suspended = false
    private var toolsSuspended = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore,
                makeExecutor: @escaping @Sendable () -> any NativeExecuting,
                choose: @escaping @Sendable (String, String?) async throws -> WorkspaceDirectoryChoice?) {
        self.repository = repository; self.identity = identity; self.credentials = credentials
        self.makeExecutor = makeExecutor; self.choose = choose
    }
    private var key: String { "session-directories:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    private func loadGrants() async throws -> [Grant] {
        if let grants { return grants }
        let data = try await credentials.read(key)
        let value = try data.map { try WorkspaceCoding.decode([Grant].self, from: $0) } ?? []
        grants = value; return value
    }
    public func directories() async throws -> [WorkspaceSessionDirectoryGrant] {
        try await loadGrants().map { .init(id: $0.id, conversationID: $0.conversation, agentID: $0.agent, path: $0.path) }
    }
    public func revokeDirectory(_ id: UUID) async throws {
        let values = try await loadGrants().filter { $0.id != id }
        try await credentials.write(WorkspaceCoding.encode(values), name: key); grants = values
        scopes.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        await executor?.stopAll(); executor = nil
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        do {
            let (_, tools) = try await authorization(context)
            return WorkspaceSessionFileCatalog.definitions.filter { tools.contains($0.name) }
        } catch is CancellationError { throw CancellationError() }
        catch { return [] }
    }
    public func authorize(_ name: String, context: WorkspaceToolContext) async throws -> UUID {
        let (conversation, tools) = try await authorization(context)
        guard tools.contains(name) else { throw NativeExecutionError.accessDenied }; return conversation
    }
    private func authorization(_ context: WorkspaceToolContext) async throws -> (UUID, Set<String>) {
        guard !suspended, !toolsSuspended, let agentID = context.agentID else { throw NativeExecutionError.accessDenied }
        let projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }), source.metadata.ownerId == identity.ownerID,
              let agent = projection.agents.first(where: { $0.metadata.id == agentID }),
              let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection),
              !projection.conflicts.contains(where: { !$0.resolved && ($0.recordId == agentID || $0.recordId == source.conversationId) }) else { throw NativeExecutionError.accessDenied }
        let restrictions = WorkspaceToolRestrictions(userRequest: source.content)
        let uncertain = projection.invocations.contains { invocation in invocation.state == .unknown && projection.actions.contains { $0.metadata.id == invocation.preparedActionId && $0.resource.hasPrefix("session-files:" + source.conversationId.uuidString) } }
        var tools = Set(configuration.toolIds).intersection(context.allowedToolIDs).intersection(WorkspaceSessionFileCatalog.toolIDs)
        tools = tools.filter { name in
            let writes = WorkspaceSessionFileCatalog.writes(name)
            return restrictions.allows(operation: writes ? "create" : name == "workspace_directory" ? "resources" : "read") && !(writes && (agent.accessMode == .observe || uncertain))
        }
        var taskID = context.taskID, visited: Set<UUID> = []
        while let id = taskID {
            guard visited.insert(id).inserted, visited.count <= 3,
                  let task = projection.tasks.first(where: { $0.metadata.id == id }), task.conversationId == source.conversationId,
                  task.execution.executorDeviceId == identity.deviceID, !WorkspaceTaskService.terminal(task.state), task.state != .paused,
                  let pinned = projection.configurations.first(where: { $0.metadata.id == task.configurationId }) else { throw NativeExecutionError.accessDenied }
            tools.formIntersection(pinned.toolIds)
            taskID = task.parentTaskId
        }
        guard !suspended, !toolsSuspended else { throw NativeExecutionError.accessDenied }
        return (source.conversationId, tools)
    }
    public func prepare(conversationID: UUID? = nil) async throws -> ChatJSON {
        var parameters = ["owner_id": identity.ownerID.uuidString, "workspace_id": identity.workspaceID.uuidString]
        if let conversationID { parameters["conversation_id"] = conversationID.uuidString }
        return try await request(.workspacePrepare, root: "/", parameters: parameters)
    }
    public func request(_ operation: NativeRequest.Operation, root: String, parameters: [String: String]) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        guard !suspended else { throw NativeExecutionError.unavailable }
        if executor == nil { executor = makeExecutor() }
        let command = NativeCommand(projectID: identity.workspaceID, root: root, executable: "/usr/bin/true")
        return try await executor!.request(.init(operation, command: command, parameters: parameters))
    }
    public func perform(_ call: ChatToolCall, context: WorkspaceToolContext, actionID: UUID) async throws -> ChatJSON {
        let conversation = try await authorize(call.name, context: context), fields = call.arguments.mcpFields
        if call.name == "workspace_request_directory" {
            if let existing = try await loadGrants().first(where: { $0.id == actionID && $0.agent == context.agentID && $0.conversation == conversation }) { return grantResult(existing) }
            guard let purpose = fields["purpose"]?.mcpString, !purpose.isEmpty, purpose.utf8.count <= 1000 else { throw NativeExecutionError.invalidRequest }
            let name = fields["folder_name"]?.mcpString
            if let name { guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"), !name.contains("\0"), name.utf8.count <= 180 else { throw NativeExecutionError.invalidRequest } }
            guard let choice = try await choose(purpose, name) else { throw NativeExecutionError.accessDenied }
            try _Concurrency.Task.checkCancellation()
            _ = try await authorize(call.name, context: context)
            var values = try await loadGrants()
            guard values.count < 100 else { throw NativeExecutionError.invalidRequest }
            let grant = Grant(id: actionID, conversation: conversation, agent: context.agentID!, path: choice.path, bookmark: choice.bookmark)
            values.append(grant); try await credentials.write(WorkspaceCoding.encode(values), name: key); grants = values
            return grantResult(grant)
        }
        let prepared = try await prepare(conversationID: conversation).mcpFields
        guard let defaultRoot = prepared["files_root"]?.mcpString else { throw NativeExecutionError.unavailable }
        if call.name == "workspace_directory" {
            let available = try await loadGrants().filter { $0.conversation == conversation && $0.agent == context.agentID }
            guard let base = prepared["root"]?.mcpString, defaultRoot.hasPrefix(base + "/") else { throw NativeExecutionError.unavailable }
            return .object(["path": .string("~/Blot" + defaultRoot.dropFirst(base.count)), "directory_id": .string("session"), "approved_directories": .array(available.map(grantResult))])
        }
        let directoryID = fields["directory_id"]?.mcpString ?? "session"
        let root: String
        if directoryID == "session" { root = defaultRoot }
        else {
            guard let id = UUID(uuidString: directoryID), let grant = try await loadGrants().first(where: { $0.id == id && $0.conversation == conversation && $0.agent == context.agentID }) else { throw NativeExecutionError.accessDenied }
            root = try resolve(grant)
        }
        var parameters: [String: String] = [:]
        for (key, value) in fields { if let text = value.mcpString { parameters[key] = text } }
        if call.name == "workspace_write_file" { guard (parameters["content"] ?? "").utf8.count <= 40 * 1024 else { throw NativeExecutionError.invalidRequest } }
        let operations: [String: NativeRequest.Operation] = ["workspace_list_files": .workspaceList, "workspace_read_file": .workspaceRead,
            "workspace_write_file": .workspaceWrite, "workspace_create_directory": .workspaceMkdir]
        guard let operation = operations[call.name] else { throw NativeExecutionError.invalidRequest }
        return try await request(operation, root: root, parameters: parameters)
    }
    private func grantResult(_ grant: Grant) -> ChatJSON {
        .object(["directory_id": .string(grant.id.uuidString), "name": .string((grant.path as NSString).lastPathComponent), "state": .string("granted")])
    }
    private func resolve(_ grant: Grant) throws -> String {
        #if os(macOS)
        if scopes[grant.id] == nil {
            var stale = false
            let url = try URL(resolvingBookmarkData: grant.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.standardizedFileURL.resolvingSymlinksInPath().path == grant.path,
                  url.startAccessingSecurityScopedResource() else { throw NativeExecutionError.accessDenied }
            scopes[grant.id] = url
        }
        return grant.path
        #else
        throw NativeExecutionError.unavailable
        #endif
    }
    public func suspend() async {
        suspended = true; await executor?.stopAll(); executor = nil
        for url in scopes.values { url.stopAccessingSecurityScopedResource() }; scopes.removeAll()
    }
    public func quiesceTools() { toolsSuspended = true }
    public func resume() { suspended = false; toolsSuspended = false }
    public func resolve(invocationID: UUID, succeeded: Bool) async throws {
        guard let invocation = try await repository.record(BlotV3.ToolInvocation.self, id: invocationID, workspaceID: identity.workspaceID),
              invocation.state == .unknown, invocation.execution.executorDeviceId == identity.deviceID,
              let action = try await repository.record(BlotV3.PreparedAction.self, id: invocation.preparedActionId, workspaceID: identity.workspaceID), action.toolId.hasPrefix("workspace_") else { throw NativeExecutionError.accessDenied }
        try await WorkspacePermissionService(repository: repository, identity: identity).finish(commandID: UUID(), invocationID: invocationID,
            state: succeeded ? .succeeded : .failed, result: "{\"state\":\"verified_by_user\"}")
        let tasks = WorkspaceTaskService(repository: repository, identity: identity)
        if succeeded { try? await tasks.completeActionTask(taskID: invocation.execution.taskId) }
        else if !(try await repository.projection(identity: identity)).modelSteps.contains(where: { $0.taskId == invocation.execution.taskId }) {
            try? await tasks.cancel(commandID: UUID(), taskID: invocation.execution.taskId)
        }
    }
}
