import BlotDomain
import Foundation

/// Runs on the owner's physical desktop. Outbound claims survive restarts and are never retried blindly.
public actor WorkspaceTeamBotEngine {
    private struct Job: Codable {
        let botID: UUID; let teamID: UUID; let version: Int; let channel: WorkspaceTeamBot.Channel; let messageID: String
        var state: String
    }
    private struct State: Codable { var cursors: [String: String] = [:]; var jobs: [UUID: Job] = [:] }
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let credentials: any WorkspaceCredentialStore
    private let client: WorkspaceCollaborationClient
    private let messaging: WorkspaceMessagingService
    private var worker: _Concurrency.Task<Void, Never>?
    private var state: State?
    private var failure: String?
    private var ticking = false
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, credentials: any WorkspaceCredentialStore, client: WorkspaceCollaborationClient, messaging: WorkspaceMessagingService) {
        self.repository = repository; self.identity = identity; self.credentials = credentials; self.client = client; self.messaging = messaging
    }
    private var key: String { "team-bots:" + identity.ownerID.uuidString + ":" + identity.workspaceID.uuidString + ":" + identity.deviceID.uuidString }
    public func start() {
        guard worker == nil else { return }
        worker = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                await self?.tick()
                do { try await _Concurrency.Task.sleep(for: .seconds(65)) } catch { return }
            }
        }
    }
    public func stop() async { let old = worker; worker = nil; old?.cancel(); await old?.value }
    public func status() -> String? {
        let unknown = state?.jobs.values.filter { $0.state == "unknown" }.count ?? 0
        if unknown > 0 { return "Replies with unknown delivery: \(unknown). Verify the external threads before sending again." }
        return failure
    }
    private func load() async throws {
        guard state == nil else { return }
        var loaded = try await credentials.read(key).map { try JSONDecoder().decode(State.self, from: $0) } ?? State()
        for id in loaded.jobs.keys where loaded.jobs[id]?.state == "posting" { loaded.jobs[id]?.state = "unknown" }
        state = loaded
    }
    private func persist() async throws { try await credentials.write(JSONEncoder().encode(state), name: key) }
    public func tick() async {
        guard !ticking else { return }; ticking = true; defer { ticking = false }
        failure = nil
        do {
            try await load()
            var bots: [WorkspaceTeamBot] = []
            for team in try await client.teams() { bots += try await client.bots(team.id) }
            let active = bots.filter { $0.ownerID == identity.ownerID && $0.configuration.executorDeviceID == identity.deviceID && $0.configuration.enabled }
            for bot in active {
                try _Concurrency.Task.checkCancellation()
                for channel in bot.configuration.channels {
                    do { try await poll(bot, channel: channel) } catch is CancellationError { throw CancellationError() } catch { failure = "Channel access failed. Check app registration, connection, permissions and rate limits." }
                }
            }
            try await deliver(active)
            // Keep a bounded recent ledger. Task IDs retain inbound deduplication after pruning.
            if let state, state.jobs.count > 400 {
                let removable = state.jobs.filter { ["sent", "failed", "canceled"].contains($0.value.state) }.keys
                for id in removable.prefix(state.jobs.count - 400) { self.state?.jobs[id] = nil }
                try await persist()
            }
        } catch is CancellationError {} catch { failure = "Team Bots are waiting for a connection to the cloud service." }
    }
    private func account(_ bot: WorkspaceTeamBot, channel: WorkspaceTeamBot.Channel) async throws -> WorkspaceMessagingAccount {
        guard let id = UUID(uuidString: channel.connectionID), let account = try await messaging.accounts().first(where: { $0.id == id && $0.provider.rawValue == channel.provider }) else { throw WorkspaceStorageError.permissionDenied }
        let projection = try await repository.projection(identity: identity)
        guard try WorkspaceAgentConfigurationResolver().resolve(agentID: bot.configuration.agentID, projection: projection) != nil,
              projection.connections.contains(where: {
                  $0.metadata.id == id && $0.pluginId == channel.provider
                      && WorkspacePluginAccess.isActive($0, deviceID: identity.deviceID, projection: projection)
              }),
              channel.provider != "slack" || channel.workspace == account.workspace else { throw WorkspaceStorageError.permissionDenied }
        return account
    }
    private func poll(_ bot: WorkspaceTeamBot, channel: WorkspaceTeamBot.Channel) async throws {
        let account = try await account(bot, channel: channel)
        let key = bot.id.uuidString + ":" + String(bot.version) + ":" + channel.connectionID + ":" + channel.channel
        guard let cursor = state?.cursors[key] else {
            state?.cursors[key] = channel.provider == "slack" ? String(Date().timeIntervalSince1970) : ISO8601DateFormatter().string(from: Date())
            try await persist(); return
        }
        var events: [(String, String, String)] = []
        if channel.provider == "slack" {
            var next = "", pages = 0
            repeat {
                pages += 1; guard pages <= 10 else { throw MCPError.responseTooLarge }
                let response = try await messaging.request(accountID: account.id, path: ["conversations.history"], query: ["channel": channel.channel, "oldest": cursor, "limit": "100", "cursor": next]).mcpFields
                guard case .array(let messages) = response["messages"] else { throw MCPError.protocolViolation }
                for message in messages {
                    let fields = message.mcpFields
                    guard let id = fields["ts"]?.mcpString, let user = fields["user"]?.mcpString, let text = fields["text"]?.mcpString,
                          fields["bot_id"] == nil, fields["subtype"] == nil, user != account.userID else { continue }
                    events.append((id, user, text))
                }
                next = response["response_metadata"]?.mcpFields["next_cursor"]?.mcpString ?? ""
                guard events.count <= 1000 else { throw MCPError.responseTooLarge }
            } while !next.isEmpty
            events.sort { (Double($0.0) ?? 0) < (Double($1.0) ?? 0) }
        } else {
            let path = ["teams", channel.workspace, "channels", channel.channel, "messages"]
            var next: String?, pages = 0
            repeat {
                pages += 1; guard pages <= 20 else { throw MCPError.responseTooLarge }
                let result: ChatJSON
                if let next { result = try await messaging.nextPage(accountID: account.id, path: path, link: next) }
                else { result = try await messaging.request(accountID: account.id, path: path, query: ["$top": "50"]) }
                let response = result.mcpFields
                guard case .array(let messages) = response["value"] else { throw MCPError.protocolViolation }
                var sawOld = false
                for message in messages {
                    let fields = message.mcpFields
                    guard let id = fields["id"]?.mcpString, let created = fields["createdDateTime"]?.mcpString else { continue }
                    guard Self.date(created) > Self.date(cursor) else { sawOld = true; continue }
                    guard let user = fields["from"]?.mcpFields["user"]?.mcpFields["id"]?.mcpString, user != account.userID,
                          let text = fields["body"]?.mcpFields["content"]?.mcpString else { continue }
                    events.append((created + "|" + id, user, text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)))
                }
                next = sawOld ? nil : response["@odata.nextLink"]?.mcpString
            } while next != nil
            events.sort { Self.date(String($0.0.split(separator: "|").first ?? "")) < Self.date(String($1.0.split(separator: "|").first ?? "")) }
        }
        for (eventID, author, text) in events {
            if text.localizedCaseInsensitiveContains(channel.trigger) {
                guard (state?.jobs.count ?? 0) < 500 else { throw WorkspaceStorageError.invalidParameters }
                let messageID = channel.provider == "teams" ? String(eventID.split(separator: "|").last ?? "") : eventID
                let taskID = try await WorkspaceTeamBotTasks(repository: repository, identity: identity).enqueue(bot: bot, channel: channel, messageID: messageID, author: author, text: String(text.prefix(8000)))
                if state?.jobs[taskID] == nil { state?.jobs[taskID] = .init(botID: bot.id, teamID: bot.teamID, version: bot.version, channel: channel, messageID: messageID, state: "waiting") }
            }
            state?.cursors[key] = channel.provider == "teams" ? String(eventID.split(separator: "|").first ?? "") : eventID
            try await persist()
        }
    }
    private static func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]; return formatter.date(from: value) ?? .distantPast
    }
    private func deliver(_ bots: [WorkspaceTeamBot]) async throws {
        let projection = try await repository.projection(identity: identity), cardMessages = Set(projection.cards.map(\.messageId))
        for (id, job) in state?.jobs ?? [:] where job.state == "waiting" {
            guard let bot = bots.first(where: { $0.id == job.botID && $0.version == job.version }), bot.configuration.channels.contains(job.channel) else {
                state?.jobs[id]?.state = "canceled"; try await persist(); continue
            }
            guard let task = projection.tasks.first(where: { $0.metadata.id == id }) else { continue }
            if [.failed, .canceled].contains(task.state) { state?.jobs[id]?.state = "failed"; try await persist(); continue }
            guard task.state == .completed else { continue }
            let source = WorkspaceTaskLifecycle.sourceID(taskID: id, workspaceID: identity.workspaceID)
            guard let response = WorkspaceMessageOrder.ordered(projection.messages.filter { $0.replyToMessageId == source && $0.role == .assistant && $0.delivery == .completed && !cardMessages.contains($0.metadata.id) }).last,
                  !response.content.isEmpty else { continue }
            guard try await client.bots(bot.teamID).contains(where: { $0.id == bot.id && $0.version == bot.version && $0.configuration.enabled }) else { continue }
            try _Concurrency.Task.checkCancellation()
            let account = try await account(bot, channel: job.channel)
            state?.jobs[id]?.state = "posting"; try await persist()
            do {
                let text = String(response.content.prefix(12_000))
                if job.channel.provider == "slack" {
                    _ = try await messaging.request(accountID: account.id, path: ["chat.postMessage"], body: .object(["channel": .string(job.channel.channel), "thread_ts": .string(job.messageID), "text": .string(text), "unfurl_links": .bool(false), "unfurl_media": .bool(false), "parse": .string("none")]))
                } else {
                    _ = try await messaging.request(accountID: account.id, path: ["teams", job.channel.workspace, "channels", job.channel.channel, "messages", job.messageID, "replies"], body: .object(["body": .object(["contentType": .string("text"), "content": .string(text)])]))
                }
                state?.jobs[id]?.state = "sent"
            } catch { state?.jobs[id]?.state = "unknown"; failure = "A reply has an unknown delivery outcome. Verify the external channel before sending it again." }
            try await persist()
        }
    }
}
