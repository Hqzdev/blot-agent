import Foundation

/// Presentation data only. Credentials and browser cookie values never belong in a card.
public enum WorkspaceCardContent: Codable, Equatable, Sendable {
    case email(MailDraft)
    case question(Question)
    case subscription(Subscription)
    case purchase(WorkspacePurchaseOrder)
    case page(PageLink)
    public struct PageLink: Codable, Equatable, Sendable {
        public let id: UUID
        public let title: String
        public init(id: UUID, title: String) { self.id = id; self.title = title }
    }
    case command(Command)
    case takeover(Takeover)
    case task(TaskResult)
    case slack(SlackDraft)
    case plugin(Plugin)
    case connectionRequest(ConnectionRequest)
    public struct ConnectionRequest: Codable, Equatable, Sendable {
        public let pluginID: String
        public let name: String
        public let reason: String
        public let agentID: UUID
        public init(pluginID: String, name: String, reason: String, agentID: UUID) {
            self.pluginID = pluginID; self.name = name; self.reason = reason; self.agentID = agentID
        }
    }
    case credential(Credential)
    case cookies(CookieTransfer)
    case mailFailure(MailFailure)

    public struct MailDraft: Codable, Equatable, Sendable {
        public var sender: String; public var recipient: String; public var subject: String; public var body: String
        public init(sender: String, recipient: String, subject: String, body: String) {
            self.sender = sender; self.recipient = recipient; self.subject = subject; self.body = body
        }
    }
    public struct Question: Codable, Equatable, Sendable {
        public let prompt: String; public let choices: [String]; public let allowsCustomAnswer: Bool
        public init(prompt: String, choices: [String], allowsCustomAnswer: Bool = true) {
            self.prompt = prompt; self.choices = choices; self.allowsCustomAnswer = allowsCustomAnswer
        }
    }
    public struct Subscription: Codable, Equatable, Sendable {
        public let checkoutURL: URL
        public init(checkoutURL: URL) { self.checkoutURL = checkoutURL }
    }
    public struct Command: Codable, Equatable, Sendable {
        public let ruleScope: String?
        public let title: String; public let details: String; public let command: String
        public init(title: String, details: String, command: String, ruleScope: String? = nil) { self.ruleScope = ruleScope; self.title = title; self.details = details; self.command = command }
    }
    public struct Takeover: Codable, Equatable, Sendable {
        public let reason: String; public let tabID: UUID
        public init(reason: String, tabID: UUID) { self.reason = reason; self.tabID = tabID }
    }
    public struct TaskResult: Codable, Equatable, Sendable {
        public let state: String; public let title: String; public let branch: String?; public let files: [String]; public let pullRequestURL: URL?
        public let additions: Int?; public let deletions: Int?
        public init(title: String, branch: String?, files: [String], pullRequestURL: URL?, state: String = "completed", additions: Int? = nil, deletions: Int? = nil) {
            self.state = state; self.title = title; self.branch = branch; self.files = files; self.pullRequestURL = pullRequestURL
            self.additions = additions; self.deletions = deletions
        }
    }
    public struct SlackDraft: Codable, Equatable, Sendable {
        public let workspace: String; public let channel: String; public let thread: String?; public var body: String
        public init(workspace: String, channel: String, thread: String?, body: String) {
            self.workspace = workspace; self.channel = channel; self.thread = thread; self.body = body
        }
    }
    public struct Plugin: Codable, Equatable, Sendable {
        public let name: String; public let detail: String; public let connectionID: UUID
        public init(name: String, detail: String, connectionID: UUID) { self.name = name; self.detail = detail; self.connectionID = connectionID }
    }
    public struct Credential: Codable, Equatable, Sendable {
        public let name: String; public let purpose: String; public let reference: String
        public init(name: String, purpose: String, reference: String) { self.name = name; self.purpose = purpose; self.reference = reference }
    }
    public struct CookieTransfer: Codable, Equatable, Sendable {
        public let sourceProfileID: UUID; public let destinationProfileID: UUID; public let domains: [String]
        public init(sourceProfileID: UUID, destinationProfileID: UUID, domains: [String]) {
            self.sourceProfileID = sourceProfileID; self.destinationProfileID = destinationProfileID; self.domains = domains
        }
    }
    public struct MailFailure: Codable, Equatable, Sendable {
        public let draft: MailDraft; public let detail: String; public let outcomeUnknown: Bool
        public init(draft: MailDraft, detail: String, outcomeUnknown: Bool) { self.draft = draft; self.detail = detail; self.outcomeUnknown = outcomeUnknown }
    }
    public var kind: String {
        switch self {
        case .email: "email"; case .question: "question"; case .subscription: "subscription"; case .purchase: "purchase"
        case .command: "command"; case .takeover: "takeover"; case .task: "task"; case .slack: "slack"
        case .plugin: "plugin"; case .credential: "credential"; case .cookies: "cookies"; case .mailFailure: "mailFailure"; case .page: "page"
        case .connectionRequest: "connectionRequest"
        }
    }
    public var fallback: String {
        switch self {
        case .email(let v): v.subject
        case .question(let v): v.prompt
        case .subscription: "Ori"
        case .purchase(let order): order.merchant
        case .page(let page): page.title
        case .command(let v): v.title
        case .takeover(let v): v.reason
        case .task(let v): v.title
        case .slack(let v): v.channel
        case .plugin(let v): v.name
        case .connectionRequest(let v): v.name + " · " + v.reason
        case .credential(let v): v.purpose
        case .cookies(let v): v.domains.joined(separator: ", ")
        case .mailFailure(let v): v.detail
        }
    }
    func validate() throws {
        guard try JSONEncoder().encode(self).count <= 48 * 1024, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WorkspaceStorageError.invalidParameters
        }
        switch self {
        case .connectionRequest(let request):
            guard !request.pluginID.isEmpty, request.pluginID.utf8.count <= 200, !request.name.isEmpty,
                  !request.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceStorageError.invalidParameters }
        case .purchase(let order): try order.validate()
        case .question(let v):
            guard v.choices.count <= 12, Set(v.choices).count == v.choices.count,
                  v.choices.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
                  v.allowsCustomAnswer || !v.choices.isEmpty else { throw WorkspaceStorageError.invalidParameters }
        case .cookies(let v):
            guard v.sourceProfileID != v.destinationProfileID, !v.domains.isEmpty, v.domains.count <= 32,
                  v.domains.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains(":") && !$0.contains("*") }) else { throw WorkspaceStorageError.invalidParameters }
        case .subscription(let v):
            guard v.checkoutURL.scheme == "https", v.checkoutURL.host == "blot-agent.vercel.app", v.checkoutURL.path == "/app/pricing" else {
                throw WorkspaceStorageError.invalidParameters
            }
        default: break
        }
    }
}

public struct WorkspaceCardResponse: Codable, Equatable, Sendable {
    public let action: String
    public let value: String?
    public init(action: String, value: String? = nil) { self.action = action; self.value = value }
}
