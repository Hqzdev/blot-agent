import BlotDomain
import Foundation

public struct WorkspaceGoogleTools: WorkspaceToolExecuting {
    private let service: WorkspaceGoogleService
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService?
    private let confirm: @Sendable (String, String) async throws -> Bool
    public init(service: WorkspaceGoogleService, repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService? = nil,
                confirm: @escaping @Sendable (String, String) async throws -> Bool) {
        self.service = service; self.repository = repository; self.identity = identity; self.files = files; self.confirm = confirm
    }
    public var definitions: [ChatToolDefinition] {
        let accounts = ChatToolDefinition(name: "google_accounts", description: "List the Google account UUIDs and enabled services assigned to this agent on this device. Call with {}. No tokens are returned.", parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([]), "additionalProperties": .bool(false)]))
        return [accounts] + WorkspaceGoogleCatalog.definitions
    }
    private func eligible(context: WorkspaceToolContext) async throws -> [WorkspaceGoogleAccount] {
        let access = WorkspaceExternalAccess(repository: repository, identity: identity)
        var result: [WorkspaceGoogleAccount] = []
        for account in try await service.accounts() {
            for tool in WorkspaceGoogleCatalog.definitions where WorkspaceGoogleCatalog.plugin(tool.name) == account.plugin && context.allowedToolIDs.contains(tool.name) {
                if (try? await access.authorize(id: account.id, tool: tool.name, operation: WorkspaceGoogleCatalog.operation(tool.name), context: context)) != nil { result.append(account); break }
            }
        }
        return result
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        let accounts = try await eligible(context: context)
        return definitions.filter { definition in definition.name == "google_accounts" ? context.allowedToolIDs.contains(definition.name) && !accounts.isEmpty : context.allowedToolIDs.contains(definition.name) && accounts.contains { $0.plugin == WorkspaceGoogleCatalog.plugin(definition.name) } }
    }
    public func preferredInitialTool(userRequest: String, context: WorkspaceToolContext) async throws -> String? {
        let policy = WorkspaceCapabilityPolicy(userRequest: userRequest)
        guard context.taskID == nil, policy.requestsAction else { return nil }
        let accounts = try await eligible(context: context)
        return accounts.contains { policy.mentions(id: $0.plugin.rawValue, name: $0.plugin.name) } ? "google_accounts" : nil
    }
    public func invalidArgumentsResult(for call: ChatToolCall) -> ChatJSON? {
        guard definitions.contains(where: { $0.name == call.name }) else { return nil }
        return .object(["error": .string("invalid_arguments"), "instructions": .string("No operation was executed. Match the tool schema exactly; omit unused optional fields instead of null. google_accounts accepts {} only. Other Google tools require an actual account_id UUID from google_accounts for the requested service. Correct the arguments and try again.")])
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        if call.name == "google_accounts" {
            return .array(try await eligible(context: context).map { .object(["account_id": .string($0.id.uuidString), "service": .string($0.plugin.rawValue), "email": .string($0.email)]) })
        }
        guard let plugin = WorkspaceGoogleCatalog.plugin(call.name) else { throw WorkspaceToolError.unknownTool }
        guard let raw = call.arguments.mcpFields["account_id"]?.mcpString,
              let id = UUID(uuidString: raw), let account = try await service.accounts().first(where: { $0.id == id && $0.plugin == plugin }) else {
            return .object(["error": .string("account_unavailable"), "instructions": .string("No operation was executed. Use google_accounts to obtain the actual account UUID for this service. Do not invent IDs. If the account was disconnected, ask the owner to reconnect it.")])
        }
        let access = WorkspaceExternalAccess(repository: repository, identity: identity)
        let authorize: @Sendable () async throws -> Void = {
            try await access.authorize(id: id, tool: call.name, operation: WorkspaceGoogleCatalog.operation(call.name), context: context)
        }
        try await authorize()
        let upload: GoogleDriveUpload?
        do { upload = call.name == "drive_create" ? try await makeUpload(call.arguments, context: context) : nil }
        catch WorkspaceToolError.invalidArguments { return invalidArgumentsResult(for: call)! }
        catch WorkspaceStorageError.invalidParameters { return invalidArgumentsResult(for: call)! }
        if !WorkspaceGoogleCatalog.writes(call.name) {
            if try await WorkspaceRuleService(repository: repository, identity: identity).requiresReview(toolID: call.name, resource: id.uuidString, agentID: context.agentID, default: false) {
                guard try await confirm(call.name, String(decoding: WorkspaceCoding.encode(call.arguments), as: UTF8.self)) else { throw WorkspaceStorageError.permissionDenied }
                try await authorize()
            }
            do { return try await perform(call, account: account) }
            catch GoogleOAuthError.authorizationExpired { return .object(["error": .string("authorization_expired")]) }
            catch GoogleOAuthError.invalidScopes { return .object(["error": .string("insufficient_scopes")]) }
            catch GoogleOAuthError.apiNotEnabled { return .object(["error": .string("api_not_enabled")]) }
            catch GoogleOAuthError.accessDenied { return .object(["error": .string("provider_access_denied")]) }
            catch GoogleOAuthError.serviceUnavailable { return .object(["error": .string("service_unavailable")]) }
            catch let error as URLError where error.code != .cancelled { return .object(["error": .string("network_error")]) }
        }
        var content: WorkspaceCardContent = .command(.init(title: plugin.name, details: String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self), command: call.name))
        if let upload {
            let fields = call.arguments.mcpFields
            let folder = upload.parentID ?? "My Drive"
            let value = fields["content"]?.mcpString
            let preview = value.map { String(decoding: Data($0.utf8).prefix(2000), as: UTF8.self) + ($0.utf8.count > 2000 ? "\n… Preview truncated; the full file will be saved." : "") }
                ?? "Attached file · \(upload.data.count) bytes"
            content = .command(.init(title: "Google Drive · " + upload.name,
                details: "Folder: \(folder)\nType: \(upload.mimeType)\nSize: \(upload.data.count) bytes\n\n" + preview, command: call.name))
        }
        if call.name == "gmail_send" {
            let draft = try Self.draft(call.arguments, sender: account.email); _ = try Self.mime(draft)
            content = .email(draft)
        }
        return try await WorkspaceExternalReview(repository: repository, identity: identity, confirm: confirm).run(call: call, context: context,
            resource: id.uuidString, content: content, authorize: authorize) { response in
                var input = call
                if call.name == "gmail_send", let raw = response?.value {
                    let draft = try JSONDecoder().decode(WorkspaceCardContent.MailDraft.self, from: Data(raw.utf8)); _ = try Self.mime(draft)
                    guard draft.sender == account.email else { throw WorkspaceStorageError.invalidParameters }
                    var fields = call.arguments.mcpFields
                    fields["recipient"] = .string(draft.recipient); fields["subject"] = .string(draft.subject); fields["body"] = .string(draft.body)
                    input = .init(id: call.id, name: call.name, arguments: .object(fields))
                }
                if let upload { return try await service.upload(accountID: id, file: upload) }
                return try await perform(input, account: account)
            }
    }
    private func makeUpload(_ arguments: ChatJSON, context: WorkspaceToolContext) async throws -> GoogleDriveUpload {
        let fields = arguments.mcpFields
        guard let name = fields["name"]?.mcpString,
              (fields["content"] != nil) != (fields["artifact_id"] != nil) else { throw WorkspaceToolError.invalidArguments }
        let data: Data, type: String
        if let raw = fields["artifact_id"]?.mcpString {
            guard let id = UUID(uuidString: raw), let files,
                  let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
                  source.artifactIds.contains(id),
                  let artifact = try await repository.record(BlotV3.Artifact.self, id: id, workspaceID: identity.workspaceID),
                  artifact.metadata.ownerId == identity.ownerID, artifact.byteCount <= GoogleDriveUpload.maximumBytes,
                  fields["mime_type"] == nil || fields["mime_type"] == .string(artifact.mediaType) else { throw WorkspaceStorageError.permissionDenied }
            data = try await files.data(for: id); type = artifact.mediaType
        } else {
            guard let text = fields["content"]?.mcpString, text.utf8.count <= 32 * 1024 else { throw WorkspaceToolError.invalidArguments }
            type = fields["mime_type"]?.mcpString ?? "text/plain"
            guard ["text/plain", "text/markdown", "text/csv", "text/html", "application/json", "application/xml"].contains(type) else { throw WorkspaceToolError.invalidArguments }
            data = Data(text.utf8)
        }
        return try .init(name: name, mimeType: type, parentID: fields["parent_id"]?.mcpString, data: data)
    }
    private func perform(_ call: ChatToolCall, account: WorkspaceGoogleAccount) async throws -> ChatJSON {
        let fields = call.arguments.mcpFields, id = account.id
        func text(_ name: String) throws -> String {
            guard let value = fields[name]?.mcpString, !value.isEmpty, value.utf8.count <= 48_000 else { throw WorkspaceStorageError.invalidParameters }; return value
        }
        func page() -> [String: String] { fields["next_page"]?.mcpString.map { ["pageToken": $0] } ?? [:] }
        switch call.name {
        case "gmail_check_access":
            try await service.verifyAccount(id)
            return .object(["state": .string("verified"), "email": .string(account.email)])
        case "gmail_recent":
            let limit = fields["limit"]?.mcpString ?? "5"
            guard let count = Int(limit), (1...20).contains(count) else { throw WorkspaceToolError.invalidArguments }
            return try await recentMail(accountID: id, limit: count)
        case "gmail_search":
            var query = page(); query["q"] = try text("query"); query["maxResults"] = "50"
            return try await service.request(accountID: id, host: "gmail.googleapis.com", path: ["gmail", "v1", "users", "me", "messages"], query: query)
        case "gmail_read": return try await service.request(accountID: id, host: "gmail.googleapis.com", path: ["gmail", "v1", "users", "me", "messages", text("message_id")], query: ["format": "full"])
        case "gmail_draft", "gmail_send":
            let raw = try Self.mime(Self.draft(call.arguments, sender: account.email))
            return try await service.request(accountID: id, host: "gmail.googleapis.com", path: ["gmail", "v1", "users", "me"] + (call.name == "gmail_draft" ? ["drafts"] : ["messages", "send"]), method: "POST",
                body: call.name == "gmail_draft" ? .object(["message": .object(["raw": .string(raw)])]) : .object(["raw": .string(raw)]))
        case "calendar_list":
            return try await service.request(accountID: id, path: ["calendar", "v3", "users", "me", "calendarList"], query: page())
        case "calendar_events":
            var query = page(); query["timeMin"] = try text("time_min"); query["timeMax"] = try text("time_max"); query["maxResults"] = "100"; query["singleEvents"] = "true"; query["orderBy"] = "startTime"
            return try await service.request(accountID: id, path: ["calendar", "v3", "calendars", text("calendar_id"), "events"], query: query)
        case "calendar_create", "calendar_update":
            let start = try text("start"), end = try text("end"), formatter = ISO8601DateFormatter()
            guard let first = formatter.date(from: start), let last = formatter.date(from: end), last > first else { throw WorkspaceStorageError.invalidParameters }
            let body: ChatJSON = .object(["summary": .string(try text("title")), "description": .string(fields["description"]?.mcpString ?? ""), "start": .object(["dateTime": .string(start)]), "end": .object(["dateTime": .string(end)])])
            let update = call.name == "calendar_update"
            return try await service.request(accountID: id, path: ["calendar", "v3", "calendars", text("calendar_id"), "events"] + (update ? [try text("event_id")] : []), query: ["sendUpdates": "none"], method: update ? "PATCH" : "POST", body: body, etag: update ? try text("etag") : nil)
        case "drive_search":
            var query = page(); query["pageSize"] = "100"; query["fields"] = "nextPageToken,files(id,name,mimeType,modifiedTime,webViewLink)"; query["q"] = fields["query"]?.mcpString ?? "trashed = false"
            return try await service.request(accountID: id, path: ["drive", "v3", "files"], query: query)
        case "drive_read":
            let type = try text("mime_type"), native = ["application/vnd.google-apps.document": "text/plain", "application/vnd.google-apps.spreadsheet": "text/csv"]
            guard native[type] != nil || ["text/plain", "text/csv", "text/markdown", "application/json"].contains(type) else { throw WorkspaceStorageError.invalidParameters }
            return try await service.request(accountID: id, path: ["drive", "v3", "files", text("file_id")] + (native[type] == nil ? [] : ["export"]), query: native[type].map { ["mimeType": $0] } ?? ["alt": "media"], text: true)
        default: throw WorkspaceToolError.unknownTool
        }
    }
    private func recentMail(accountID: UUID, limit: Int) async throws -> ChatJSON {
        let host = "gmail.googleapis.com", path = ["gmail", "v1", "users", "me", "messages"]
        let listing = try await service.request(accountID: accountID, host: host, path: path,
            query: ["q": "in:inbox", "maxResults": String(limit)])
        guard case .object(let inbox) = listing else { throw GoogleOAuthError.serviceUnavailable }
        guard let matchingMessages = inbox["messages"] else { return .array([]) }
        guard case .array(let messages) = matchingMessages else { throw GoogleOAuthError.serviceUnavailable }
        var summaries: [ChatJSON] = []
        for message in messages.prefix(limit) {
            guard let id = message.mcpFields["id"]?.mcpString else { throw GoogleOAuthError.serviceUnavailable }
            let detail = try await service.request(accountID: accountID, host: host, path: path + [id],
                query: ["format": "full", "fields": "id,threadId,snippet,internalDate,payload(headers)"])
            let fields = detail.mcpFields
            var summary = fields.filter { ["id", "threadId", "snippet", "internalDate"].contains($0.key) }
            if case .array(let headers) = fields["payload"]?.mcpFields["headers"] {
                for header in headers {
                    guard let key = header.mcpFields["name"]?.mcpString?.lowercased(),
                          ["from", "subject", "date"].contains(key), let value = header.mcpFields["value"] else { continue }
                    summary[key] = value
                }
            }
            summaries.append(.object(summary))
        }
        return .array(summaries)
    }
    private static func draft(_ arguments: ChatJSON, sender: String) throws -> WorkspaceCardContent.MailDraft {
        let fields = arguments.mcpFields
        guard let recipient = fields["recipient"]?.mcpString, let subject = fields["subject"]?.mcpString, let body = fields["body"]?.mcpString else { throw WorkspaceStorageError.invalidParameters }
        return .init(sender: sender, recipient: recipient, subject: subject, body: body)
    }
    static func mime(_ draft: WorkspaceCardContent.MailDraft) throws -> String {
        let header = [draft.sender, draft.recipient, draft.subject]
        guard header.allSatisfy({ !$0.contains(where: { $0.isNewline || $0 == "\0" }) && $0.utf8.count <= 800 }), draft.body.utf8.count <= 48_000,
              [draft.sender, draft.recipient].allSatisfy({ $0.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil }) else { throw WorkspaceStorageError.invalidParameters }
        let body = Data(draft.body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let message = "From: " + draft.sender + "\r\nTo: " + draft.recipient + "\r\nSubject: =?UTF-8?B?" + Data(draft.subject.utf8).base64EncodedString() + "?=\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n" + body
        return Data(message.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
