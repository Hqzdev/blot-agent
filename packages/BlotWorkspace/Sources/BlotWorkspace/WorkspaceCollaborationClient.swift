import Foundation

public struct WorkspaceTeam: Codable, Sendable, Identifiable { public let id: UUID; public let name: String; public let role: String }
public struct WorkspaceTeamMember: Codable, Sendable, Identifiable { public let accountID: UUID; public let name: String; public let email: String; public let role: String; public var id: UUID { accountID } }
public struct WorkspaceTeamInvite: Codable, Sendable { public let token: String; public let expiresAt: String }
public struct WorkspaceTeamBot: Codable, Sendable, Identifiable {
    public let id: UUID; public let teamID: UUID; public let ownerID: UUID; public let version: Int; public var configuration: Configuration
    public struct Channel: Codable, Sendable, Equatable {
        public var connectionID: String; public var provider: String; public var workspace: String; public var channel: String; public var trigger: String
        public init(connectionID: String = "", provider: String = "slack", workspace: String = "", channel: String = "", trigger: String = "@blot") { self.connectionID = connectionID; self.provider = provider; self.workspace = workspace; self.channel = channel; self.trigger = trigger }
    }
    public struct Configuration: Codable, Sendable {
        public var name: String; public var agentID: UUID; public var executorDeviceID: UUID; public var instructions: String; public var allowedTools: [String]; public var channels: [Channel]; public var enabled: Bool
        public init(name: String, agentID: UUID, executorDeviceID: UUID, instructions: String, allowedTools: [String], channels: [Channel], enabled: Bool) {
            self.name = name; self.agentID = agentID; self.executorDeviceID = executorDeviceID; self.instructions = instructions; self.allowedTools = allowedTools; self.channels = channels; self.enabled = enabled
        }
    }
}
public struct WorkspacePublicationLink: Decodable, Sendable { public let id: UUID; public let token: String; public let expiresAt: String }
public struct WorkspacePublicationSummary: Decodable, Sendable, Identifiable { public let id: UUID; public let kind: String; public let title: String; public let expiresAt: String; public let revoked: Bool }

public struct WorkspaceCollaborationClient: Sendable {
    private let http: WorkspaceCloudHTTP
    private let authorization: any WorkspaceCloudAuthorization
    public init(http: WorkspaceCloudHTTP, authorization: any WorkspaceCloudAuthorization) { self.http = http; self.authorization = authorization }
    public func teams() async throws -> [WorkspaceTeam] { try await get(["teams"]) }
    public func createTeam(_ name: String) async throws -> WorkspaceTeam {
        struct Input: Encodable { let name: String }; return try await post(["teams"], Input(name: name))
    }
    public func members(_ team: UUID) async throws -> [WorkspaceTeamMember] { try await get(["teams", team.uuidString, "members"]) }
    public func invite(_ team: UUID, email: String, role: String) async throws -> WorkspaceTeamInvite {
        struct Input: Encodable { let email: String; let role: String }; return try await post(["teams", team.uuidString, "invites"], Input(email: email, role: role))
    }
    public func accept(_ token: String) async throws {
        struct Input: Encodable { let token: String }
        try await http.empty(method: "POST", path: root + ["invites", "accept"], body: JSONEncoder().encode(Input(token: token)), accessToken: authorization.accessToken())
    }
    public func removeMember(_ team: UUID, account: UUID) async throws {
        try await http.empty(method: "DELETE", path: root + ["teams", team.uuidString, "members", account.uuidString], accessToken: authorization.accessToken())
    }
    public func bots(_ team: UUID) async throws -> [WorkspaceTeamBot] { try await get(["teams", team.uuidString, "bots"]) }
    public func saveBot(_ team: UUID, id: UUID, version: Int, configuration: WorkspaceTeamBot.Configuration) async throws -> WorkspaceTeamBot {
        struct Input: Encodable { let version: Int; let configuration: WorkspaceTeamBot.Configuration }
        return try await http.request(WorkspaceTeamBot.self, method: "PUT", path: root + ["teams", team.uuidString, "bots", id.uuidString], body: JSONEncoder().encode(Input(version: version, configuration: configuration)), accessToken: authorization.accessToken())
    }
    public func deleteBot(_ bot: WorkspaceTeamBot) async throws {
        try await http.empty(method: "DELETE", path: root + ["teams", bot.teamID.uuidString, "bots", bot.id.uuidString], query: ["version": String(bot.version)], accessToken: authorization.accessToken())
    }
    public func publish(kind: String, title: String, data: Data, days: Int) async throws -> WorkspacePublicationLink {
        guard data.count <= 128_000 else { throw WorkspaceStorageError.invalidParameters }
        struct Input: Encodable { let kind: String; let title: String; let payload: String; let days: Int }
        return try await post(["publications"], Input(kind: kind, title: title, payload: String(decoding: data, as: UTF8.self), days: days))
    }
    public func publications() async throws -> [WorkspacePublicationSummary] { try await get(["publications"]) }
    public func revoke(_ id: UUID) async throws { try await http.empty(method: "DELETE", path: root + ["publications", id.uuidString], accessToken: authorization.accessToken()) }
    public func link(_ publication: WorkspacePublicationLink) async throws -> URL { try await http.publicationURL(publication.token) }
    private var root: [String] { ["v1", "collaboration"] }
    private func get<T: Decodable & Sendable>(_ path: [String]) async throws -> T { try await http.request(T.self, method: "GET", path: root + path, accessToken: authorization.accessToken()) }
    private func post<T: Decodable & Sendable, Input: Encodable>(_ path: [String], _ input: Input) async throws -> T { try await http.request(T.self, method: "POST", path: root + path, body: JSONEncoder().encode(input), accessToken: authorization.accessToken()) }
}
