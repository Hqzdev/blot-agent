import BlotDomain
import Foundation

/// Local, account/device-bound grants. A replicated configuration alone never grants browser access.
public actor WorkspaceBrowserService {
    public nonisolated let automaticAccess: Bool
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let driver: any WorkspaceBrowserExecuting
    private var access: WorkspaceBrowserAccess?
    private var suspended = false
    private var scopes: Set<WorkspaceBrowserScope> = []
    private var observation: _Concurrency.Task<Void, Never>?
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore, driver: any WorkspaceBrowserExecuting, automaticAccess: Bool = false) {
        self.repository = repository; self.identity = identity; self.credentials = credentials; self.driver = driver
        self.automaticAccess = automaticAccess
    }
    private var key: String { "browser:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    public func settings() async throws -> WorkspaceBrowserAccess {
        if let access { return access }
        let data = try await credentials.read(key)
        let value = try data.map { try WorkspaceCoding.decode(WorkspaceBrowserAccess.self, from: $0) } ?? .init()
        access = value; return value
    }
    public func configure(agents: Set<UUID>, origins: Set<String>) async throws {
        let normalized = try Set(origins.map { try WorkspaceBrowserURL.origin(WorkspaceBrowserURL.validated($0)) })
        guard agents.count <= 100, normalized.count <= 100 else { throw WorkspaceBrowserError.denied }
        let projection = try await repository.projection(identity: identity)
        guard agents.isSubset(of: Set(projection.agents.map(\.metadata.id))) else { throw WorkspaceBrowserError.denied }
        let previous = try await settings()
        // Fail closed while saving grants/configuration. Revocation also stops outstanding page work.
        access = .init(); await driver.stop(scope: nil)
        try await credentials.write(WorkspaceCoding.encode(WorkspaceBrowserAccess(agents: agents, origins: normalized)), name: key)
        for id in previous.agents.union(agents) {
            let live = try await repository.projection(identity: identity)
            guard let agent = live.agents.first(where: { $0.metadata.id == id }),
                  let revision = try WorkspaceAgentConfigurationResolver().resolve(agentID: id, projection: live) else { continue }
            var tools = Set(revision.toolIds).subtracting(WorkspaceBrowserCatalog.toolIDs)
            if agents.contains(id) { tools.formUnion(WorkspaceBrowserCatalog.toolIDs) }
            if tools != Set(revision.toolIds) {
                _ = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), agentID: id,
                    expectedVersion: agent.metadata.version, draft: .init(name: agent.name, instructions: revision.instructions,
                        avatarShape: agent.avatarShape, avatarColor: agent.avatarColor, modelID: revision.modelId, toolIDs: tools.sorted(), accessMode: agent.accessMode))
            }
        }
        access = .init(agents: agents, origins: normalized)
    }
    private struct Authorization {
        let scope: WorkspaceBrowserScope
        let origins: Set<String>
        let tools: Set<String>
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        do {
            let authorization = try await authorization(context)
            return WorkspaceBrowserCatalog.definitions.filter { authorization.tools.contains($0.name) }
        } catch is CancellationError { throw CancellationError() }
        catch { return [] }
    }
    public func authorize(_ name: String, context: WorkspaceToolContext) async throws -> WorkspaceBrowserCommand {
        let authorization = try await authorization(context)
        guard authorization.tools.contains(name) else { throw WorkspaceBrowserError.denied }
        return .init(id: UUID(), name: name, arguments: .object([:]), scope: authorization.scope, origins: authorization.origins)
    }
    private func authorization(_ context: WorkspaceToolContext) async throws -> Authorization {
        guard !suspended, let agentID = context.agentID else { throw WorkspaceBrowserError.denied }
        let access: WorkspaceBrowserAccess
        if automaticAccess { access = .init() } else { access = try await settings() }
        // Unassigned agents do not scan the workspace just to discover unavailable tools.
        guard automaticAccess || (access.agents.contains(agentID) && !access.origins.isEmpty) else { throw WorkspaceBrowserError.denied }
        let projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }), source.metadata.ownerId == identity.ownerID,
              let agent = projection.agents.first(where: { $0.metadata.id == agentID }),
              let config = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection),
              !projection.conflicts.contains(where: { !$0.resolved && $0.recordId == agentID }) else { throw WorkspaceBrowserError.denied }
        var tools = Set(config.toolIds).intersection(context.allowedToolIDs).intersection(WorkspaceBrowserCatalog.toolIDs)
        let restrictions = WorkspaceToolRestrictions(userRequest: source.content)
        let browserActions = Set(projection.actions.filter { $0.toolId.hasPrefix("browser_") }.map(\.metadata.id))
        let uncertain = projection.invocations.contains { $0.state == .unknown && browserActions.contains($0.preparedActionId) && $0.execution.executorDeviceId == identity.deviceID }
        tools = tools.filter { name in
            let writes = WorkspaceBrowserCatalog.requiresConfirmation(name)
            return restrictions.allows(operation: writes ? "send" : "read") && !(writes && (agent.accessMode == .observe || uncertain))
        }
        if let taskID = context.taskID {
            var id: UUID? = taskID; var visited: Set<UUID> = []
            while let current = id {
                guard visited.insert(current).inserted, visited.count <= 3,
                      let task = projection.tasks.first(where: { $0.metadata.id == current }), task.execution.executorDeviceId == identity.deviceID,
                      !WorkspaceTaskService.terminal(task.state), task.state != .paused,
                      let revision = projection.configurations.first(where: { $0.metadata.id == task.configurationId }) else { throw WorkspaceBrowserError.denied }
                if current == taskID, task.conversationId != source.conversationId || revision.agentId != agentID { throw WorkspaceBrowserError.denied }
                tools.formIntersection(revision.toolIds); id = task.parentTaskId
            }
        }
        return Authorization(scope: .init(sourceID: context.sourceMessageID, taskID: context.taskID, agentID: agentID), origins: automaticAccess ? ["*"] : access.origins, tools: tools)
    }
    public func prepare(_ command: WorkspaceBrowserCommand) async throws -> WorkspaceBrowserBinding { try await driver.prepare(command) }
    public func perform(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserResult {
        try _Concurrency.Task.checkCancellation()
        if command.scope.taskID != nil { scopes.insert(command.scope); observeTasks() }
        return try await withTaskCancellationHandler { try await driver.execute(command, binding: binding) }
        onCancel: { _Concurrency.Task { await self.driver.stop(scope: command.scope) } }
    }
    private func observeTasks() {
        guard observation == nil else { return }
        observation = _Concurrency.Task { [weak self, repository] in
            for await _ in await repository.changes() {
                do { try await _Concurrency.Task.sleep(for: .milliseconds(80)); try _Concurrency.Task.checkCancellation(); await self?.reconcileTasks() }
                catch { return }
            }
        }
    }
    private func reconcileTasks() async {
        guard !suspended else { return }
        guard let projection = try? await repository.taskExecutionProjection(identity: identity) else { return }
        for scope in scopes {
            var id = scope.taskID; var visited: Set<UUID> = []; var active = true
            while let current = id {
                guard visited.insert(current).inserted, visited.count <= 3,
                      let task = projection.tasks.first(where: { $0.metadata.id == current }), !WorkspaceTaskService.terminal(task.state), task.state != .paused else { active = false; break }
                id = task.parentTaskId
            }
            if !active { await driver.stop(scope: scope); scopes.remove(scope) }
        }
    }
    public func resolve(invocationID: UUID, succeeded: Bool) async throws {
        guard let invocation = try await repository.record(BlotV3.ToolInvocation.self, id: invocationID, workspaceID: identity.workspaceID),
              invocation.metadata.ownerId == identity.ownerID, invocation.state == .unknown, invocation.execution.executorDeviceId == identity.deviceID,
              let action = try await repository.record(BlotV3.PreparedAction.self, id: invocation.preparedActionId, workspaceID: identity.workspaceID), action.toolId.hasPrefix("browser_") else { throw WorkspaceBrowserError.denied }
        try await WorkspacePermissionService(repository: repository, identity: identity).finish(commandID: UUID(), invocationID: invocationID,
            state: succeeded ? .succeeded : .failed, result: "{\"state\":\"verified_by_user\"}")
    }
    public func suspend() async { suspended = true; observation?.cancel(); observation = nil; scopes.removeAll(); await driver.stop(scope: nil) }
    public func resume() { suspended = false }
}
