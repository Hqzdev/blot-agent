import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private final class DecodeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private struct CountedMessage: BlotWorkspaceRecord {
    static let counter = DecodeCounter()
    static let recordKind = "Message"
    let message: BlotV3.Message
    var metadata: BlotV3.RecordMetadata { message.metadata }
    init(from decoder: Decoder) throws { message = try BlotV3.Message(from: decoder); Self.counter.increment() }
    func encode(to encoder: Encoder) throws { try message.encode(to: encoder) }
}

@Test func recordReadsReuseDecodedContentButNeverHideReplacementRollbackOrDeletion() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(folder) }
    let database = try SQLiteDatabase(url: folder.appendingPathComponent("cache.sqlite"))
    defer { try? database.close() }
    let store = WorkspaceRecordStore(database: database)
    let owner = UUID(), workspace = UUID(), conversation = UUID(), now = Date()
    var messages: [BlotV3.Message] = []
    try database.transaction {
        for index in 0..<1000 {
            let metadata = try BlotV3.RecordMetadata(id: UUID(), ownerId: owner, workspaceId: workspace, version: 1, createdAt: now, updatedAt: now)
            let message = try BlotV3.Message(metadata: metadata, conversationId: conversation, role: .assistant,
                content: "Message \(index) " + String(repeating: "history ", count: 80), delivery: .completed, commandId: UUID(), artifactIds: [])
            let payload = String(decoding: try WorkspaceCoding.encode(message), as: UTF8.self)
            try database.execute("INSERT INTO records(kind,id,workspace_id,version,payload,deleted) VALUES ('Message',?,?,1,?,0)",
                [.text(metadata.id.uuidString), .text(workspace.uuidString), .text(payload)])
            messages.append(message)
        }
    }
    let before = CountedMessage.counter.value
    let first = try store.records(CountedMessage.self, workspaceID: workspace)
    let warm = CountedMessage.counter.value
    for _ in 0..<8 { #expect(try store.records(CountedMessage.self, workspaceID: workspace) == first) }
    #expect(warm - before == 1000)
    #expect(CountedMessage.counter.value == warm)
    let clock = ContinuousClock()
    let cold = clock.now
    for _ in 0..<8 {
        let rows = try database.query("SELECT payload FROM records WHERE kind = 'Message' AND workspace_id = ? AND deleted = 0 ORDER BY rowid", [.text(workspace.uuidString)]) {
            try WorkspaceCoding.decode(BlotV3.Message.self, from: Data(SQLiteDatabase.text($0, 0).utf8))
        }
        #expect(rows.count == 1000)
    }
    let uncached = cold.duration(to: clock.now)
    let hot = clock.now
    for _ in 0..<8 { #expect(try store.records(CountedMessage.self, workspaceID: workspace).count == 1000) }
    print("READ BENCHMARK: 1000 messages × 8 reads; uncached=\(uncached), cached=\(hot.duration(to: clock.now)); unchanged records decoded once")
    let message = messages[0]
    var object = try #require(JSONSerialization.jsonObject(with: WorkspaceCoding.encode(message)) as? [String: Any])
    object["content"] = "same-version replacement"
    let replacement = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    let id = message.metadata.id
    try database.execute("UPDATE records SET payload = ? WHERE id = ?", [.text(replacement), .text(id.uuidString)])
    #expect(try store.record(CountedMessage.self, id: id, workspaceID: workspace)?.message.content == "same-version replacement")
    #expect(try store.record(CountedMessage.self, id: id, workspaceID: UUID()) == nil)
    enum Abort: Error { case rollback }
    do {
        try database.transaction {
            try database.execute("UPDATE records SET payload = ? WHERE id = ?", [.text(String(decoding: try WorkspaceCoding.encode(message), as: UTF8.self)), .text(id.uuidString)])
            #expect(try store.record(CountedMessage.self, id: id, workspaceID: workspace)?.message.content == message.content)
            throw Abort.rollback
        }
    } catch Abort.rollback { }
    #expect(try store.record(CountedMessage.self, id: id, workspaceID: workspace)?.message.content == "same-version replacement")
    try database.execute("UPDATE records SET deleted = 1, payload = NULL WHERE id = ?", [.text(id.uuidString)])
    #expect(try store.record(CountedMessage.self, id: id, workspaceID: workspace) == nil)
}
