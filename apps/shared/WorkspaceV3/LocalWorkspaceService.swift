import BlotDomain
import BlotWorkspace
import Foundation

/// Owns one authenticated account's local database and its command services.
@MainActor
final class LocalWorkspaceService: WorkspaceDevicePairingCommands, WorkspaceDevicePairingProviding, WorkspaceService, WorkspaceCommandService, WorkspaceCommandProviding {
    var workspacePairing: (any WorkspaceDevicePairingCommands)? { deviceAuthority == nil ? nil : self }
    private let deviceAuthority: WorkspaceDeviceAuthority?
    var workspaceCommands: (any WorkspaceCommandService)? { self }
    let repository: WorkspaceRepository
    private let executorPool = WorkspaceExecutorPool()
    private let credentials: WorkspaceModelCredentialStore
    private let filesDirectory: URL
    private var files: WorkspaceFileService?
    private let makeModel: @MainActor (String) throws -> any ChatModel
    private let runTokenBudget: Int
    private let maximumOutputTokens: Int
    private var identity: WorkspaceIdentity?
    private var responseWorkers: [UUID: _Concurrency.Task<Void, Never>] = [:]
    private var startingResponses: Set<UUID> = []
    private var recovery: _Concurrency.Task<Void, Error>?
    private var closed = false

    init(databaseURL: URL, repository: WorkspaceRepository? = nil, identity: WorkspaceIdentity? = nil,
         maximumOutputTokens: Int = 2048, runTokenBudget: Int = 20000, deviceAuthority: WorkspaceDeviceAuthority? = nil, makeModel: (@MainActor (String) throws -> any ChatModel)? = nil) throws {
        self.deviceAuthority = deviceAuthority
        self.repository = try repository ?? WorkspaceRepository(url: databaseURL)
        self.identity = identity
        self.maximumOutputTokens = maximumOutputTokens
        self.runTokenBudget = runTokenBudget
        let modelCredentials = WorkspaceModelCredentialStore(accountNamespace: identity.map { $0.ownerID.uuidString + ":" + $0.deviceID.uuidString } ?? "local")
        credentials = modelCredentials
        filesDirectory = databaseURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
        self.makeModel = makeModel ?? { modelID in
            guard modelID == "compatible" else { throw ChatModelError.invalidConfiguration }
            let config = try modelCredentials.load()
            return try CompatibleChatModel(endpoint: config.endpoint, model: config.model, apiKey: config.apiKey)
        }
    }

    func load() async throws -> WorkspaceSnapshot? {
        let identity = try await context()
        if recovery == nil {
            let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
            recovery = _Concurrency.Task {
                try await recorder.recoverInterruptedResponses()
                try await WorkspaceModelStepService(repository: repository, identity: identity).recoverInterrupted()
            }
        }
        try await recovery?.value
        return try await snapshot(identity)
    }

    func presentationState() async throws -> Data? { try await repository.presentationState() }
    func savePresentationState(_ data: Data) async throws { try await repository.savePresentationState(data) }

    func changes() async -> AsyncStream<Void> { await repository.changes() }

    func stopAll() async {
        closed = true
        let workers = Array(responseWorkers.values)
        for worker in workers { worker.cancel() }
        for worker in workers { await worker.value }
    }

    func close() async throws {
        await stopAll()
        try await repository.close()
    }

    func currentSnapshot() async throws -> WorkspaceSnapshot {
        try await snapshot(context())
    }

    func cancelResponse(in conversationID: UUID) async throws -> WorkspaceSnapshot {
        if let worker = responseWorkers[conversationID] {
            worker.cancel()
            await worker.value
        }
        return try await currentSnapshot()
    }

