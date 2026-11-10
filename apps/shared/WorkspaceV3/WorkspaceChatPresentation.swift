import BlotDomain
import BlotWorkspace
import Foundation
import Observation

/// Chat views observe only presentation inputs that changed, rather than every task/tool snapshot.
@MainActor @Observable
final class WorkspaceChatPresentation {
    private(set) var agents: [BlotV3.AgentProfile] = []
    private(set) var skills: [BlotV3.Skill] = []
    private(set) var participants: [BlotV3.ConversationParticipant] = []
    private(set) var conversations: [UUID: BlotV3.Conversation] = [:]
    private(set) var artifacts: [UUID: BlotV3.Artifact] = [:]
    private(set) var reactions: [UUID: [BlotV3.MessageReaction]] = [:]
    private(set) var pinnedMessages: [UUID: [BlotV3.Message]] = [:]
    private(set) var messagePins: [UUID: Bool] = [:]
    private(set) var pinnedPlans: [UUID: UUID] = [:]
    private(set) var runningTaskConversationIDs: Set<UUID> = []
    private var toolRevision = 0
    @ObservationIgnored private var steps: [UUID: [BlotV3.ModelStep]] = [:]
    @ObservationIgnored private let plugins = NSCache<NSUUID, PluginResult>()
    @ObservationIgnored private let plans = NSCache<NSUUID, PlanResult>()

    init() {
        plugins.countLimit = 128; plugins.totalCostLimit = 4 * 1024 * 1024
        plans.countLimit = 128; plans.totalCostLimit = 2 * 1024 * 1024
    }

    func update(_ snapshot: WorkspaceSnapshot, previous: WorkspaceSnapshot) {
        if agents != snapshot.agents { agents = snapshot.agents; plans.removeAllObjects() }
        if skills != snapshot.skills ?? [] { skills = snapshot.skills ?? [] }
        if participants != snapshot.participants ?? [] { participants = snapshot.participants ?? [] }
        if snapshot.conversations != previous.conversations {
            conversations = Dictionary(snapshot.conversations.map { ($0.metadata.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        if snapshot.artifacts != previous.artifacts {
            artifacts = Dictionary(snapshot.artifacts.map { ($0.metadata.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        if snapshot.reactions != previous.reactions {
            reactions = Dictionary(grouping: (snapshot.reactions ?? []).filter { !$0.removed }, by: \.messageId)
        }
        if snapshot.messages != previous.messages || snapshot.messagePins != previous.messagePins || snapshot.pinnedGroupPlans != previous.pinnedGroupPlans {
            messagePins = Dictionary((snapshot.messagePins ?? []).map { ($0.messageID, $0.pinned) }, uniquingKeysWith: { _, latest in latest })
            pinnedPlans = snapshot.pinnedGroupPlans ?? [:]
            pinnedMessages = Dictionary(grouping: snapshot.messages.filter {
                messagePins[$0.metadata.id] ?? (pinnedPlans[$0.conversationId] == $0.metadata.id)
            }, by: \.conversationId).mapValues(WorkspaceMessageOrder.ordered)
        }
        if snapshot.modelSteps != previous.modelSteps {
            steps = Dictionary(grouping: snapshot.modelSteps ?? [], by: \.responseMessageId)
            toolRevision += 1
        }
        if snapshot.tasks != previous.tasks || snapshot.localDeviceID != previous.localDeviceID {
            let ids = Set((snapshot.tasks ?? []).filter {
                $0.state == .running && $0.execution.executorDeviceId == snapshot.localDeviceID && $0.executionMode == .local_owned
            }.map(\.conversationId))
            if ids != runningTaskConversationIDs { runningTaskConversationIDs = ids }
        }
    }

    func plan(for message: BlotV3.Message) -> WorkspaceGroupPlanProgress? {
        guard message.role == .assistant, let conversation = conversations[message.conversationId], conversation.kind == .group else { return nil }
        let key = message.metadata.id as NSUUID
        let legacy = message.authorAgentId == conversation.agentId
        if let cached = plans.object(forKey: key), cached.content == message.content, cached.legacy == legacy { return cached.value }
        let value = WorkspaceGroupPlanProgress.decode(message.content, agents: agents)
            ?? (legacy ? WorkspaceGroupPlanProgress.legacy(message.content, agents: agents) : nil)
        plans.setObject(PlanResult(content: message.content, legacy: legacy, value: value), forKey: key, cost: message.content.utf8.count * 3 + 256)
        return value
    }

    func plugins(for message: BlotV3.Message) -> [WorkspacePluginReference] {
        guard message.role == .assistant else { return [] }
        _ = toolRevision
        let matching = steps[message.metadata.id] ?? []
        let key = message.metadata.id as NSUUID
        if let cached = plugins.object(forKey: key), cached.content == message.content, cached.steps == matching { return cached.value }
        let value = WorkspaceMessagePluginAttribution().references(for: message, steps: matching)
        let cost = matching.reduce(message.content.utf8.count) { $0 + $1.requestJSON.utf8.count + ($1.toolResultsJSON?.utf8.count ?? 0) }
        plugins.setObject(PluginResult(content: message.content, steps: matching, value: value), forKey: key, cost: cost * 2 + 256)
        return value
    }

    private final class PluginResult {
        let content: String
        let steps: [BlotV3.ModelStep]
        let value: [WorkspacePluginReference]
        init(content: String, steps: [BlotV3.ModelStep], value: [WorkspacePluginReference]) { self.content = content; self.steps = steps; self.value = value }
    }
    private final class PlanResult {
        let content: String
        let legacy: Bool
        let value: WorkspaceGroupPlanProgress?
        init(content: String, legacy: Bool, value: WorkspaceGroupPlanProgress?) { self.content = content; self.legacy = legacy; self.value = value }
    }
}
