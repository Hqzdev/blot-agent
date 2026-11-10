import BlotDomain
import Foundation

struct WorkspaceAccountForm {
    var browserRegistering = false
    var name = ""
    var lastName = ""
    var email = ""
    var password = ""
    var code = ""
}
struct WorkspaceAgentForm {
    var name = ""
    var instructions = ""
    var modelID = "gigachat"
    #if os(iOS)
    var toolIDs: [String] = PhoneAgentDefaults.tools
    #else
    var toolIDs: [String] = []
    #endif
    var remember = true
    var shape = "round"
    var color = "orange"
}
struct WorkspaceScheduleForm {
    var skillRevisionID: UUID?
    var timezone = TimeZone.current.identifier
    var oneTime = false
    var missedRunPolicy: BlotV3.MissedRunPolicy = .coalesce
    var maximumCatchUpRuns = 1
    var agentID: UUID?
    var deviceID: UUID?
    var name = ""
    var goal = ""
    var time = Date()
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]
}
struct WorkspaceMcpForm {
    var name = ""
    var endpoint = ""
    var transport = "STREAMABLE_HTTP"
}
struct WorkspaceModelForm {
    var secret = ""
    var endpoint = "https://api.openai.com/v1/chat/completions"
    var model = ""
}
struct WorkspaceConnectionForm {
    var service = ""
    var accountName = ""
    var scopes: [String] = []
}
struct WorkspaceMemoryForm {
    var content = ""
    var sourceID: UUID?
    var agentID: UUID?
    var candidate = false
}
struct WorkspacePairForm { var code = "" }
nonisolated struct WorkspaceComposerForm: Codable, Sendable {
    var draft = ""
    var attachments: [URL] = []
    var replyToMessageID: UUID?
    var projectID: UUID? = nil
}
struct WorkspaceSearchForm { var query = "" }
struct WorkspacePreferencesForm {
    var backgroundWork = false
    var accessMode: BlotV3.AccessMode = .ask_first
}

/// Each feature owns its draft. Navigation never reuses another form's name, code or content.
struct WorkspaceForm {
    var account = WorkspaceAccountForm()
    var agent = WorkspaceAgentForm()
    var schedule = WorkspaceScheduleForm()
    var mcp = WorkspaceMcpForm()
    var model = WorkspaceModelForm()
    var connection = WorkspaceConnectionForm()
    var memory = WorkspaceMemoryForm()
    var pair = WorkspacePairForm()
    var composer = WorkspaceComposerForm()
    var search = WorkspaceSearchForm()
    var preferences = WorkspacePreferencesForm()
    var personalization = WorkspacePersonalization()
    var messageContext = WorkspaceMessageContext()

    /// Auth credentials cannot leak into a message, schedule or MCP operation.
    func requestInput(for action: WorkspaceAction) -> WorkspaceForm {
        var input = WorkspaceForm()
        switch action {
        case .oauth: input.account.browserRegistering = account.browserRegistering
        case .signIn: input.account.email = account.email; input.account.password = account.password
        case .register, .resendVerification, .resetPassword: input.account = account
        case .verify: input.account.email = account.email; input.account.code = account.code
        case .recover: input.account.email = account.email
        case .createAgent, .saveAgent: input.agent = agent
        case .createSchedule: input.schedule = schedule
        case .send:
            input.composer = composer
            input.personalization = personalization
            input.messageContext = messageContext
        case .addMcp: input.mcp = mcp
        case .saveMemory: input.memory = memory
        case .connect: input.pair = pair
        case .addConnection: input.connection = connection
        case .saveSetting: input.preferences = preferences
        case .saveModelKey: input.model = model
        default: break
        }
        return input
    }
}
