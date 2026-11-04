import BlotDomain
import Foundation

enum WorkspaceAction: String {
    case signIn, register, verify, recover, resetPassword, resendVerification, oauth, createConversation, send, start, pause, stop, approve, deny, grantRule
    case createAgent, saveAgent, createSchedule, updateSchedule, revokeDevice, connect, saveFile, applyChanges, saveSetting, saveModelKey, addMcp, saveMemory
    case addConnection, removeConnection
}

struct WorkspaceRequest {
    var commandID = UUID()
    let action: WorkspaceAction
    let form: WorkspaceForm
    let selectedAgentID: UUID?
    let selectedConversationID: UUID?
    let selectedRecordID: UUID?
}

enum WorkspaceServiceError: Error {
    case unavailable
}

@MainActor
protocol WorkspaceService {
    func load() async throws -> WorkspaceSnapshot?
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot
}

extension WorkspaceService {
    func load() async throws -> WorkspaceSnapshot? { nil }
}

/// v2 cannot execute v3 commands. A missing adapter is an explicit failure, never a simulated success.
struct UnavailableWorkspaceService: WorkspaceService {
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        throw WorkspaceServiceError.unavailable
    }
}

/// Local data mutations for the screen catalog, render harness and previews.
struct PreviewWorkspaceService: WorkspaceService {
    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Yekaterinburg")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    func execute(_ request: WorkspaceRequest, snapshot: WorkspaceSnapshot) async throws -> WorkspaceSnapshot {
        var result = snapshot
        let owner = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let metadata = try BlotV3.RecordMetadata(id: UUID(), ownerId: owner, workspaceId: owner,
                                               version: 1, createdAt: Date(), updatedAt: Date())
        switch request.action {
        case .createAgent:
            result.agents.append(try BlotV3.AgentProfile(metadata: metadata, name: request.form.agent.name,
                roleId: "custom", avatarShape: request.form.agent.shape, avatarColor: request.form.agent.color,
                instructions: request.form.agent.instructions, modelId: "gigachat", accessMode: .ask_first))
        case .saveAgent:
            if let i = result.agents.firstIndex(where: { $0.metadata.id == request.selectedAgentID }) {
                let agent = result.agents[i]
                let updated = try BlotV3.RecordMetadata(id: agent.metadata.id, ownerId: agent.metadata.ownerId, workspaceId: agent.metadata.workspaceId, version: agent.metadata.version + 1, createdAt: agent.metadata.createdAt, updatedAt: Date())
                result.agents[i] = try BlotV3.AgentProfile(metadata: updated, name: request.form.agent.name,
                    roleId: agent.roleId, avatarShape: request.form.agent.shape, avatarColor: request.form.agent.color,
                    instructions: request.form.agent.instructions, modelId: agent.modelId, accessMode: agent.accessMode)
            }
        case .createSchedule:
            #if os(iOS)
            let scheduledAgentID = request.form.schedule.agentID
            #else
            let scheduledAgentID = request.form.schedule.agentID ?? request.selectedAgentID
            #endif
            result.schedules.append(try BlotV3.Automation(metadata: metadata, kind: .task,
                executorDeviceId: request.form.schedule.deviceID ?? result.devices.first { $0.kind == .desktop }?.metadata.id,
                agentId: scheduledAgentID,
                name: request.form.schedule.name, goal: request.form.schedule.goal, timezone: TimeZone.current.identifier,
                localTime: formattedTime(request.form.schedule.time),
                weekdays: request.form.schedule.weekdays.sorted(), missedRunPolicy: .coalesce, enabled: true))
        case .updateSchedule:
            if let i = result.schedules.firstIndex(where: { $0.metadata.id == request.selectedRecordID }) {
                let a = result.schedules[i]
                result.schedules[i] = try BlotV3.Automation(metadata: a.metadata, kind: a.kind,
                    executorDeviceId: a.executorDeviceId, agentId: a.agentId, name: a.name, goal: a.goal,
                    timezone: a.timezone, localTime: a.localTime, weekdays: a.weekdays,
                    missedRunPolicy: a.missedRunPolicy, enabled: !a.enabled)
            }
        case .createConversation:
            let title = result.agents.first(where: { $0.metadata.id == request.selectedAgentID })?.name ?? "Chat with AI"
            result.conversations.append(try BlotV3.Conversation(metadata: metadata, agentId: request.selectedAgentID, title: title, mobileOwned: request.selectedAgentID == nil, pinned: false, archived: false))
        case .send:
            let conversationID = request.selectedConversationID ?? result.conversations.first?.metadata.id ?? owner
            let content = ([request.form.composer.draft] + request.form.composer.attachments.map { "[\($0.lastPathComponent)]" })
                .filter { !$0.isEmpty }.joined(separator: "\n")
            result.messages.append(try BlotV3.Message(metadata: metadata, conversationId: conversationID,
                role: .user, content: content, delivery: .saved, commandId: UUID(), artifactIds: []))
        case .addMcp:
            result.mcpConnections.append(try BlotV3.McpConnection(metadata: metadata, name: request.form.mcp.name, transport: request.form.mcp.transport, endpoint: request.form.mcp.endpoint, toolIds: [], state: .disconnected))
        case .saveMemory:
            if let i = result.memories.firstIndex(where: { $0.metadata.id == request.selectedRecordID }) {
                let m = result.memories[i]
                result.memories[i] = try BlotV3.MemoryEntry(metadata: m.metadata, scope: m.scope, scopeId: m.scopeId, content: request.form.memory.content, sourceId: m.sourceId, state: m.state)
            }
        case .revokeDevice: result.devices.removeAll { $0.metadata.id == request.selectedRecordID }
        case .addConnection:
            if !result.connections.contains(where: { $0.service == request.form.connection.service }) {
                result.connections.append(try .init(metadata: metadata, service: request.form.connection.service,
                    accountName: request.form.connection.accountName, scopes: request.form.connection.scopes, state: .connected))
            }
        case .removeConnection:
            result.connections.removeAll { $0.metadata.id == request.selectedRecordID }
        default: break // The catalog changes the visual state; it performs no external side effects.
        }
        return result
    }
}
