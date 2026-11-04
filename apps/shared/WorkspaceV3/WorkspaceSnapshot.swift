import BlotDomain
import Foundation

struct WorkspaceSnapshot: Codable, Equatable {
    var toolInvocations: [BlotV3.ToolInvocation]?
    var preparedActions: [BlotV3.PreparedAction]?
    var modelSteps: [BlotV3.ModelStep]?
    var ownerID: UUID?
    var localDeviceID: UUID?
    var participants: [BlotV3.ConversationParticipant]?
    var reactions: [BlotV3.MessageReaction]?
    var readPositions: [BlotV3.ConversationReadPosition]?
    var skills: [BlotV3.Skill]?
    var skillRevisions: [BlotV3.SkillRevision]?
    var configurations: [BlotV3.AgentConfigurationRevision]?
    var summaries: [BlotV3.ContextSummary]?
    var conflicts: [BlotV3.ConflictingRevision]?
    var agents: [BlotV3.AgentProfile] = []
    var conversations: [BlotV3.Conversation] = []
    var messages: [BlotV3.Message] = []
    var schedules: [BlotV3.Automation] = []
    var devices: [BlotV3.Device] = []
    var memories: [BlotV3.MemoryEntry] = []
    var connections: [BlotV3.Connection] = []
    var artifacts: [BlotV3.Artifact] = []
    var mcpConnections: [BlotV3.McpConnection] = []
}
