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
    private(set) var activityMessageIDs: Set<UUID> = []
    @ObservationIgnored private var actionRecords: [UUID: BlotV3.PreparedAction] = [:]
    @ObservationIgnored private var invocationRecords: [UUID: BlotV3.ToolInvocation] = [:]
    @ObservationIgnored private var mcpConnections: [BlotV3.McpConnection] = []
    @ObservationIgnored private var callPresence: [UUID: (raw: String, present: Bool)] = [:]
    @ObservationIgnored private let activityCache = NSCache<NSUUID, ActivityResult>()
    @ObservationIgnored private var steps: [UUID: [BlotV3.ModelStep]] = [:]
    @ObservationIgnored private let plugins = NSCache<NSUUID, PluginResult>()
    @ObservationIgnored private let plans = NSCache<NSUUID, PlanResult>()

    init() {
        activityCache.countLimit = 128; activityCache.totalCostLimit = 4 * 1024 * 1024
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
            var presence: [UUID: (raw: String, present: Bool)] = [:]
            var ids: Set<UUID> = []
            for step in snapshot.modelSteps ?? [] {
                guard let raw = step.toolCallsJSON else { continue }
                let present: Bool
                if let cached = callPresence[step.metadata.id], cached.raw == raw { present = cached.present }
                else { present = raw.utf8.count <= 4_194_304 && ((try? JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8)))?.isEmpty == false) }
                presence[step.metadata.id] = (raw, present)
                if present { ids.insert(step.responseMessageId) }
            }
            callPresence = presence
            if ids != activityMessageIDs { activityMessageIDs = ids }
        }
        if snapshot.preparedActions != previous.preparedActions {
            actionRecords = Dictionary((snapshot.preparedActions ?? []).map { ($0.metadata.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        if snapshot.toolInvocations != previous.toolInvocations {
            invocationRecords = Dictionary((snapshot.toolInvocations ?? []).map { ($0.preparedActionId, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        if snapshot.mcpConnections != previous.mcpConnections { mcpConnections = snapshot.mcpConnections }
        if snapshot.modelSteps != previous.modelSteps || snapshot.preparedActions != previous.preparedActions
            || snapshot.toolInvocations != previous.toolInvocations || snapshot.mcpConnections != previous.mcpConnections { toolRevision += 1 }
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

    func activities(for message: BlotV3.Message) -> [WorkspaceToolActivity] {
        guard message.role == .assistant else { return [] }
        _ = toolRevision
        let matching = steps[message.metadata.id] ?? []
        let key = message.metadata.id as NSUUID
        if let cached = activityCache.object(forKey: key), cached.steps == matching, cached.connections == mcpConnections,
           cached.dependencies.allSatisfy({ cached.actions[$0] == actionRecords[$0] && cached.invocations[$0] == invocationRecords[$0] }) { return cached.rows }
        let result = WorkspaceToolActivityBuilder().build(steps: matching, actions: actionRecords, invocations: invocationRecords, connections: mcpConnections)
        let cached = ActivityResult(steps: matching, result: result, actions: actionRecords, invocations: invocationRecords, connections: mcpConnections)
        let stepCost = matching.reduce(0) { $0 + $1.requestJSON.utf8.count + ($1.toolCallsJSON?.utf8.count ?? 0) + ($1.toolResultsJSON?.utf8.count ?? 0) }
        let cost = stepCost + result.rows.reduce(256) { $0 + $1.details.reduce(128) { $0 + $1.value.utf8.count * 2 } }
        activityCache.setObject(cached, forKey: key, cost: cost)
        return result.rows
    }
    private final class ActivityResult {
        let steps: [BlotV3.ModelStep]
        let rows: [WorkspaceToolActivity]
        let dependencies: Set<UUID>
        let actions: [UUID: BlotV3.PreparedAction]
        let invocations: [UUID: BlotV3.ToolInvocation]
        let connections: [BlotV3.McpConnection]
        init(steps: [BlotV3.ModelStep], result: WorkspaceToolActivityBuilder.Result, actions: [UUID: BlotV3.PreparedAction],
             invocations: [UUID: BlotV3.ToolInvocation], connections: [BlotV3.McpConnection]) {
            self.steps = steps; self.rows = result.rows; self.dependencies = result.dependencies
            self.actions = actions.filter { result.dependencies.contains($0.key) }
            self.invocations = invocations.filter { result.dependencies.contains($0.key) }; self.connections = connections
        }
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