    func updateConversation(_ chat: BlotV3.Conversation, title: String? = nil, pinned: Bool? = nil,
                            archived: Bool? = nil, deleting: Bool = false) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        let service = WorkspaceConversationService(repository: repository, identity: identity)
        if deleting {
            try await service.delete(commandID: UUID(), conversationID: chat.metadata.id, expectedVersion: chat.metadata.version)
        } else {
            try await service.update(commandID: UUID(), conversationID: chat.metadata.id, expectedVersion: chat.metadata.version,
                title: title, pinned: pinned, archived: archived)
        }
        return try await snapshot(identity)
    }

    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        let chat = WorkspaceChatService(repository: repository, identity: identity)
        switch request.action {
        case .createConversation:
            let title = snapshot.agents.first { $0.metadata.id == request.selectedAgentID }?.name ?? "Chat with AI"
            _ = try await chat.createConversation(commandID: request.commandID, title: title, agentID: request.selectedAgentID)
        case .send:
            guard let conversationID = request.selectedConversationID, request.form.composer.attachments.count <= 8 else {
                throw WorkspaceStorageError.invalidParameters
            }
            let files = try await fileService()
            var artifactIDs: [UUID] = []
            for (index, url) in request.form.composer.attachments.enumerated() {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let commandID = WorkspaceFileService.attachmentCommandID(sendCommandID: request.commandID, index: index)
                artifactIDs.append(try await files.importFile(commandID: commandID, source: url))
            }
            _ = try await chat.sendMessage(commandID: request.commandID, conversationID: conversationID,
                content: request.form.composer.draft, replyToMessageID: request.form.composer.replyToMessageID, artifactIDs: artifactIDs)
        case .createAgent, .saveAgent:
            let agentID = request.action == .saveAgent ? request.selectedAgentID : nil
            if request.action == .saveAgent && agentID == nil { throw WorkspaceStorageError.invalidParameters }
            let previous = snapshot.agents.first { $0.metadata.id == agentID }
            let service = WorkspaceAgentService(repository: repository, identity: identity)
            _ = try await service.save(commandID: request.commandID, agentID: agentID, expectedVersion: previous?.metadata.version ?? 0,
                draft: .init(name: request.form.agent.name, instructions: request.form.agent.instructions,
                    avatarShape: request.form.agent.shape, avatarColor: request.form.agent.color,
                    modelID: request.form.agent.modelID, toolIDs: request.form.agent.toolIDs))
        case .saveMemory:
            let service = WorkspaceMemoryService(repository: repository, identity: identity)
            if let id = request.selectedRecordID, let memory = snapshot.memories.first(where: { $0.metadata.id == id }) {
                try await service.revise(commandID: request.commandID, memoryID: id, expectedVersion: memory.metadata.version,
                    content: request.form.memory.content)
            } else {
                guard let sourceID = request.form.memory.sourceID else { throw WorkspaceStorageError.invalidParameters }
                _ = try await service.create(commandID: request.commandID, content: request.form.memory.content,
                    sourceID: sourceID, agentID: request.form.memory.agentID, candidate: request.form.memory.candidate)
            }
        case .createSchedule:
            let form = request.form.schedule
            guard let agentID = form.agentID, let executor = form.deviceID, let timezone = TimeZone(identifier: form.timezone) else {
                throw WorkspaceStorageError.invalidParameters
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timezone; formatter.dateFormat = "HH:mm"
            _ = try await WorkspaceScheduleService(repository: repository, identity: identity).save(commandID: request.commandID,
                draft: .init(name: form.name, goal: form.goal, agentID: agentID, executorDeviceID: executor,
                    timezone: form.timezone, localTime: formatter.string(from: form.time), weekdays: form.oneTime ? [] : form.weekdays.sorted(),
                    scheduledAt: form.oneTime ? form.time : nil, missedRunPolicy: form.missedRunPolicy, maximumCatchUpRuns: form.maximumCatchUpRuns))
        case .updateSchedule:
            guard let schedule = snapshot.schedules.first(where: { $0.metadata.id == request.selectedRecordID }),
                  let agentID = schedule.agentId, let executor = schedule.executorDeviceId else { throw WorkspaceStorageError.missingRecord }
            _ = try await WorkspaceScheduleService(repository: repository, identity: identity).save(commandID: request.commandID,
                scheduleID: schedule.metadata.id, expectedVersion: schedule.metadata.version,
                draft: .init(name: schedule.name, goal: schedule.goal, agentID: agentID, executorDeviceID: executor,
                    timezone: schedule.timezone, localTime: schedule.localTime, weekdays: schedule.weekdays, scheduledAt: schedule.scheduledAt,
                    skillRevisionID: schedule.skillRevisionId, missedRunPolicy: schedule.missedRunPolicy,
                    maximumCatchUpRuns: schedule.maxCatchUpRuns ?? 1, enabled: !schedule.enabled))
        case .saveModelKey:
            guard let endpoint = URL(string: request.form.model.endpoint) else { throw ChatModelError.invalidConfiguration }
            _ = try CompatibleChatModel(endpoint: endpoint, model: request.form.model.model, apiKey: request.form.model.secret)
            try credentials.save(.init(endpoint: endpoint, model: request.form.model.model, apiKey: request.form.model.secret))
        default: throw WorkspaceServiceError.unavailable
        }
        return try await self.snapshot(identity)
    }

    func responses(to message: BlotV3.Message) async throws -> AsyncThrowingStream<BlotV3.Message, Error> {
        guard responseWorkers[message.conversationId] == nil,
              startingResponses.insert(message.conversationId).inserted else { throw WorkspaceStorageError.permissionDenied }
        defer { startingResponses.remove(message.conversationId) }
        let identity = try await context()
        let projection = try await repository.projection(identity: identity)
        let agentID = projection.conversations.first { $0.metadata.id == message.conversationId }?.agentId
        let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection)
        if let configuration, !["compatible", "gigachat"].contains(configuration.modelId) { throw WorkspaceServiceError.unavailable }
        let modelID = configuration?.modelId ?? "gigachat"
        let model = try makeModel(modelID)
        let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
        let tools = try WorkspaceToolRegistry(providers: [WorkspaceLocalTools(repository: repository, identity: identity, files: try await fileService())])
        let runtime = WorkspaceModelRuntime(repository: repository, identity: identity, pool: executorPool, tools: tools)
        let responseID = UUID()
        try _Concurrency.Task.checkCancellation()
        let initial = try await recorder.begin(id: responseID, replyingTo: message, agentID: agentID)
        if _Concurrency.Task.isCancelled {
            _ = try await recorder.finish(responseID, delivery: .canceled)
            throw CancellationError()
        }
        return AsyncThrowingStream { continuation in
            let worker = _Concurrency.Task {
                defer { responseWorkers[message.conversationId] = nil }
                var generating = false
                do {
                    continuation.yield(initial)
                    let maximumCharacters = message.artifactIds.isEmpty ? 48_000 : 24_000
                    let prepared = try await WorkspaceContextCompactor(repository: repository, identity: identity, pool: executorPool)
                        .prepare(source: message, responseID: responseID, configuration: configuration, model: model, modelID: modelID,
                            maximumCharacters: maximumCharacters, maximumOutputTokens: maximumOutputTokens, budgetTokenLimit: runTokenBudget)
                    let context = try await responseContext(for: message, projection: prepared, configuration: configuration)
                    let modelRequest = ChatModelRequest(messages: context, maximumOutputTokens: maximumOutputTokens)
                    generating = true
                    try await runtime.generate(source: message, responseID: responseID, request: modelRequest, model: model,
                        modelID: modelID, configuration: configuration, budgetTokenLimit: runTokenBudget,
                        emit: { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    if !generating {
                        let state: BlotV3.DeliveryState = _Concurrency.Task.isCancelled ? .canceled : .interrupted
                        if let saved = try? await recorder.finish(responseID, delivery: state) { continuation.yield(saved) }
                    }
                    continuation.finish(throwing: error)
                }
            }
            responseWorkers[message.conversationId] = worker
            continuation.onTermination = { _ in worker.cancel() }
        }
    }

    private func responseContext(for message: BlotV3.Message, projection: WorkspaceProjection,
                                 configuration: BlotV3.AgentConfigurationRevision?) async throws -> [ChatModelMessage] {
        var context = try WorkspaceContextBuilder().messages(for: message, projection: projection, configuration: configuration,
            maximumCharacters: message.artifactIds.isEmpty ? 48_000 : 24_000)
        if !message.artifactIds.isEmpty {
            let files = try await fileService()
            var attachments = ""
            for id in message.artifactIds {
                let name = projection.artifacts.first { $0.metadata.id == id }?.name ?? id.uuidString
                attachments += "\n\n[Attachment " + id.uuidString + ": " + name + "]\n"
                attachments += try await files.text(for: id, maximumCharacters: min(8_000, 24_000 / message.artifactIds.count))
            }
            let content = (context.last?.content ?? "") + attachments
            context.removeLast()
            context.append(.init(role: "user", content: content))
        }
        return context
    }

    private func context() async throws -> WorkspaceIdentity {
        guard !closed else { throw WorkspaceStorageError.databaseClosed }
        if let identity { return identity }
        let value = try await repository.localIdentity()
        identity = value
        return value
    }

    func setReaction(messageID: UUID, emoji: String, removed: Bool) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        try await WorkspaceInteractionService(repository: repository, identity: identity).setReaction(commandID: UUID(),
            messageID: messageID, emoji: emoji, removed: removed, replacingOtherReactions: true)
        return try await snapshot(identity)
    }

    func markRead(conversationID: UUID, messageID: UUID) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        try await WorkspaceInteractionService(repository: repository, identity: identity).markRead(commandID: UUID(),
            conversationID: conversationID, messageID: messageID)
        return try await snapshot(identity)
    }

    func deleteMemory(_ memory: BlotV3.MemoryEntry) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        try await WorkspaceMemoryService(repository: repository, identity: identity).revise(commandID: UUID(),
            memoryID: memory.metadata.id, expectedVersion: memory.metadata.version, deleting: true)
        return try await snapshot(identity)
    }

    func createGroup(commandID: UUID, title: String, agentIDs: [UUID]) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        _ = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: commandID, title: title, agentIDs: agentIDs)
        return try await snapshot(identity)
    }

    func updateGroup(_ id: UUID, expectedVersion: Int, title: String, agentIDs: [UUID]) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        try await WorkspaceGroupService(repository: repository, identity: identity).update(commandID: UUID(),
            conversationID: id, expectedVersion: expectedVersion, title: title, agentIDs: agentIDs)
        return try await snapshot(identity)
    }

    func fileURL(_ id: UUID) async throws -> URL { try await fileService().url(for: id) }
    func enqueueDueSchedules() async throws -> WorkspaceSnapshot {
        let identity = try await context()
        try await WorkspaceScheduleRunner(repository: repository, identity: identity).enqueueDueRuns()
        return try await snapshot(identity)
    }

    func runScheduleManually(_ id: UUID) async throws -> WorkspaceSnapshot {
        let identity = try await context()
        _ = try await WorkspaceScheduleService(repository: repository, identity: identity).runManually(commandID: UUID(), scheduleID: id)
        return try await snapshot(identity)
    }
    func searchMessages(_ query: String) async throws -> [BlotV3.Message] {
        try await repository.searchMessages(query, workspaceID: context().workspaceID)
    }
    private func requireDeviceAuthority() throws -> WorkspaceDeviceAuthority {
        guard let deviceAuthority else { throw WorkspaceServiceError.unavailable }
        return deviceAuthority
    }
    func createDeviceInvite() async throws -> String { try await requireDeviceAuthority().invite(name: "Mac") }
    func claimDevice(_ token: String) async throws -> WorkspacePairingClaim { try await requireDeviceAuthority().claim(token, name: "iPhone") }
    func inspectDeviceClaim(_ token: String) async throws -> WorkspacePairingClaim { try await requireDeviceAuthority().inspect(token) }
    func approveDevice(_ token: String, code: String) async throws -> String { try await requireDeviceAuthority().approve(token, confirmedCode: code) }
    func finishDevicePairing(_ token: String) async throws { try await requireDeviceAuthority().finish(token) }
    func revokePairedDevice(_ id: UUID) async throws { try await requireDeviceAuthority().revoke(id) }

    func fileText(_ id: UUID) async throws -> String { try await fileService().text(for: id) }

    func resolveConflict(_ selectedID: UUID, displayedIDs: Set<UUID>) async throws -> WorkspaceSnapshot {
        try await WorkspaceConflictService(repository: repository, identity: context()).resolve(commandID: UUID(),
            selectedRevisionID: selectedID, displayedRevisionIDs: displayedIDs)
        return try await currentSnapshot()
    }

    func export(_ message: BlotV3.Message, format: WorkspaceExportFormat) async throws -> WorkspaceSnapshot {
        let writer = WorkspaceDocumentWriter()
        let title = "Response " + String(message.metadata.id.uuidString.prefix(8))
        let data: Data
        let mediaType: String
        switch format {
        case .markdown: data = writer.markdown(title: title, body: message.content); mediaType = "text/markdown"
        case .pdf: data = try writer.pdf(title: title, body: message.content); mediaType = "application/pdf"
        case .csv: data = try writer.csv(headers: ["Content"], rows: message.content.components(separatedBy: .newlines).map { [$0] }); mediaType = "text/csv"
        }
        _ = try await fileService().store(commandID: UUID(), name: title + "." + format.rawValue, mediaType: mediaType, data: data)
        return try await currentSnapshot()
    }

    private func fileService() async throws -> WorkspaceFileService {
        if let files { return files }
        let value = WorkspaceFileService(repository: repository, identity: try await context(), directory: filesDirectory)
        files = value
        return value
    }

    private func snapshot(_ identity: WorkspaceIdentity) async throws -> WorkspaceSnapshot {
        let records = try await repository.projection(identity: identity)
        var result = WorkspaceSnapshot()
        result.modelSteps = records.modelSteps
        result.ownerID = identity.ownerID
        result.localDeviceID = identity.deviceID
        result.pairedDevices = try await deviceAuthority?.devices()
        result.conversations = records.conversations; result.messages = records.messages
        result.agents = records.agents; result.configurations = records.configurations
        result.schedules = records.schedules; result.memories = records.memories.filter { $0.state != .deleted }
        result.artifacts = records.artifacts; result.connections = records.connections
        result.participants = records.participants; result.reactions = records.reactions; result.readPositions = records.readPositions
        result.skills = records.skills; result.skillRevisions = records.skillRevisions; result.summaries = records.summaries
        result.conflicts = records.conflicts
        return result
    }
}
