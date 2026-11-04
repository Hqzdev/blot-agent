import BlotDomain
import Foundation

public struct WorkspaceBudgetService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func reserve(requestID: UUID, taskID: UUID, tokens: Int, limit: Int, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let requestID: UUID; let taskID: UUID; let tokens: Int; let limit: Int }
        let command = try WorkspaceCommand(type: "budget.reserve", workspaceID: identity.workspaceID,
            payload: Input(requestID: requestID, taskID: taskID, tokens: tokens, limit: limit)).data()
        return try await repository.execute(commandID: requestID, command: command, identity: identity) { tx in
            guard tokens > 0, limit >= tokens else { throw WorkspaceStorageError.invalidParameters }
            let task = try tx.require(BlotV3.Task.self, id: taskID)
            guard !WorkspaceTaskService.terminal(task.state) else { throw WorkspaceStorageError.permissionDenied }
            let tasks = try tx.records(BlotV3.Task.self)
            var root = task
            var visited: Set<UUID> = [taskID]
            while let parentID = root.parentTaskId {
                guard visited.insert(parentID).inserted else { throw WorkspaceStorageError.invalidRecord }
                root = try tx.require(BlotV3.Task.self, id: parentID)
                guard !WorkspaceTaskService.terminal(root.state) else { throw WorkspaceStorageError.permissionDenied }
            }
            let effectiveLimit = min(limit, root.budgetTokenLimit ?? limit)
            guard tokens <= effectiveLimit else { throw WorkspaceStorageError.permissionDenied }
            var family: Set<UUID> = [root.metadata.id]
            while true {
                let count = family.count
                family.formUnion(tasks.filter { $0.parentTaskId.map(family.contains) ?? false }.map(\.metadata.id))
                if count == family.count { break }
            }
            var spent = 0
            for entry in try tx.records(BlotV3.BudgetLedger.self) where family.contains(entry.execution.taskId) {
                let charge = entry.state == .settled ? entry.actualTokens ?? entry.reservedTokens : entry.reservedTokens
                guard charge <= effectiveLimit - min(spent, effectiveLimit) else { throw WorkspaceStorageError.permissionDenied }
                spent += charge
            }
            guard spent <= effectiveLimit - tokens else { throw WorkspaceStorageError.permissionDenied }
            let ledger = try BlotV3.BudgetLedger(metadata: tx.metadata(id: requestID, now: now), execution: task.execution,
                requestId: requestID, reservedTokens: tokens, actualTokens: nil, state: .reserved)
            try tx.put(ledger, expectedVersion: 0)
            return requestID
        }
    }

    public func settle(commandID: UUID, requestID: UUID, actualTokens: Int?, now: Date = Date()) async throws {
        struct Input: Encodable { let requestID: UUID; let actualTokens: Int? }
        let command = try WorkspaceCommand(type: "budget.settle", workspaceID: identity.workspaceID,
            payload: Input(requestID: requestID, actualTokens: actualTokens)).data()
        _ = try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            if let actualTokens, actualTokens < 0 { throw WorkspaceStorageError.invalidParameters }
            let old = try tx.require(BlotV3.BudgetLedger.self, id: requestID)
            if old.state == .settled {
                guard old.actualTokens == actualTokens else { throw WorkspaceStorageError.commandConflict }
                return requestID
            }
            let ledger = try BlotV3.BudgetLedger(metadata: tx.metadata(id: requestID, now: now, replacing: old.metadata),
                execution: old.execution, requestId: requestID, reservedTokens: old.reservedTokens,
                actualTokens: actualTokens, state: actualTokens == nil ? .unknown : .settled)
            try tx.put(ledger, expectedVersion: old.metadata.version)
            return requestID
        }
    }
}
