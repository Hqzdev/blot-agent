import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor GoogleTestCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

private final class GoogleTestProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private final class Routes: @unchecked Sendable {
        let lock = NSLock()
        var handlers: [String: Handler] = [:]
    }
    private static let routes = Routes()
    static func session(handler: @escaping Handler) -> (String, URLSession) {
        let key = UUID().uuidString
        routes.lock.withLock { routes.handlers[key] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Self.self]; config.httpAdditionalHeaders = ["X-Blot-Test": key]
        return (key, URLSession(configuration: config))
    }
    static func remove(_ key: String) { _ = routes.lock.withLock { routes.handlers.removeValue(forKey: key) } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let key = request.value(forHTTPHeaderField: "X-Blot-Test") ?? ""
            guard let handler = Self.routes.lock.withLock({ Self.routes.handlers[key] }), let url = request.url else { throw URLError(.badURL) }
            let result = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.1); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class GoogleRequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [(String, String, Data)] = []
    private var failing = false
    private var disabled = false
    var uploadFails: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }
    var apiDisabled: Bool {
        get { lock.withLock { disabled } }
        set { lock.withLock { disabled = newValue } }
    }
    func record(_ request: URLRequest) throws -> (Int, Data) {
        let url = try #require(request.url)
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(buffer, count: count)
            }
        }
        lock.withLock { requests.append((request.httpMethod ?? "GET", url.path, data)) }
        func json(_ value: [String: Any]) throws -> (Int, Data) { (200, try JSONSerialization.data(withJSONObject: value)) }
        if url.path == "/token" {
            return try json(["access_token": "test-access", "refresh_token": "test-refresh", "expires_in": 3600,
                "token_type": "Bearer", "scope": GoogleAccess.allCases.map(\.scope).joined(separator: " ")])
        }
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
        switch url.path {
        case "/v1/userinfo": return try json(["email": "qa@example.com", "email_verified": true])
        case "/gmail/v1/users/me/profile": return try json(["emailAddress": "qa@example.com"])
        case "/drive/v3/about":
            if apiDisabled { return (403, try JSONSerialization.data(withJSONObject: ["error": ["details": [["reason": "SERVICE_DISABLED"]]]])) }
            return try json(["user": ["emailAddress": "qa@example.com"]])
        case "/gmail/v1/users/me/messages": return try json(["messages": [["id": "mail-1"]]])
        case "/gmail/v1/users/me/messages/mail-1": return try json(["id": "mail-1", "snippet": "Synthetic test mail"])
        case "/gmail/v1/users/me/drafts": return try json(["id": "draft-1"])
        case "/gmail/v1/users/me/messages/send": return try json(["id": "sent-1"])
        case "/calendar/v3/users/me/calendarList": return try json(["items": [["id": "primary", "accessRole": "owner"]]])
        case "/calendar/v3/calendars/primary/events":
            return try json(request.httpMethod == "POST" ? ["id": "event-1"] : ["items": [["id": "event-1", "etag": "etag-1"]]])
        case "/calendar/v3/calendars/primary/events/event-1":
            #expect(request.value(forHTTPHeaderField: "If-Match") == "etag-1")
            return try json(["id": "event-1", "etag": "etag-2"])
        case "/drive/v3/files/folder-1": return try json(["id": "folder-1", "mimeType": "application/vnd.google-apps.folder", "capabilities": ["canAddChildren": true]])
        case "/drive/v3/files": return try json(["files": [["id": "saved-1", "name": "QA-report.md", "mimeType": "text/markdown"]]])
        case "/drive/v3/files/saved-1": return (200, Data("# QA\nSynthetic report".utf8))
        case "/upload/drive/v3/files":
            if uploadFails { throw URLError(.networkConnectionLost) }
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/related; boundary=") == true)
            #expect(String(decoding: data, as: UTF8.self).contains("Synthetic report"))
            return try json(["id": "saved-1", "name": "QA-report.md", "webViewLink": "https://drive.google.com/file/d/saved-1/view"])
        default: Issue.record("Unexpected Google request: \(url.path)"); throw URLError(.badURL)
        }
    }
    func count(_ path: String) -> Int { lock.withLock { requests.filter { $0.1 == path }.count } }
}

