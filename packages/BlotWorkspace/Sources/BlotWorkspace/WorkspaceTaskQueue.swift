import BlotDomain
import Foundation

/// A single local consumer; independent conversations still share the model executor pool with chat.
public actor WorkspaceTaskQueue {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let available: @Sendable (UUID) async -> Bool
    private let authorize: (@Sendable (BlotV3.Task) async throws -> Void)?
    private let execute: @Sendable (UUID) async throws -> Void
    private var observer: _Concurrency.Task<Void, Never>?
    private var worker: _Concurrency.Task<Void, Never>?
    private var currentID: UUID?
    private var stopped = true
    private var selecting = false
    private var wakeRequested = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity,
                available: @escaping @Sendable (UUID) async -> Bool = { _ in true },
                authorize: (@Sendable (BlotV3.Task) async throws -> Void)? = nil,
                execute: @escaping @Sendable (UUID) async throws -> Void) {
        self.repository = repository; self.identity = identity; self.available = available; self.execute = execute; self.authorize = authorize
    }
    public func start() async {
        guard stopped else { return }
        stopped = false
        let changes = await repository.changes()
        observer = _Concurrency.Task { [weak self] in
            for await _ in changes {
                guard !_Concurrency.Task.isCancelled else { return }
                await self?.wake()
            }
        }
        await wake()
    }
    public func wake() async {
        guard !stopped else { return }
        if let currentID, let worker {
            let current = try? await repository.record(BlotV3.Task.self, id: currentID, workspaceID: identity.workspaceID)
            if let current { try? await repository.rememberTerminalTask(current, identity: identity) }
            if current == nil || current?.state == .canceled || current?.state == .paused { worker.cancel() }
            return
        }
        guard worker == nil else { return }
        if selecting { wakeRequested = true; return }
        selecting = true
        defer {
            selecting = false
            if wakeRequested {
                wakeRequested = false
                _Concurrency.Task { await self.wake() }
            }
        }
        guard let projection = try? await repository.projection(identity: identity) else { return }
        for task in projection.tasks where WorkspaceTaskService.terminal(task.state) { try? await repository.rememberTerminalTask(task, identity: identity) }
        let candidates = projection.tasks.filter {
            $0.state == .queued && $0.execution.executorDeviceId == identity.deviceID && ($0.execution.originDeviceId == identity.deviceID && $0.executionMode == .local_owned || authorize != nil && $0.authorizationJSON != nil && $0.executionMode == .delegated) && !WorkspaceTaskLifecycle.isActionOnly($0, projection: projection)
        }.sorted { $0.metadata.createdAt == $1.metadata.createdAt ? $0.metadata.id.uuidString < $1.metadata.id.uuidString : $0.metadata.createdAt < $1.metadata.createdAt }
        for task in candidates {
            guard (try? await repository.executionAdmitted(task, identity: identity)) == true else { continue }
            if task.executionMode == .delegated {
                guard let authorize else { continue }
                do { try await authorize(task) } catch { continue }
            }
            if let parentID = task.parentTaskId, !projection.tasks.contains(where: { $0.metadata.id == parentID && [.running, .completed].contains($0.state) }) { continue }
            guard !projection.messages.contains(where: { $0.conversationId == task.conversationId && $0.role == .assistant && $0.delivery == .running }),
                  !projection.tasks.contains(where: { $0.conversationId == task.conversationId && $0.state == .running }),
                  await available(task.conversationId) else { continue }
            guard !stopped else { return }
            currentID = task.metadata.id
            worker = _Concurrency.Task { [weak self, execute] in
                do { try await execute(task.metadata.id) } catch { /* The executor persists the failure before returning. */ }
                await self?.finished()
            }
            return
        }
    }
    public func interrupt(taskID: UUID) async {
        guard let currentID, let worker else { return }
        if currentID != taskID {
            guard let projection = try? await repository.projection(identity: identity) else { return }
            var ancestor = projection.tasks.first { $0.metadata.id == currentID }?.parentTaskId
            var visited: Set<UUID> = []
            while let id = ancestor, id != taskID, visited.insert(id).inserted { ancestor = projection.tasks.first { $0.metadata.id == id }?.parentTaskId }
            guard ancestor == taskID else { return }
        }
        worker.cancel()
        await worker.value
    }
    public func stop() async {
        stopped = true
        observer?.cancel(); observer = nil
        let active = worker; active?.cancel()
        await active?.value
    }
    private func finished() async {
        currentID = nil; worker = nil
        await wake()
    }
}
