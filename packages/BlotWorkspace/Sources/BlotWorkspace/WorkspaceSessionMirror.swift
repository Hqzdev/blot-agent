import BlotDomain
import CryptoKit
import Foundation

/// Mirrors changed final records, never complete database backups or streamed tokens.
public actor WorkspaceSessionMirror {
    private struct Entry: Codable, Equatable {
        let type: String
        let conversation: UUID
        let record: UUID
        let hash: String
    }
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceSessionFileService
    private let indexURL: URL
    private let artifacts: WorkspaceFileService?
    private var index: [String: Entry] = [:]
    private var loaded = false
    private var messages: [UUID: BlotV3.Message] = [:]
    private var conversations: [UUID: BlotV3.Conversation] = [:]
    private var observation: _Concurrency.Task<Void, Never>?
    public private(set) var lastError: String?
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceSessionFileService, indexURL: URL, artifacts: WorkspaceFileService? = nil) {
        self.repository = repository; self.identity = identity; self.files = files; self.indexURL = indexURL
        self.artifacts = artifacts
    }
    public func start() {
        guard observation == nil else { return }
        observation = _Concurrency.Task { [weak self, repository] in
            await self?.synchronize()
            for await _ in await repository.changes() {
                do { try await _Concurrency.Task.sleep(for: .milliseconds(400)); try _Concurrency.Task.checkCancellation() } catch { return }
                await self?.synchronize()
            }
        }
    }
    public func stop(flush: Bool = false) async {
        observation?.cancel(); await observation?.value; observation = nil
        if flush { await synchronize() }
    }
    public func synchronize() async {
        do { try await update(); lastError = nil }
        catch is CancellationError {}
        catch { lastError = "Не удалось сохранить историю сессии в папке Blot. Данные чата сохранены в приложении." }
    }
    private func update() async throws {
        try _Concurrency.Task.checkCancellation()
        if !loaded {
            if let data = try? Data(contentsOf: indexURL), data.count <= 16 * 1024 * 1024 { index = (try? WorkspaceCoding.decode([String: Entry].self, from: data)) ?? [:] }
            loaded = true
        }
        let projection = try await repository.projection(identity: identity)
        let previous = index
        var live: Set<String> = []
        for conversation in projection.conversations {
            let key = "conversation/" + conversation.metadata.id.uuidString
            live.insert(key)
            if conversations[conversation.metadata.id] != conversation {
                try await save(conversation, key: key, type: "conversation", conversation: conversation.metadata.id, id: conversation.metadata.id)
                conversations[conversation.metadata.id] = conversation
            }
        }
        let activeChats = Set(projection.conversations.map(\.metadata.id))
        for message in projection.messages where activeChats.contains(message.conversationId) {
            let key = "message/" + message.metadata.id.uuidString
            live.insert(key)
            guard message.delivery != .running else { continue }
            if messages[message.metadata.id] != message {
                try await save(message, key: key, type: "message", conversation: message.conversationId, id: message.metadata.id)
                messages[message.metadata.id] = message
            }
        }
        if let artifacts {
            let byID = Dictionary(uniqueKeysWithValues: projection.artifacts.map { ($0.metadata.id, $0) })
            for message in projection.messages where activeChats.contains(message.conversationId) {
                for id in message.artifactIds {
                    guard let artifact = byID[id] else { continue }
                    let key = "artifact/" + message.conversationId.uuidString + "/" + id.uuidString
                    live.insert(key)
                    if index[key]?.hash == artifact.hash { continue }
                    guard let source = try? await artifacts.url(for: id) else { continue }
                    try _Concurrency.Task.checkCancellation()
                    var arguments = parameters(.init(type: "artifact", conversation: message.conversationId, record: id, hash: artifact.hash))
                    let sanitized = String(artifact.name.filter { $0 != "/" && $0 != "\\" && $0 != "\0" })
                    let fileExtension = (sanitized as NSString).pathExtension
                    let suffix = fileExtension.isEmpty || fileExtension.utf8.count > 16 ? "" : "." + fileExtension
                    var stem = suffix.isEmpty ? sanitized : (sanitized as NSString).deletingPathExtension
                    while stem.utf8.count + suffix.utf8.count > 180 { stem.removeLast() }
                    let safeName = stem + suffix
                    arguments["name"] = safeName.isEmpty || safeName == "." || safeName == ".." ? "file" : safeName
                    arguments["source"] = source.standardizedFileURL.resolvingSymlinksInPath().path
                    arguments["hash"] = artifact.hash; arguments["expected_hash"] = index[key]?.hash ?? "missing"
                    _ = try await files.request(.workspaceCopyArtifact, root: "/", parameters: arguments)
                    index[key] = .init(type: "artifact", conversation: message.conversationId, record: id, hash: artifact.hash)
                }
            }
        }
        for key in Set(index.keys).subtracting(live) {
            guard let entry = index[key] else { continue }
            if entry.type != "artifact" { _ = try await files.request(.workspaceRemoveRecord, root: "/", parameters: parameters(entry)) }
            index[key] = nil; messages[entry.record] = nil; conversations[entry.record] = nil
        }
        if previous != index {
            try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try WorkspaceCoding.encode(index).write(to: indexURL, options: .atomic)
        }
    }
    private func save<Value: Encodable>(_ value: Value, key: String, type: String, conversation: UUID, id: UUID) async throws {
        try _Concurrency.Task.checkCancellation()
        let data = try WorkspaceCoding.encode(value)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if index[key]?.hash == hash { return }
        let entry = Entry(type: type, conversation: conversation, record: id, hash: hash)
        var arguments = parameters(entry); arguments["record"] = String(decoding: data, as: UTF8.self)
        _ = try await files.request(.workspaceRecord, root: "/", parameters: arguments)
        index[key] = entry
    }
    private func parameters(_ entry: Entry) -> [String: String] {
        ["owner_id": identity.ownerID.uuidString, "workspace_id": identity.workspaceID.uuidString,
         "conversation_id": entry.conversation.uuidString, "record_id": entry.record.uuidString, "record_type": entry.type]
    }
}
