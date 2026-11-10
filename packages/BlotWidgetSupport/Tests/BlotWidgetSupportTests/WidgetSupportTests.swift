import BlotDomain
import Foundation
import Testing
@testable import BlotWidgetSupport

struct WidgetSupportTests {
    private let owner = UUID()
    private let now = Date(timeIntervalSince1970: 1_794_000_000)

    @Test func destinationsRoundTripAndRejectUntrustedLinks() throws {
        let id = UUID()
        for destination: WidgetDestination in [.compose, .agents, .schedules, .overview, .agent(id), .conversation(id)] {
            #expect(WidgetDestination(url: destination.url) == destination)
        }
        for raw in ["https://widgets/compose", "blot-agent-macos://widgets/compose", "blot-agent-ios://widgets/unknown",
                    "blot-agent-ios://widgets/chat/not-a-uuid", "blot-agent-ios://widgets/compose?approve=true",
                    "blot-agent-ios://widgets/compose#anything", "blot-agent-ios://user@widgets/compose",
                    "blot-agent-ios://widgets/chat/\(id)/extra", "blot-agent-ios://widgets//compose"] {
            #expect(WidgetDestination(url: try #require(URL(string: raw))) == nil)
        }
    }

    @Test func projectionExcludesArchivedAndOtherAccounts() throws {
        let agent = try makeAgent()
        let active = try makeChat(agent: agent.metadata.id)
        let archived = try makeChat(agent: agent.metadata.id, archived: true)
        let foreign = try makeChat(agent: agent.metadata.id, ownerID: UUID())
        let result = project(agents: [agent], chats: [active, archived, foreign], messages: [
            try makeMessage(chat: active.metadata.id, delivery: .running),
            try makeMessage(chat: archived.metadata.id, delivery: .running),
            try makeMessage(chat: foreign.metadata.id, delivery: .completed),
        ])
        #expect(result.conversations.map(\.id) == [active.metadata.id])
        #expect(result.runningCount == 1)
        #expect(result.completedCount == 0)
        #expect(result.agents.first?.state == .running)
        let data = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        #expect(!data.contains("PRIVATE MESSAGE"))
        #expect(!data.contains("PRIVATE INSTRUCTIONS"))
    }

    @Test func latestResponseWinsOverOlderRunningMessage() throws {
        let chat = try makeChat()
        let result = project(chats: [chat], messages: [
            try makeMessage(chat: chat.metadata.id, delivery: .running, age: 60),
            try makeMessage(chat: chat.metadata.id, delivery: .completed),
        ])
        #expect(result.conversations.first?.state == .completed)
        #expect(result.runningCount == 0)
        #expect(result.completedCount == 1)
    }

    @Test func decisionsExcludeExpiredActionsAndDoNotDuplicateTasks() throws {
        let chat = try makeChat()
        let task = try makeTask(chat: chat.metadata.id, state: .waiting_user)
        let valid = try makeAction(task: task, expires: now.addingTimeInterval(60))
        let expired = try makeAction(task: task, expires: now.addingTimeInterval(-1))
        let result = project(chats: [chat], tasks: [task], actions: [valid, expired])
        #expect(result.decisions.count == 1)
        #expect(result.decisions.first?.id == valid.metadata.id)
        #expect(result.conversations.first?.state == .waiting)
    }

    @Test func taskStateOverridesOldMessageAndWaitingComesFirst() throws {
        let chat = try makeChat()
        let runningChat = try makeChat()
        let task = try makeTask(chat: chat.metadata.id, state: .waiting_user)
        let result = project(chats: [runningChat, chat], messages: [
            try makeMessage(chat: chat.metadata.id, delivery: .completed, age: 60),
            try makeMessage(chat: runningChat.metadata.id, delivery: .running),
        ], tasks: [task])
        #expect(result.conversations.first?.id == chat.metadata.id)
        #expect(result.decisions.first?.conversationID == chat.metadata.id)
        #expect(result.runningCount == 1)
    }

    @Test func signedOutProjectionContainsNoWorkspaceData() throws {
        let agent = try makeAgent()
        let result = WidgetSnapshotProjector().project(ownerID: nil, agents: [agent], conversations: [try makeChat()],
            messages: [], tasks: [], actions: [], schedules: [], language: "en", now: now)
        #expect(!result.isSignedIn)
        #expect(result.agents.isEmpty)
        #expect(result.conversations.isEmpty)
        #expect(result.language == "en")
    }

