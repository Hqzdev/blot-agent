import BlotDomain
import Foundation

/// Device-only project bindings and authority. A replicated Project never grants command execution.
public actor WorkspaceNativeService {
    private let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let files: WorkspaceFileService
    private let makeExecutor: @Sendable () -> any NativeExecuting
    private var executor: (any NativeExecuting)?
    private var state: WorkspaceNativeState?
    private var suspended = false
    private var mutating = false
    private var scopes: [UUID: URL] = [:]
    struct Job {
        let command: NativeCommand; let taskID: UUID; let sourceID: UUID; let agentID: UUID; let invocationID: UUID
        let actionOnly: Bool; let projectRevision: UUID
        let secrets: [String]
        var snapshot: NativeProcessSnapshot?
    }
    private var jobs: [UUID: Job] = [:]
    private var monitors: [UUID: _Concurrency.Task<Void, Never>] = [:]
    private var preparations: [String: (UUID, UUID, ChatJSON)] = [:]
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore, files: WorkspaceFileService,
                makeExecutor: @escaping @Sendable () -> any NativeExecuting = {
                    #if os(macOS)
                    NativeXPCClient()
                    #else
                    NativeUnavailableExecutor()
                    #endif
                }) {
        self.repository = repository; self.identity = identity; self.credentials = credentials; self.files = files; self.makeExecutor = makeExecutor
    }
    private var key: String { "native-projects:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    private func load() async throws -> WorkspaceNativeState {
        if let state { return state }
        let data = try await credentials.read(key)
        let value = try data.map { try WorkspaceCoding.decode(WorkspaceNativeState.self, from: $0) } ?? WorkspaceNativeState()
        if state == nil { state = value }; return state ?? value
    }
    private func save(_ value: WorkspaceNativeState) async throws {
        guard !suspended else { throw NativeExecutionError.unavailable }
        try await credentials.write(WorkspaceCoding.encode(value), name: key); state = value
    }
    public func projects() async throws -> [WorkspaceNativeProject] { try await load().projects }
    public func selectedProject(conversationID: UUID) async throws -> UUID? { try await load().conversations[conversationID.uuidString] }
    public func select(projectID: UUID?, conversationID: UUID) async throws {
        var value = try await load()
        if let projectID { guard value.projects.contains(where: { $0.id == projectID }) else { throw NativeExecutionError.accessDenied } }
        guard try await repository.record(BlotV3.Conversation.self, id: conversationID, workspaceID: identity.workspaceID) != nil else { throw NativeExecutionError.accessDenied }
        value.conversations[conversationID.uuidString] = projectID; try await save(value)
    }
    @discardableResult
    public func connect(name: String, root: URL, bookmark: Data?, agents: Set<UUID>, trustedClasses: Set<String> = [],
                        variables: [String: String] = [:], gitToken: String = "", gitCredentialURL: String = "", sshAuthSocket: String = "", trustedCLI: Bool) async throws -> UUID {
        #if os(macOS)
        guard !suspended, !mutating, trustedCLI, !name.isEmpty, name.utf8.count <= 200, !agents.isEmpty,
              trustedClasses.isSubset(of: Set(WorkspaceNativeCatalog.trustedClasses)), variables.count <= 50,
              variables.allSatisfy({ key, value in !key.hasPrefix("GIT_") && key != "SSH_AUTH_SOCK" && key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil && !value.contains("\0") && value.utf8.count <= 8192 }),
              gitToken.utf8.count <= 8192, !gitToken.contains(where: \.isNewline), sshAuthSocket.utf8.count <= 4096 else { throw NativeExecutionError.invalidRequest }
        mutating = true; defer { mutating = false }
        if !gitToken.isEmpty {
            guard let url = URL(string: gitCredentialURL), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw NativeExecutionError.invalidRequest }
        }
        _ = try NativeProjectFiles(root: root.path)
        let entry = WorkspaceNativeProject(id: UUID(), name: name, root: root.resolvingSymlinksInPath().path, bookmark: bookmark,
            revision: UUID(), agents: agents, trustedClasses: trustedClasses, variables: variables, gitToken: gitToken, gitCredentialURL: gitCredentialURL, sshAuthSocket: sshAuthSocket)
        var value = try await load()
        guard value.projects.count < 30, !value.projects.contains(where: { $0.root == entry.root }) else { throw NativeExecutionError.invalidRequest }
        struct Input: Encodable { let id: UUID; let name: String; let agents: [UUID] }
        let command = try WorkspaceCommand(type: "project.connect", workspaceID: identity.workspaceID,
            payload: Input(id: entry.id, name: name, agents: agents.sorted { $0.uuidString < $1.uuidString })).data()
        _ = try await repository.execute(commandID: entry.id, command: command, identity: identity) { tx in
            let record = try BlotV3.Project(metadata: tx.metadata(id: entry.id, now: Date()), name: name, repositoryPath: "device:" + identity.deviceID.uuidString)
            try tx.put(record, expectedVersion: 0)
            for agent in agents { try Self.assign(tx, agentID: agent, adding: true, trusted: !trustedClasses.isEmpty) }
            return entry.id
        }
        guard !suspended else { throw NativeExecutionError.unavailable }
        value.projects.append(entry); try await save(value)
        return entry.id
        #else
        throw NativeExecutionError.unavailable
        #endif
    }
    public func disconnect(_ id: UUID) async throws {
        guard !mutating else { throw NativeExecutionError.busy }; mutating = true; defer { mutating = false }
        var value = try await load()
        guard let entry = value.projects.first(where: { $0.id == id }) else { throw NativeExecutionError.accessDenied }
        value.projects.removeAll { $0.id == id }; value.conversations = value.conversations.filter { $0.value != id }
        try await save(value)
        for job in jobs.values where job.command.projectID == id { _ = try? await executor?.request(.init(.stop, command: job.command)) }
        let stoppedJobs = jobs.values.filter { $0.command.projectID == id }.map(\.command.id)
        for jobID in stoppedJobs { await monitors[jobID]?.value; jobs[jobID] = nil }
        struct Input: Encodable { let id: UUID }
        let command = try WorkspaceCommand(type: "project.disconnect", workspaceID: identity.workspaceID, payload: Input(id: id)).data()
        let remaining = value.projects
        _ = try await repository.execute(commandID: UUID(), command: command, identity: identity) { tx in
            if let record = try tx.record(BlotV3.Project.self, id: id) { try tx.delete(record) }
            for agent in entry.agents where !remaining.contains(where: { $0.agents.contains(agent) }) { try Self.assign(tx, agentID: agent, adding: false) }
            return id
        }
        if let scope = scopes.removeValue(forKey: id) { scope.stopAccessingSecurityScopedResource() }
    }
    private static func assign(_ tx: WorkspaceTransaction, agentID: UUID, adding: Bool, trusted: Bool = false) throws {
        guard let agent = try tx.record(BlotV3.AgentProfile.self, id: agentID) else {
            if adding { throw WorkspaceStorageError.missingRecord }; return
        }
        try tx.requireResolved(kind: "AgentProfile", id: agentID)
        guard let configurationID = agent.configurationId else { throw NativeExecutionError.accessDenied }
        let config = try tx.require(BlotV3.AgentConfigurationRevision.self, id: configurationID), revisionID = UUID()
        let tools = adding ? Set(config.toolIds).union(WorkspaceNativeCatalog.toolIDs) : Set(config.toolIds).subtracting(WorkspaceNativeCatalog.toolIDs)
        guard WorkspaceToolCapacity.accepts(tools) else { throw NativeExecutionError.invalidRequest }
        try tx.put(BlotV3.AgentConfigurationRevision(metadata: tx.metadata(id: revisionID, now: Date()), agentId: agentID,
            revision: agent.metadata.version + 1, instructions: config.instructions, toolIds: tools.sorted(), modelId: config.modelId), expectedVersion: 0)
        try tx.put(BlotV3.AgentProfile(metadata: tx.metadata(id: agentID, now: Date(), replacing: agent.metadata), name: agent.name, roleId: agent.roleId,
            avatarShape: agent.avatarShape, avatarColor: agent.avatarColor, instructions: agent.instructions, modelId: agent.modelId,
            accessMode: trusted && agent.accessMode != .observe ? .trusted_scope : agent.accessMode, configurationId: revisionID), expectedVersion: agent.metadata.version)
    }
    func authorize(_ name: String, context: WorkspaceToolContext) async throws -> WorkspaceNativeProject {
        #if os(macOS)
        guard !suspended, !mutating, let agentID = context.agentID else { throw NativeExecutionError.accessDenied }
        let value = try await load(), projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }), source.metadata.ownerId == identity.ownerID else { throw NativeExecutionError.accessDenied }
        let projectID: UUID?
        if let id = context.taskID {
            guard let task = projection.tasks.first(where: { $0.metadata.id == id }), task.execution.executorDeviceId == identity.deviceID,
                  !WorkspaceTaskService.terminal(task.state), task.state != .paused else { throw NativeExecutionError.accessDenied }
            var parentID = task.parentTaskId, visited: Set<UUID> = []
            while let id = parentID {
                guard visited.insert(id).inserted, visited.count <= 2,
                      let parent = projection.tasks.first(where: { $0.metadata.id == id && $0.projectId == task.projectId }),
                      let config = projection.configurations.first(where: { $0.metadata.id == parent.configurationId }), config.toolIds.contains(name),
                      ![.paused, .canceled, .failed, .interrupted].contains(parent.state) else { throw NativeExecutionError.accessDenied }
                parentID = parent.parentTaskId
            }
            projectID = task.projectId
        } else { projectID = value.conversations[source.conversationId.uuidString] }
        guard let projectID, let project = value.projects.first(where: { $0.id == projectID && $0.agents.contains(agentID) }),
              let row = try await repository.record(BlotV3.Project.self, id: projectID, workspaceID: identity.workspaceID), row.repositoryPath == "device:" + identity.deviceID.uuidString,
              context.allowedToolIDs.contains(name), try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection)?.toolIds.contains(name) == true,
              !projection.conflicts.contains(where: { !$0.resolved && ($0.recordId == projectID || $0.recordId == agentID) }) else { throw NativeExecutionError.accessDenied }
        let writes = WorkspaceNativeCatalog.writes(name)
        if writes {
            guard projection.agents.first(where: { $0.metadata.id == agentID })?.accessMode != .observe,
                  WorkspaceToolRestrictions(userRequest: source.content).allows(operation: name == "git_push" || name == "process_run" ? "send" : "update"),
                  WorkspaceToolRestrictions(userRequest: source.content).allows(operation: "update"),
                  !projection.invocations.contains(where: { invocation in invocation.state == .unknown && projection.actions.contains { $0.metadata.id == invocation.preparedActionId && $0.resource == "project:" + projectID.uuidString } }) else { throw NativeExecutionError.unknown }
        }
        if let bookmark = project.bookmark {
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale, url.resolvingSymlinksInPath().path == project.root else { throw NativeExecutionError.accessDenied }
            if scopes[projectID] == nil {
                guard url.startAccessingSecurityScopedResource() else { throw NativeExecutionError.accessDenied }
                scopes[projectID] = url
            }
        }
        return project
        #else
        throw NativeExecutionError.unavailable
        #endif
    }
    private func activeExecutor() throws -> any NativeExecuting {
        guard !suspended else { throw NativeExecutionError.unavailable }
        if let executor { return executor }; let value = makeExecutor(); executor = value; return value
    }
    func command(project: WorkspaceNativeProject, arguments: ChatJSON = .object([:]), id: UUID = UUID(), git: Bool = false) throws -> NativeCommand {
        let fields = arguments.mcpFields
        var env = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin", "LANG": "en_US.UTF-8"]
        if git {
            if !project.sshAuthSocket.isEmpty { env["SSH_AUTH_SOCK"] = project.sshAuthSocket }
            if !project.gitToken.isEmpty { env.merge(["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "http." + project.gitCredentialURL + ".extraHeader", "GIT_CONFIG_VALUE_0": "Authorization: Bearer " + project.gitToken]) { _, new in new } }
        } else if case .array(let names) = fields["variables"] {
            for name in names { guard let name = name.mcpString, let value = project.variables[name] else { throw NativeExecutionError.invalidRequest }; env[name] = value }
        }
        var timeout = 120
        if case .number(let value) = fields["timeout_seconds"] { guard value >= 1, value <= 1800, value.rounded() == value else { throw NativeExecutionError.invalidRequest }; timeout = Int(value) }
        let args: [String]
        if case .array(let values) = fields["arguments"] { args = try values.map { guard let text = $0.mcpString else { throw NativeExecutionError.invalidRequest }; return text } } else { args = [] }
        return NativeCommand(id: id, projectID: project.id, root: project.root, directory: fields["directory"]?.mcpString ?? ".",
            executable: fields["executable"]?.mcpString ?? "/usr/bin/git", arguments: args, environment: env, timeout: timeout)
    }
    func perform(_ request: NativeRequest) async throws -> ChatJSON { try await activeExecutor().request(request) }
    func rememberPreparation(_ result: ChatJSON, project: UUID, source: UUID) {
        if let id = result.mcpFields["preparation_id"]?.mcpString { preparations[id] = (project, source, result) }
        if preparations.count > 200 { preparations.removeAll() }
    }
    func preparation(_ id: String, project: UUID, source: UUID) throws -> ChatJSON {
        guard let value = preparations[id], value.0 == project, value.1 == source else { throw NativeExecutionError.changed }; return value.2
    }
    func register(command: NativeCommand, context: WorkspaceToolContext, taskID: UUID, invocationID: UUID, project: WorkspaceNativeProject) {
        jobs[command.id] = .init(command: command, taskID: taskID, sourceID: context.sourceMessageID, agentID: context.agentID!, invocationID: invocationID,
            actionOnly: context.taskID == nil, projectRevision: project.revision, secrets: ([project.gitToken] + Array(project.variables.values)).filter { !$0.isEmpty })
        monitors[command.id] = _Concurrency.Task { [weak self] in await self?.monitor(command.id) }
    }
    public func processSnapshots() -> [NativeProcessSnapshot] { jobs.values.compactMap(\.snapshot).sorted { $0.startedAt > $1.startedAt } }
    public func stopProcess(_ id: UUID) async throws {
        guard let job = jobs[id] else { throw NativeExecutionError.unknown }; _ = try await perform(.init(.stop, command: job.command))
    }
    public func inspect(projectID: UUID, operation: NativeRequest.Operation) async throws -> String {
        guard [.gitStatus, .gitDiff, .gitLog].contains(operation), let project = try await load().projects.first(where: { $0.id == projectID }) else { throw NativeExecutionError.accessDenied }
        let result = try await perform(.init(operation, command: command(project: project, git: true)))
        return String(decoding: try WorkspaceCoding.encode(redact(result, project: project)), as: UTF8.self)
    }
    func process(_ id: UUID, context: WorkspaceToolContext, stop: Bool) async throws -> ChatJSON {
        guard let job = jobs[id], job.sourceID == context.sourceMessageID, job.agentID == context.agentID,
              context.taskID == nil && job.actionOnly || context.taskID == job.taskID else { throw NativeExecutionError.accessDenied }
        if stop { try await stopProcess(id) }
        if let snapshot = jobs[id]?.snapshot { return summary(snapshot) }
        return .object(["process_id": .string(id.uuidString), "state": .string("running")])
    }
    private func monitor(_ id: UUID) async {
        defer { monitors[id] = nil }
        guard let job = jobs[id] else { return }
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        do {
            while true {
                let configuration = try await load().projects.first { $0.id == job.command.projectID }
                let live = try await repository.projection(identity: identity)
                let currentTools = try WorkspaceAgentConfigurationResolver().resolve(agentID: job.agentID, projection: live)?.toolIds ?? []
                if configuration?.revision != job.projectRevision || configuration?.agents.contains(job.agentID) != true || !currentTools.contains("process_run") || live.agents.first(where: { $0.metadata.id == job.agentID })?.accessMode == .observe {
                    _ = try? await executor?.request(.init(.stop, command: job.command))
                }
                if let task = try await repository.record(BlotV3.Task.self, id: job.taskID, workspaceID: identity.workspaceID),
                   [.paused, .canceled, .interrupted, .failed, .completed].contains(task.state) {
                    _ = try? await executor?.request(.init(.stop, command: job.command))
                }
                let result = try await perform(.init(.status, command: job.command))
                var snapshot = try WorkspaceCoding.decode(NativeProcessSnapshot.self, from: WorkspaceCoding.encode(result))
                snapshot = try WorkspaceCoding.decode(NativeProcessSnapshot.self, from: WorkspaceCoding.encode(redact(try snapshot.json(), secrets: job.secrets, root: job.command.root)))
                if snapshot.finishedAt != nil {
                    let log = "stdout:\n" + snapshot.stdout + "\nstderr:\n" + snapshot.stderr
                    let artifact = try await files.store(commandID: id, name: "command-" + String(id.uuidString.prefix(8)) + ".log", mediaType: "text/plain", data: Data(log.utf8), taskID: job.taskID)
                    var fields = summary(snapshot).mcpFields; fields["log_artifact_id"] = .string(artifact.uuidString)
                    let state: BlotV3.ActionState = snapshot.state == .succeeded ? .succeeded : .failed
                    try await permission.finish(commandID: UUID(), invocationID: job.invocationID, state: state, result: String(decoding: try WorkspaceCoding.encode(ChatJSON.object(fields)), as: UTF8.self))
                    jobs[id]?.snapshot = snapshot
                    if job.actionOnly { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: job.taskID) }
                    return
                }
                jobs[id]?.snapshot = snapshot
                try await _Concurrency.Task.sleep(for: .milliseconds(150))
            }
        } catch {
            try? await permission.finish(commandID: UUID(), invocationID: job.invocationID, state: .unknown)
        }
    }
    private func summary(_ value: NativeProcessSnapshot) -> ChatJSON {
        .object(["process_id": .string(value.id.uuidString), "state": .string(value.finishedAt == nil ? "running" : value.state == .succeeded ? "succeeded" : "failed"),
            "process_state": .string(value.state.rawValue), "exitCode": value.exitCode.map { .number(Double($0)) } ?? .null,
            "stdout": .string(String(value.stdout.suffix(8000))), "stderr": .string(String(value.stderr.suffix(8000))),
            "truncated": .bool(value.truncated || value.stdout.count > 8000 || value.stderr.count > 8000)])
    }
    func redact(_ value: ChatJSON, project: WorkspaceNativeProject) -> ChatJSON {
        redact(value, secrets: ([project.gitToken] + Array(project.variables.values)).filter { !$0.isEmpty }, root: project.root)
    }
    private func redact(_ value: ChatJSON, secrets: [String], root: String) -> ChatJSON {
        switch value {
        case .string(let text): return .string(secrets.reduce(text.replacingOccurrences(of: root, with: "[project]")) { $0.replacingOccurrences(of: $1, with: "[redacted]") })
        case .object(let fields): return .object(fields.mapValues { redact($0, secrets: secrets, root: root) })
        case .array(let values): return .array(values.map { redact($0, secrets: secrets, root: root) })
        default: return value
        }
    }
    public func suspend() async {
        suspended = true
        await executor?.stopAll()
        for monitor in monitors.values { await monitor.value }
        executor = nil
        for scope in scopes.values { scope.stopAccessingSecurityScopedResource() }; scopes = [:]
    }
    public func resume() { suspended = false }
    public func checkRemote(invocationID: UUID) async throws -> Bool {
        let projection = try await repository.projection(identity: identity)
        guard let invocation = projection.invocations.first(where: { $0.metadata.id == invocationID && $0.state == .unknown && $0.execution.executorDeviceId == identity.deviceID }),
              let action = projection.actions.first(where: { $0.metadata.id == invocation.preparedActionId && $0.toolId == "git_push" }),
              let project = try await load().projects.first(where: { "project:" + $0.id.uuidString == action.resource }) else { throw NativeExecutionError.accessDenied }
        let value = try WorkspaceCoding.decode(ChatJSON.self, from: Data(action.consequences.utf8)).mcpFields["binding"]?.mcpFields ?? [:]
        var parameters: [String: String] = [:]
        for key in ["commit", "remote", "endpoint", "destination"] {
            guard let text = value[key]?.mcpString else { throw NativeExecutionError.changed }
            parameters[key] = key == "endpoint" ? text.replacingOccurrences(of: "[project]", with: project.root) : text
        }
        let result = try await perform(.init(.gitReconcilePush, command: command(project: project, git: true), parameters: parameters))
        guard result.mcpFields["state"] == .string("succeeded") else { return false }
        let safe = redact(result, project: project)
        try await WorkspacePermissionService(repository: repository, identity: identity).finish(commandID: UUID(), invocationID: invocationID, state: .succeeded,
            externalID: parameters["commit"], result: String(decoding: try WorkspaceCoding.encode(safe), as: UTF8.self))
        return true
    }
    public func resolve(invocationID: UUID, succeeded: Bool) async throws {
        let projection = try await repository.projection(identity: identity)
        guard let invocation = projection.invocations.first(where: { $0.metadata.id == invocationID && $0.state == .unknown && $0.execution.executorDeviceId == identity.deviceID }),
              let action = projection.actions.first(where: { $0.metadata.id == invocation.preparedActionId && $0.resource.hasPrefix("project:") }) else { throw NativeExecutionError.accessDenied }
        _ = action
        let result: ChatJSON = .object(["state": .string(succeeded ? "succeeded" : "failed"), "owner_verified": .bool(true)])
        try await WorkspacePermissionService(repository: repository, identity: identity).finish(commandID: UUID(), invocationID: invocationID,
            state: succeeded ? .succeeded : .failed, result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
    }
}
