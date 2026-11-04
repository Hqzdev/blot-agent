import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private struct TestWorkspace {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var url: URL { directory.appendingPathComponent("workspace-v3.sqlite") }
    func clean() { cleanupWorkspaceTestStorage(directory) }
}

@Test func durableChatAndReceiptsSurviveReopening() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let service = WorkspaceChatService(repository: repository, identity: identity)
    let conversationID = UUID(); let messageID = UUID()
    _ = try await service.createConversation(commandID: conversationID, title: "Планы")
    _ = try await service.sendMessage(commandID: messageID, conversationID: conversationID, content: "Обсудим проект")
    let reopened = try await workspaceTestRepository(url: files.url)
    #expect(try await reopened.localIdentity() == identity)
    let replay = WorkspaceChatService(repository: reopened, identity: identity)
    _ = try await replay.sendMessage(commandID: messageID, conversationID: conversationID, content: "Обсудим проект")
    #expect(try await reopened.records(BlotV3.Message.self, workspaceID: identity.workspaceID).count == 1)
    #expect(try await reopened.pendingChanges().count == 2)
    await #expect(throws: WorkspaceStorageError.commandConflict) {
        _ = try await replay.sendMessage(commandID: messageID, conversationID: conversationID, content: "Изменённый текст")
    }
    #expect(try await reopened.searchMessages("проект", workspaceID: identity.workspaceID).map(\.metadata.id) == [messageID])
    #expect(try await reopened.searchMessages("проект", workspaceID: UUID()).isEmpty)
}

@Test func failedBatchRollsBackRecordsReceiptOutboxAndSearch() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let metadata = try BlotV3.RecordMetadata(id: UUID(), ownerId: identity.ownerID, workspaceId: identity.workspaceID,
        version: 1, createdAt: Date(), updatedAt: Date())
    let message = try BlotV3.Message(metadata: metadata, conversationId: UUID(), role: .user,
        content: "atomic rollback", delivery: .saved, commandId: UUID(), artifactIds: [])
    let mutation = try WorkspaceRecordMutation(message, expectedVersion: 0)
    let commandID = UUID(); let command = Data("batch".utf8)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await repository.commit(commandID: commandID, command: command, mutations: [mutation, mutation])
    }
    #expect(try await repository.records(BlotV3.Message.self, workspaceID: identity.workspaceID).isEmpty)
    #expect(try await repository.pendingChanges().isEmpty)
    #expect(try await !repository.hasReceipt(commandID: commandID, command: command))
    #expect(try await repository.searchMessages("atomic", workspaceID: identity.workspaceID).isEmpty)
}

@Test func tombstonePreventsStaleResurrectionAndRemovesSearch() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let service = WorkspaceChatService(repository: repository, identity: identity)
    let conversationID = try await service.createConversation(commandID: UUID(), title: "Delete")
    let messageID = try await service.sendMessage(commandID: UUID(), conversationID: conversationID, content: "erase this")
    let message = try #require(try await repository.record(BlotV3.Message.self, id: messageID, workspaceID: identity.workspaceID))
    try await repository.commit(commandID: UUID(), command: Data("delete".utf8), mutations: [.init(deleting: message)])
    await #expect(throws: WorkspaceStorageError.deletedRecord) {
        try await repository.commit(commandID: UUID(), command: Data("restore stale".utf8), mutations: [.init(message, expectedVersion: 0)])
    }
    #expect(try await repository.searchMessages("erase", workspaceID: identity.workspaceID).isEmpty)
    #expect(try await repository.pendingChanges().last?.deleted == true)
}

@Test func recoveryPreservesPartialResponseWithoutAnotherAnswer() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let service = WorkspaceChatService(repository: repository, identity: identity)
    let conversationID = try await service.createConversation(commandID: UUID(), title: "Stream")
    let messageID = try await service.sendMessage(commandID: UUID(), conversationID: conversationID, content: "Hello")
    let source = try #require(try await repository.record(BlotV3.Message.self, id: messageID, workspaceID: identity.workspaceID))
    let recorder = WorkspaceResponseRecorder(repository: repository, identity: identity)
    let responseID = UUID()
    _ = try await recorder.begin(id: responseID, replyingTo: source, agentID: nil)
    _ = try await recorder.append("Частичный ответ 👋", to: responseID)
    let reopened = try await workspaceTestRepository(url: files.url)
    let recovery = WorkspaceResponseRecorder(repository: reopened, identity: identity)
    try await recovery.recoverInterruptedResponses()
    try await recovery.recoverInterruptedResponses()
    let messages = try await reopened.records(BlotV3.Message.self, workspaceID: identity.workspaceID)
    #expect(messages.count == 2)
    let response = try #require(messages.first { $0.metadata.id == responseID })
    #expect(response.content == "Частичный ответ 👋")
    #expect(response.delivery == .interrupted)
    await #expect(throws: WorkspaceStorageError.invalidRecord) { _ = try await recovery.append("more", to: responseID) }
}