private struct GoogleWorkspaceFixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let agent: UUID
    let source: UUID
    let files: WorkspaceFileService
    let service: WorkspaceGoogleService
    let log = GoogleRequestLog()
    let session: URLSession
    let route: String
    init() async throws {
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("google.sqlite"))
        identity = try await repository.localIdentity()
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Google QA", instructions: "Test integrations"))
        let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Google QA", agentID: agent)
        source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat,
            content: "Create and save a synthetic report, a draft and a test calendar event. Send only synthetic test mail.")
        files = WorkspaceFileService(repository: repository, identity: identity, directory: folder.appendingPathComponent("files"))
        let log = self.log
        (route, session) = GoogleTestProtocol.session { try log.record($0) }
        service = WorkspaceGoogleService(repository: repository, identity: identity, credentials: GoogleTestCredentials(), session: session)
    }
    func connect(_ plugin: WorkspaceGooglePlugin) async throws -> UUID {
        let configuration = try GoogleOAuthConfiguration(clientID: "123-test.apps.googleusercontent.com", redirectURI: URL(string: "com.googleusercontent.apps.123-test:/oauthredirect")!)
        let authorization = try GoogleOAuthAuthorization(configuration: configuration, access: plugin.access)
        let state = URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
        try await service.connect(plugin: plugin, authorization: authorization, callback: URL(string: configuration.redirectURI.absoluteString + "?state=\(state)&code=test")!)
        return try #require(try await service.accounts().first { $0.plugin == plugin }?.id)
    }
    var tools: WorkspaceGoogleTools { .init(service: service, repository: repository, identity: identity, files: files, confirm: { _, _ in true }) }
    var context: WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil, allowedToolIDs: Set(WorkspaceGoogleCatalog.definitions.map(\.name) + ["google_accounts"]), agentID: agent) }
    func call(_ name: String, account: UUID, fields: [String: String] = [:], id: String = UUID().uuidString) async throws -> ChatJSON {
        try await tools.execute(.init(id: id, name: name, arguments: .object(fields.mapValues(ChatJSON.string).merging(["account_id": .string(account.uuidString)]) { $1 })), context: context)
    }
    func clean() { session.invalidateAndCancel(); GoogleTestProtocol.remove(route); cleanupWorkspaceTestStorage(folder) }
}

@Test func googleWorkspaceOAuthAndMailCalendarDriveUseGrantedAccounts() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let gmail = try await f.connect(.gmail), calendar = try await f.connect(.calendar), drive = try await f.connect(.drive)
    #expect(try await f.call("gmail_search", account: gmail, fields: ["query": "subject:QA"]).mcpFields["messages"] != nil)
    #expect(try await f.call("gmail_read", account: gmail, fields: ["message_id": "mail-1"]).mcpFields["id"] == .string("mail-1"))
    let mail = ["recipient": "qa@example.com", "subject": "QA", "body": "Synthetic test mail"]
    #expect(try await f.call("gmail_draft", account: gmail, fields: mail).mcpFields["id"] == .string("draft-1"))
    #expect(try await f.call("gmail_send", account: gmail, fields: mail).mcpFields["id"] == .string("sent-1"))
    _ = try await f.call("calendar_list", account: calendar)
    _ = try await f.call("calendar_events", account: calendar, fields: ["calendar_id": "primary", "time_min": "2026-11-20T10:00:00+05:00", "time_max": "2026-11-21T10:00:00+05:00"])
    let event = ["calendar_id": "primary", "title": "QA", "start": "2026-11-20T10:00:00+05:00", "end": "2026-11-20T10:10:00+05:00"]
    _ = try await f.call("calendar_create", account: calendar, fields: event)
    _ = try await f.call("calendar_update", account: calendar, fields: event.merging(["event_id": "event-1", "etag": "etag-1"]) { $1 })
    let upload = ["name": "QA-report.md", "content": "# QA\nSynthetic report", "mime_type": "text/markdown", "parent_id": "folder-1"]
    let result = try await f.call("drive_create", account: drive, fields: upload, id: "upload")
    #expect(result.mcpFields["id"] == .string("saved-1"))
    #expect(try await f.call("drive_create", account: drive, fields: upload, id: "upload") == result)
    #expect(f.log.count("/upload/drive/v3/files") == 1)
    _ = try await f.call("drive_search", account: drive)
    #expect(try await f.call("drive_read", account: drive, fields: ["file_id": "saved-1", "mime_type": "text/markdown"]).mcpFields["content"] == .string("# QA\nSynthetic report"))
    try await f.service.disconnect(drive)
    #expect(try await f.call("drive_search", account: drive).mcpFields["error"] == .string("account_unavailable"))
}