    @Test func schedulesAreFutureOnlyAndOrdered() {
        let schedules = [-30.0, 600, 60].map {
            WidgetSchedule(id: UUID(), title: "Schedule", agentID: nil, nextRun: now.addingTimeInterval($0))
        }
        let result = project(schedules: schedules)
        #expect(result.schedules.map(\.nextRun) == [now.addingTimeInterval(60), now.addingTimeInterval(600)])
    }

    @Test func storeAtomicallyReplacesAccountDataAndThrottlesUnchangedWrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        #expect(try store.read() == nil)
        let signedIn = WidgetSnapshot(ownerID: owner, updatedAt: now)
        #expect(try store.write(signedIn))
        #expect(try !store.write(signedIn))
        var heartbeat = signedIn; heartbeat.updatedAt = now.addingTimeInterval(61)
        #expect(try store.write(heartbeat))
        let signedOut = WidgetSnapshot(updatedAt: now.addingTimeInterval(62))
        #expect(try store.write(signedOut))
        #expect(try store.read() == signedOut)
    }

    @Test func corruptOrUnsupportedDataFailsExplicitly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WidgetSnapshotStore(directory: directory)
        try store.write(WidgetSnapshot())
        let file = directory.appendingPathComponent("WidgetSnapshot.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["version"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        #expect(throws: WidgetSnapshotStore.Failure.self) { try store.read() }
        try Data("invalid json".utf8).write(to: file)
        #expect(throws: (any Error).self) { try store.read() }
        #expect(throws: WidgetSnapshotStore.Failure.self) { try WidgetSnapshotStore(directory: nil).read() }
    }

    private func project(agents: [BlotV3.AgentProfile] = [], chats: [BlotV3.Conversation] = [],
                         messages: [BlotV3.Message] = [], tasks: [BlotV3.Task] = [],
                         actions: [BlotV3.PreparedAction] = [], schedules: [WidgetSchedule] = []) -> WidgetSnapshot {
        WidgetSnapshotProjector().project(ownerID: owner, agents: agents, conversations: chats, messages: messages,
            tasks: tasks, actions: actions, schedules: schedules, language: "ru", now: now)
    }
    private func metadata(ownerID: UUID? = nil, age: TimeInterval = 0) throws -> BlotV3.RecordMetadata {
        try .init(id: UUID(), ownerId: ownerID ?? owner, workspaceId: ownerID ?? owner, version: 1,
                  createdAt: now.addingTimeInterval(-age), updatedAt: now.addingTimeInterval(-age))
    }
    private func makeAgent() throws -> BlotV3.AgentProfile {
        try .init(metadata: metadata(), name: "Researcher", roleId: "custom", avatarShape: "round", avatarColor: "#B49BE8",
                  instructions: "PRIVATE INSTRUCTIONS", modelId: "gigachat", accessMode: .ask_first)
    }
    private func makeChat(agent: UUID? = nil, archived: Bool = false, ownerID: UUID? = nil) throws -> BlotV3.Conversation {
        try .init(metadata: metadata(ownerID: ownerID), agentId: agent, title: "Research", mobileOwned: true, pinned: false, archived: archived)
    }
    private func makeMessage(chat: UUID, delivery: BlotV3.DeliveryState, age: TimeInterval = 0) throws -> BlotV3.Message {
        try .init(metadata: metadata(age: age), conversationId: chat, role: .user, content: "PRIVATE MESSAGE",
                  delivery: delivery, commandId: UUID(), artifactIds: [])
    }
    private func makeTask(chat: UUID, state: BlotV3.TaskState) throws -> BlotV3.Task {
        let meta = try metadata()
        let context = try BlotV3.ExecutionContext(executorDeviceId: UUID(), originDeviceId: UUID(), taskId: meta.id, revision: 1)
        return try .init(metadata: meta, execution: context, conversationId: chat, goal: "Review the draft", state: state, plan: [])
    }
    private func makeAction(task: BlotV3.Task, expires: Date) throws -> BlotV3.PreparedAction {
        try .init(metadata: metadata(), execution: task.execution, toolId: "mail", resource: "draft", parameters: "{}",
                  digest: "digest", consequences: "PRIVATE ACTION", expiresAt: expires, state: .waiting_approval)
    }
}