@Test func racingWritersAcceptOneCommandOnly() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let first = try await workspaceTestRepository(url: files.url)
    let second = try await workspaceTestRepository(url: files.url)
    let identity = try await first.localIdentity()
    let a = WorkspaceChatService(repository: first, identity: identity)
    let b = WorkspaceChatService(repository: second, identity: identity)
    let commandID = UUID()
    async let left = a.createConversation(commandID: commandID, title: "Race")
    async let right = b.createConversation(commandID: commandID, title: "Race")
    let result = try await (left, right)
    #expect(result.0 == result.1)
    #expect(try await first.pendingChanges().count == 1)
}

@Test func conversationCommandsPersistVersionAndDeleteHistoryTogether() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversationID = try await chat.createConversation(commandID: UUID(), title: "Before")
    _ = try await chat.sendMessage(commandID: UUID(), conversationID: conversationID, content: "searchable history")
    let service = WorkspaceConversationService(repository: repository, identity: identity)
    let updateID = UUID()
    try await service.update(commandID: updateID, conversationID: conversationID, expectedVersion: 1, title: "After", pinned: true)
    try await service.update(commandID: updateID, conversationID: conversationID, expectedVersion: 1, title: "After", pinned: true)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await service.update(commandID: UUID(), conversationID: conversationID, expectedVersion: 1, title: "Stale")
    }
    let reopened = try await workspaceTestRepository(url: files.url)
    let saved = try #require(try await reopened.record(BlotV3.Conversation.self, id: conversationID, workspaceID: identity.workspaceID))
    #expect(saved.title == "After" && saved.pinned && saved.metadata.version == 2)
    try await service.delete(commandID: UUID(), conversationID: conversationID, expectedVersion: 2)
    #expect(try await reopened.records(BlotV3.Message.self, workspaceID: identity.workspaceID).isEmpty)
    #expect(try await reopened.records(BlotV3.Conversation.self, workspaceID: identity.workspaceID).isEmpty)
    #expect(try await reopened.searchMessages("history", workspaceID: identity.workspaceID).isEmpty)
    #expect(try await reopened.pendingChanges().suffix(2).allSatisfy(\.deleted))
}

@Test func closeRejectsFurtherUseAndReopenPreservesHistory() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Safe close")
    _ = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Persisted")
    try await repository.close()
    try await repository.close()
    await #expect(throws: WorkspaceStorageError.databaseClosed) { _ = try await chat.createConversation(commandID: UUID(), title: "Closed") }
    let reopened = try await workspaceTestRepository(url: files.url)
    let messages = try await reopened.records(BlotV3.Message.self, workspaceID: identity.workspaceID)
    #expect(messages.map { $0.content } == ["Persisted"])
}

@Test func snapshotRequestKeepsOriginalCursorAcrossRestartAndCompletion() async throws {
    let files = TestWorkspace(); defer { files.clean() }
    let repository = try await workspaceTestRepository(url: files.url)
    let identity = try await repository.localIdentity()
    let requestID = UUID()
    #expect(try await repository.snapshotRequestCursor(id: requestID) == 0)
    try await repository.applySyncChanges([], identity: identity, relayCursor: 7)
    try await repository.close()
    let reopened = try await workspaceTestRepository(url: files.url)
    #expect(try await reopened.pendingSnapshotRequestIDs() == [requestID])
    #expect(try await reopened.snapshotRequestCursor(id: requestID) == 0)
    try await reopened.completeSnapshotRequest(id: requestID)
    #expect(try await reopened.pendingSnapshotRequestIDs().isEmpty)
    #expect(try await reopened.snapshotRequestCursor(id: requestID) == 0)
    #expect(try await reopened.snapshotRequestCursor(id: UUID()) == 7)
}