@Test func googleDriveUnknownUploadCannotReplayAndUnattachedFilesAreDenied() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let drive = try await f.connect(.drive)
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        _ = try await f.call("drive_create", account: drive, fields: ["name": "private.pdf", "artifact_id": UUID().uuidString])
    }
    #expect(f.log.count("/upload/drive/v3/files") == 0)
    f.log.uploadFails = true
    let fields = ["name": "QA-report.md", "content": "Synthetic report"]
    await #expect(throws: (any Error).self) { _ = try await f.call("drive_create", account: drive, fields: fields, id: "lost-upload") }
    await #expect(throws: NativeExecutionError.unknown) { _ = try await f.call("drive_create", account: drive, fields: fields, id: "lost-upload") }
    #expect(f.log.count("/upload/drive/v3/files") == 1)
}

@Test func driveUploadRejectsHeaderInjectionAndOversizedFiles() throws {
    #expect(throws: WorkspaceStorageError.invalidParameters) { try GoogleDriveUpload(name: "report", mimeType: "text/plain\r\nInjected: true", parentID: nil, data: Data()) }
    #expect(throws: WorkspaceStorageError.invalidParameters) { try GoogleDriveUpload(name: "report", mimeType: "text/plain", parentID: "../file", data: Data()) }
    #expect(throws: WorkspaceStorageError.invalidParameters) { try GoogleDriveUpload(name: "report", mimeType: "text/plain", parentID: nil, data: Data(repeating: 0, count: GoogleDriveUpload.maximumBytes + 1)) }
}

@Test func googleSchemaErrorsAreRepairableWithoutCallingTheProvider() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let drive = try await f.connect(.drive)
    let registry = try WorkspaceToolRegistry(providers: [f.tools])
    #expect(try await registry.preferredInitialTool(userRequest: "Сохрани отчёт в Google Drive", context: f.context,
        available: Set(f.tools.definitions.map(\.name))) == "google_accounts")
    #expect(try await registry.preferredInitialTool(userRequest: "Проверь тестовый файл в Google Drive", context: f.context,
        available: Set(f.tools.definitions.map(\.name))) == "google_accounts")
    let invalid = ChatToolCall(id: "invalid", name: "drive_create", arguments: .object([
        "account_id": .string(drive.uuidString), "name": .string("QA-report.md"), "content": .string("Synthetic report"), "parent_id": .null]))
    let result = try await registry.execute(invalid, context: f.context)
    #expect(result.mcpFields["error"] == .string("invalid_arguments"))
    #expect(f.log.count("/upload/drive/v3/files") == 0)
    #expect(try await f.repository.projection(identity: f.identity).actions.isEmpty)
    let bootstrap = WorkspaceCapabilityPolicy(userRequest: "Сохрани отчёт в Google Drive")
    #expect(bootstrap.requiredTool(initial: "google_accounts", results: [("google_accounts", result)]) == "google_accounts")
    let accounts = try await registry.execute(.init(id: "accounts", name: "google_accounts", arguments: .object([:])), context: f.context)
    #expect(bootstrap.requiredTool(initial: "google_accounts", results: [("google_accounts", accounts)]) == nil)
    _ = try await f.call("drive_create", account: drive, fields: ["name": "QA-report.md", "content": "Synthetic report"])
    #expect(f.log.count("/upload/drive/v3/files") == 1)
}

