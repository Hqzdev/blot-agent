import BlotDomain
import Foundation

/// Consistent read model taken from one SQLite transaction.
public struct WorkspaceProjection: Codable, Equatable, Sendable {
    public var agents: [BlotV3.AgentProfile] = []
    public var configurations: [BlotV3.AgentConfigurationRevision] = []
    public var conversations: [BlotV3.Conversation] = []
    public var messages: [BlotV3.Message] = []
    public var participants: [BlotV3.ConversationParticipant] = []
    public var reactions: [BlotV3.MessageReaction] = []
    public var readPositions: [BlotV3.ConversationReadPosition] = []
    public var schedules: [BlotV3.Automation] = []
    public var automationRuns: [BlotV3.AutomationRun] = []
    public var memories: [BlotV3.MemoryEntry] = []
    public var summaries: [BlotV3.ContextSummary] = []
    public var skills: [BlotV3.Skill] = []
    public var skillRevisions: [BlotV3.SkillRevision] = []
    public var artifacts: [BlotV3.Artifact] = []
    public var connections: [BlotV3.Connection] = []
    public var modelSteps: [BlotV3.ModelStep] = []
    public var tasks: [BlotV3.Task] = []
    public var sessions: [BlotV3.AgentSession] = []
    public var agentMessages: [BlotV3.AgentMessage] = []
    public var actions: [BlotV3.PreparedAction] = []
    public var grants: [BlotV3.ApprovalGrant] = []
    public var invocations: [BlotV3.ToolInvocation] = []
    public var budgets: [BlotV3.BudgetLedger] = []
    public var conflicts: [BlotV3.ConflictingRevision] = []
    public init() {}
}
