import BlotDomain
import Foundation

public struct WorkspaceScheduleDraft: Codable, Equatable, Sendable {
    public var name: String
    public var goal: String
    public var agentID: UUID
    public var executorDeviceID: UUID
    public var timezone: String
    public var localTime: String
    public var weekdays: [Int]
    public var scheduledAt: Date?
    public var skillRevisionID: UUID?
    public var missedRunPolicy: BlotV3.MissedRunPolicy
    public var maximumCatchUpRuns: Int
    public var enabled: Bool

    public init(name: String, goal: String, agentID: UUID, executorDeviceID: UUID, timezone: String,
                localTime: String, weekdays: [Int], scheduledAt: Date? = nil, skillRevisionID: UUID? = nil,
                missedRunPolicy: BlotV3.MissedRunPolicy = .coalesce, maximumCatchUpRuns: Int = 1, enabled: Bool = true) {
        self.name = name; self.goal = goal; self.agentID = agentID; self.executorDeviceID = executorDeviceID
        self.timezone = timezone; self.localTime = localTime; self.weekdays = weekdays; self.scheduledAt = scheduledAt
        self.skillRevisionID = skillRevisionID; self.missedRunPolicy = missedRunPolicy
        self.maximumCatchUpRuns = maximumCatchUpRuns; self.enabled = enabled
    }
}

public struct WorkspaceScheduleService: Sendable {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }

    public func save(commandID: UUID, scheduleID: UUID? = nil, expectedVersion: Int = 0,
                     draft: WorkspaceScheduleDraft, now: Date = Date()) async throws -> UUID {
        struct Input: Encodable { let scheduleID: UUID?; let expectedVersion: Int; let draft: WorkspaceScheduleDraft }
        let command = try WorkspaceCommand(type: "automation.save", workspaceID: identity.workspaceID,
            payload: Input(scheduleID: scheduleID, expectedVersion: expectedVersion, draft: draft)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !draft.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  draft.name.utf8.count <= 800, draft.goal.utf8.count <= 32 * 1024,
                  TimeZone(identifier: draft.timezone) != nil, (1...100).contains(draft.maximumCatchUpRuns),
                  Set(draft.weekdays).count == draft.weekdays.count else { throw WorkspaceStorageError.invalidParameters }
            _ = try tx.require(BlotV3.AgentProfile.self, id: draft.agentID)
            if let revisionID = draft.skillRevisionID { _ = try tx.require(BlotV3.SkillRevision.self, id: revisionID) }
            let id = scheduleID ?? commandID
            try tx.requireResolved(kind: "Automation", id: id)
            let old = try scheduleID.map { try tx.require(BlotV3.Automation.self, id: $0, version: expectedVersion) }
            if old == nil && expectedVersion != 0 { throw WorkspaceStorageError.versionConflict }
            let record = try BlotV3.Automation(metadata: tx.metadata(id: id, now: now, replacing: old?.metadata), kind: .task,
                executorDeviceId: draft.executorDeviceID, agentId: draft.agentID, name: draft.name, goal: draft.goal,
                timezone: draft.timezone, localTime: draft.localTime, weekdays: draft.weekdays, missedRunPolicy: draft.missedRunPolicy,
                enabled: draft.enabled, skillRevisionId: draft.skillRevisionID, scheduledAt: draft.scheduledAt, maxCatchUpRuns: draft.maximumCatchUpRuns)
            var validation = record
            if !record.enabled {
                validation = try BlotV3.Automation(metadata: record.metadata, kind: record.kind, executorDeviceId: record.executorDeviceId,
                    agentId: record.agentId, name: record.name, goal: record.goal, timezone: record.timezone, localTime: record.localTime,
                    weekdays: record.weekdays, missedRunPolicy: record.missedRunPolicy, enabled: true,
                    skillRevisionId: record.skillRevisionId, scheduledAt: record.scheduledAt, maxCatchUpRuns: record.maxCatchUpRuns)
            }
            _ = try WorkspaceScheduleCalculator().nextRun(for: validation, after: now)
            try tx.put(record, expectedVersion: expectedVersion)
            return id
        }
    }

    public func fire(scheduleID: UUID, scheduledAt: Date, now: Date = Date()) async throws -> UUID {
        let id = WorkspaceLogicalID.make(kind: "AutomationRun", workspaceID: identity.workspaceID,
            parts: [scheduleID.uuidString, ISO8601DateFormatter().string(from: scheduledAt)])
        return try await enqueue(commandID: id, scheduleID: scheduleID, scheduledAt: scheduledAt, now: now)
    }

    public func runManually(commandID: UUID, scheduleID: UUID, now: Date = Date()) async throws -> UUID {
        try await enqueue(commandID: commandID, scheduleID: scheduleID, scheduledAt: nil, now: now)
    }

    private func enqueue(commandID: UUID, scheduleID: UUID, scheduledAt: Date?, now: Date) async throws -> UUID {
        struct Input: Encodable { let scheduleID: UUID; let scheduledAt: Date? }
        let command = try WorkspaceCommand(type: scheduledAt == nil ? "automation.run.manual" : "automation.fire",
            workspaceID: identity.workspaceID, payload: Input(scheduleID: scheduleID, scheduledAt: scheduledAt)).data()
        return try await repository.execute(commandID: commandID, command: command, identity: identity) { tx in
            let schedule = try tx.require(BlotV3.Automation.self, id: scheduleID)
            try tx.requireResolved(kind: "Automation", id: scheduleID)
            guard let executor = schedule.executorDeviceId, let agentID = schedule.agentId else { throw WorkspaceStorageError.invalidRecord }
            if let scheduledAt {
                guard schedule.enabled, executor == tx.identity.deviceID, scheduledAt <= now,
                      try WorkspaceScheduleCalculator().nextRun(for: schedule, after: scheduledAt.addingTimeInterval(-0.001)) == scheduledAt else {
                    throw WorkspaceStorageError.permissionDenied
                }
            }
            let conversation: UUID
            if let chat = try tx.records(BlotV3.Conversation.self).last(where: { $0.agentId == agentID && !$0.archived && $0.kind != .group }) {
                conversation = chat.metadata.id
            } else {
                conversation = WorkspaceLogicalID.make(kind: "AutomationConversation", workspaceID: tx.identity.workspaceID, parts: [commandID.uuidString])
                let chat = try BlotV3.Conversation(metadata: tx.metadata(id: conversation, now: now), agentId: agentID,
                    title: schedule.name, mobileOwned: false, pinned: false, archived: false, kind: .direct)
                try tx.put(chat, expectedVersion: 0)
            }
            let taskID = WorkspaceLogicalID.make(kind: "AutomationTask", workspaceID: tx.identity.workspaceID, parts: [commandID.uuidString])
            _ = try WorkspaceTaskService.insert(tx, taskID: taskID, conversationID: conversation, agentID: agentID,
                goal: schedule.goal, executorDeviceID: executor, parentTaskID: nil, skillRevisionID: schedule.skillRevisionId,
                budgetTokenLimit: 20_000, now: now)
            let task = try tx.require(BlotV3.Task.self, id: taskID)
            let run = try BlotV3.AutomationRun(metadata: tx.metadata(id: commandID, now: now), execution: task.execution,
                automationId: scheduleID, scheduledAt: scheduledAt ?? now, state: .queued, trigger: scheduledAt == nil ? .manual : .scheduled)
            try tx.put(run, expectedVersion: 0)
            return taskID
        }
    }
}