@Test func disabledGoogleAPIAndCanceledConnectionNeverGrantAgentAccess() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    f.log.apiDisabled = true
    await #expect(throws: GoogleOAuthError.apiNotEnabled) { _ = try await f.connect(.drive) }
    #expect(try await f.service.accounts().isEmpty)
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
    let gate = AsyncStream<Void>.makeStream()
    let repository = f.repository, identity = f.identity
    let task = _Concurrency.Task {
        for await _ in gate.stream { break }
        try await WorkspaceExternalAccess(repository: repository, identity: identity).save(id: UUID(), plugin: "drive", service: "Drive", account: "qa@example.com", scopes: ["create"])
    }
    task.cancel(); gate.continuation.finish()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
}

@Test func driveUploadsOnlyCurrentAttachmentAndDeniedReviewMakesNoRequest() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let drive = try await f.connect(.drive)
    let artifact = try await f.files.store(commandID: UUID(), name: "QA-report.txt", mediaType: "text/plain", data: Data("Synthetic report".utf8))
    let source = try #require(try await f.repository.projection(identity: f.identity).messages.first { $0.metadata.id == f.source })
    let message = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(),
        conversationID: source.conversationId, content: "Save only this attached QA report to Drive.", artifactIDs: [artifact])
    let context = WorkspaceToolContext(sourceMessageID: message, taskID: nil, allowedToolIDs: f.context.allowedToolIDs, agentID: f.agent)
    let call = ChatToolCall(id: "attachment", name: "drive_create", arguments: .object([
        "account_id": .string(drive.uuidString), "name": .string("QA-report.txt"), "artifact_id": .string(artifact.uuidString)]))
    let denied = WorkspaceGoogleTools(service: f.service, repository: f.repository, identity: f.identity, files: f.files, confirm: { _, _ in false })
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await denied.execute(call, context: context) }
    #expect(f.log.count("/upload/drive/v3/files") == 0)
    let accepted = ChatToolCall(id: "attachment-approved", name: call.name, arguments: call.arguments)
    #expect(try await f.tools.execute(accepted, context: context).mcpFields["id"] == .string("saved-1"))
    #expect(f.log.count("/upload/drive/v3/files") == 1)
}

@Test func connectedGooglePluginIsAvailableToExistingAndNewAgents() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let agents = WorkspaceAgentService(repository: f.repository, identity: f.identity)
    let existing = try await agents.save(commandID: UUID(), draft: .init(name: "Existing", instructions: "Help"))
    let drive = try await f.connect(.drive)
    let added = try await agents.save(commandID: UUID(), draft: .init(name: "New", instructions: "Help"))
    let chat = WorkspaceChatService(repository: f.repository, identity: f.identity)
    let registry = try WorkspaceToolRegistry(providers: [f.tools])

    for agent in [f.agent, existing, added] {
        let conversation = try await chat.createConversation(commandID: UUID(), title: "Drive", agentID: agent)
        let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "List my Google Drive files")
        let projection = try await f.repository.projection(identity: f.identity)
        let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: agent, projection: projection))
        #expect(configuration.toolIds.isEmpty)
        let allowed = registry.assignedToolIDs(configuration: configuration, projection: projection, deviceID: f.identity.deviceID)
        let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: allowed, agentID: agent)
        #expect(try await registry.availableDefinitions(context: context).contains { $0.name == "drive_search" })
        let accounts = try await registry.execute(.init(id: "accounts", name: "google_accounts", arguments: .object([:])), context: context)
        #expect(accounts == .array([.object(["account_id": .string(drive.uuidString), "service": .string("drive"), "email": .string("qa@example.com")])]))
    }
    try await f.service.disconnect(drive)
    #expect(try await registry.availableDefinitions(context: f.context).isEmpty)
}

