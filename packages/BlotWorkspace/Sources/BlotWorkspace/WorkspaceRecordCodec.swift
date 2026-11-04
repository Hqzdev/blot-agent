import BlotDomain
import Foundation

struct DecodedWorkspaceRecord {
    let metadata: BlotV3.RecordMetadata
    let payload: String
    let content: String?
}

/// Generated from the v3 model catalog. New wire entities must pass typed validation before persistence.
enum WorkspaceRecordCodec {
    static let supportedKinds: Set<String> = ["Account", "Device", "TrustedPair", "Workspace", "Project", "AgentProfile", "AgentConfigurationRevision", "Conversation", "Message", "Task", "TaskAttempt", "Assignment", "AgentSession", "AgentMessage", "PreparedAction", "ApprovalGrant", "ToolInvocation", "Artifact", "MemoryEntry", "ContextSummary", "Connection", "McpConnection", "Automation", "AutomationRun", "BudgetLedger", "SyncCursor", "ConversationParticipant", "MessageReaction", "ConversationReadPosition", "Skill", "SkillRevision", "RecordChange", "RecordTombstone", "ReplicationCheckpoint", "ConflictingRevision", "ExecutionLease", "ModelStep"]
    static func decode(kind: String, payload: String) throws -> DecodedWorkspaceRecord {
        switch kind {
        case "Account": return try record(BlotV3.Account.self, payload: payload)
        case "Device": return try record(BlotV3.Device.self, payload: payload)
        case "TrustedPair": return try record(BlotV3.TrustedPair.self, payload: payload)
        case "Workspace": return try record(BlotV3.Workspace.self, payload: payload)
        case "Project": return try record(BlotV3.Project.self, payload: payload)
        case "AgentProfile": return try record(BlotV3.AgentProfile.self, payload: payload)
        case "AgentConfigurationRevision": return try record(BlotV3.AgentConfigurationRevision.self, payload: payload)
        case "Conversation": return try record(BlotV3.Conversation.self, payload: payload)
        case "Message": return try record(BlotV3.Message.self, payload: payload)
        case "Task": return try record(BlotV3.Task.self, payload: payload)
        case "TaskAttempt": return try record(BlotV3.TaskAttempt.self, payload: payload)
        case "Assignment": return try record(BlotV3.Assignment.self, payload: payload)
        case "AgentSession": return try record(BlotV3.AgentSession.self, payload: payload)
        case "AgentMessage": return try record(BlotV3.AgentMessage.self, payload: payload)
        case "PreparedAction": return try record(BlotV3.PreparedAction.self, payload: payload)
        case "ApprovalGrant": return try record(BlotV3.ApprovalGrant.self, payload: payload)
        case "ToolInvocation": return try record(BlotV3.ToolInvocation.self, payload: payload)
        case "Artifact": return try record(BlotV3.Artifact.self, payload: payload)
        case "MemoryEntry": return try record(BlotV3.MemoryEntry.self, payload: payload)
        case "ContextSummary": return try record(BlotV3.ContextSummary.self, payload: payload)
        case "Connection": return try record(BlotV3.Connection.self, payload: payload)
        case "McpConnection": return try record(BlotV3.McpConnection.self, payload: payload)
        case "Automation": return try record(BlotV3.Automation.self, payload: payload)
        case "AutomationRun": return try record(BlotV3.AutomationRun.self, payload: payload)
        case "BudgetLedger": return try record(BlotV3.BudgetLedger.self, payload: payload)
        case "SyncCursor": return try record(BlotV3.SyncCursor.self, payload: payload)
        case "ConversationParticipant": return try record(BlotV3.ConversationParticipant.self, payload: payload)
        case "MessageReaction": return try record(BlotV3.MessageReaction.self, payload: payload)
        case "ConversationReadPosition": return try record(BlotV3.ConversationReadPosition.self, payload: payload)
        case "Skill": return try record(BlotV3.Skill.self, payload: payload)
        case "SkillRevision": return try record(BlotV3.SkillRevision.self, payload: payload)
        case "RecordChange": return try record(BlotV3.RecordChange.self, payload: payload)
        case "RecordTombstone": return try record(BlotV3.RecordTombstone.self, payload: payload)
        case "ReplicationCheckpoint": return try record(BlotV3.ReplicationCheckpoint.self, payload: payload)
        case "ConflictingRevision": return try record(BlotV3.ConflictingRevision.self, payload: payload)
        case "ExecutionLease": return try record(BlotV3.ExecutionLease.self, payload: payload)
        case "ModelStep": return try record(BlotV3.ModelStep.self, payload: payload)
        default: throw WorkspaceSyncError.unsupportedRecord
        }
    }

    private static func record<T: BlotWorkspaceRecord>(_ type: T.Type, payload: String) throws -> DecodedWorkspaceRecord {
        let data = Data(payload.utf8)
        let record = try WorkspaceCoding.decode(type, from: data)
        let encoded = try WorkspaceCoding.encode(record)
        let supplied = try JSONFields.object(payload)
        let canonical = try JSONFields.object(String(decoding: encoded, as: UTF8.self))
        guard Set(supplied.keys).isSubset(of: Set(canonical.keys)) else { throw WorkspaceSyncError.invalidChange }
        return DecodedWorkspaceRecord(metadata: record.metadata, payload: String(decoding: encoded, as: UTF8.self), content: (record as? BlotV3.Message)?.content)
    }
}