private struct GmailReadModel: ChatModel {
    let account: UUID
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            switch request.requiredTool {
            case "google_accounts":
                continuation.yield(.toolCall(.init(id: "discover", name: "google_accounts", arguments: .object([:]))))
                continuation.yield(.finished(.toolCalls))
            case "gmail_recent":
                #expect(request.messages.contains { $0.content.contains("Callable commands for this turn are gmail_recent") })
                continuation.yield(.toolCall(.init(id: "recent", name: "gmail_recent",
                    arguments: .object(["account_id": .string(account.uuidString), "limit": .string("5")]))))
                continuation.yield(.finished(.toolCalls))
            default:
                #expect(request.messages.contains { $0.role == "tool" && $0.content.contains("Synthetic test mail") })
                continuation.yield(.text("Synthetic test mail"))
                continuation.yield(.finished(.stop))
            }
            continuation.finish()
        }
    }
}

@Test func ordinaryInboxRequestAndRetryDiscoverAndReadGmail() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let account = try await f.connect(.gmail)
    let original = try #require(try await f.repository.record(BlotV3.Message.self, id: f.source, workspaceID: f.identity.workspaceID))
    let chat = WorkspaceChatService(repository: f.repository, identity: f.identity)
    let configuration = try #require(try WorkspaceAgentConfigurationResolver().resolve(agentID: f.agent,
        projection: try await f.repository.projection(identity: f.identity)))
    let runtime = WorkspaceModelRuntime(repository: f.repository, identity: f.identity, pool: .init(),
        tools: try .init(providers: [f.tools]))
    let prompt = "привет посмотри мою почту напиши 5 последних писем"
    for messages in [[prompt], [prompt, "а сейчас"], [prompt, "а сейчас", "к gmail посмотри"]] {
        let sourceID = try await chat.sendMessage(commandID: UUID(), conversationID: original.conversationId, content: try #require(messages.last))
        let source = try #require(try await f.repository.record(BlotV3.Message.self, id: sourceID, workspaceID: f.identity.workspaceID))
        let response = try await WorkspaceResponseRecorder(repository: f.repository, identity: f.identity)
            .begin(id: UUID(), replyingTo: source, agentID: f.agent)
        try await runtime.generate(source: source, responseID: response.metadata.id,
            request: .init(messages: messages.map { .init(role: "user", content: $0) }, maximumOutputTokens: 128),
            model: GmailReadModel(account: account), modelID: "compatible", configuration: configuration, budgetTokenLimit: 100_000, emit: { _ in })
    }
    #expect(f.log.count("/gmail/v1/users/me/messages") == 3)
    #expect(f.log.count("/gmail/v1/users/me/messages/mail-1") == 3)
}

@Test func gmailAccessCheckVerifiesProfileWithoutReadingInbox() async throws {
    let f = try await GoogleWorkspaceFixture(); defer { f.clean() }
    let account = try await f.connect(.gmail)
    let verification = try await f.call("gmail_check_access", account: account)
    #expect(verification.mcpFields["state"] == .string("verified"))
    #expect(f.log.count("/gmail/v1/users/me/profile") == 2)
    #expect(f.log.count("/gmail/v1/users/me/messages") == 0)
    let request = try #require(WorkspaceMailRequest("проверь доступ к Gmail"))
    let available: Set<String> = ["google_accounts", "gmail_check_access", "gmail_recent", "plugin_catalog"]
    #expect(request.requiredTool(available: available, results: []) == "google_accounts")
    let accounts: ChatJSON = .array([.object(["service": .string("gmail"), "email": .string("qa@example.com")])])
    #expect(request.requiredTool(available: available, results: [("google_accounts", accounts)]) == "gmail_check_access")
    #expect(request.requiredTool(available: ["plugin_catalog"], results: []) == "plugin_catalog")
}
