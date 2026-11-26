import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func allElevenCardKindsPreserveTheirResponsesAfterReopening() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let url = directory.appendingPathComponent("cards.sqlite")
    let repository = try await workspaceTestRepository(url: url)
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Card lifecycle verification")
    let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Verify local card responses")
    let cards = WorkspaceConversationCardService(repository: repository, identity: identity)
    let draft = WorkspaceCardContent.MailDraft(sender: "sender@example.org", recipient: "recipient@example.org", subject: "Verification", body: "A local draft")
    let checkout = try #require(URL(string: "https://blot-agent.vercel.app/app/pricing"))
    let cases: [(WorkspaceCardContent, WorkspaceCardResponse)] = [
        (.email(draft), .init(action: "send", value: String(decoding: try JSONEncoder().encode(draft), as: UTF8.self))),
        (.question(.init(prompt: "Choose", choices: ["Swift"])), .init(action: "submit", value: "Swift")),
        (.subscription(.init(checkoutURL: checkout)), .init(action: "dismiss")),
        (.command(.init(title: "Command", details: "Local command", command: "pwd", ruleScope: "Project")), .init(action: "allow_rule")),
        (.takeover(.init(reason: "Finish sign-in", tabID: UUID())), .init(action: "done")),
        (.task(.init(title: "Done", branch: nil, files: [], pullRequestURL: nil)), .init(action: "dismiss")),
        (.slack(.init(workspace: "Example", channel: "#test", thread: nil, body: "Draft")), .init(action: "send", value: "Edited draft")),
        (.plugin(.init(name: "Notion", detail: "Pages", connectionID: UUID())), .init(action: "dismiss")),
        (.credential(.init(name: "Token", purpose: "Connect", reference: "card:fixture")), .init(action: "saved")),
        (.cookies(.init(sourceProfileID: UUID(), destinationProfileID: UUID(), domains: ["example.org"])), .init(action: "deny")),
        (.mailFailure(.init(draft: draft, detail: "Unknown outcome", outcomeUnknown: true)), .init(action: "confirmed_not_sent")),
    ]
    #expect(Set(cases.map { $0.0.kind }).count == 11)
    var ids: [UUID] = []
    for (content, response) in cases {
        let id = UUID(); ids.append(id)
        try await cards.create(id: id, sourceMessageID: source, operationID: id, agentID: nil, content: content)
        try await cards.respond(commandID: UUID(), cardID: id, expectedVersion: 1, response: response)
    }
    let reopened = try await workspaceTestRepository(url: url)
    let restored = WorkspaceConversationCardService(repository: reopened, identity: identity)
    for (id, item) in zip(ids, cases) {
        let saved = try #require(try await reopened.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID))
        #expect(saved.state == "answered")
        #expect(try JSONDecoder().decode(WorkspaceCardContent.self, from: Data(saved.payloadJSON.utf8)) == item.0)
        #expect(try await restored.waitForResponse(cardID: id) == item.1)
        let consumed = try #require(try await reopened.record(BlotV3.ConversationCard.self, id: id, workspaceID: identity.workspaceID))
        #expect(consumed.state == "consumed")
    }
    // This service records intent only; no Mail, Slack, browser, payment or Keychain adapter is installed.
}

@Test func cardSnapshotsPreserveLegacyHistoryAndExecutorMessageAuthorship() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let desktop = try await workspaceTestRepository(url: directory.appendingPathComponent("desktop.sqlite"))
    let desktopID = try await desktop.localIdentity()
    let chat = WorkspaceChatService(repository: desktop, identity: desktopID)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Shared card")
    let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Choose")
    let cardID = UUID()
    let desktopCards = WorkspaceConversationCardService(repository: desktop, identity: desktopID)
    try await desktopCards.create(id: cardID, sourceMessageID: source, operationID: cardID, agentID: nil,
        content: .question(.init(prompt: "Language?", choices: ["Swift", "Java"])))
    let snapshot = try await desktop.replicaSnapshot(identity: desktopID)
    #expect(snapshot.conversationCards?.count == 1)
    #expect(snapshot.records.allSatisfy { $0.kind != "ConversationCard" })
    struct LegacySnapshot: Decodable { let records: [WorkspaceReplicaRecord] }
    #expect(try WorkspaceCoding.decode(LegacySnapshot.self, from: WorkspaceCoding.encode(snapshot)).records.count == snapshot.records.count)
    let phone = try await workspaceTestRepository(url: directory.appendingPathComponent("phone.sqlite"))
    let phoneID = try await phone.joinWorkspace(ownerID: desktopID.ownerID, workspaceID: desktopID.workspaceID)
    try await phone.installReplicaSnapshot(snapshot, identity: phoneID)
    try await WorkspaceConversationCardService(repository: phone, identity: phoneID).respond(commandID: UUID(), cardID: cardID,
        expectedVersion: 1, response: .init(action: "submit", value: "Swift"))
    #expect(try await phone.pendingSyncChanges().allSatisfy { $0.kind != "ConversationCard" })
    try await desktop.installReplicaSnapshot(phone.replicaSnapshot(identity: phoneID), identity: desktopID)
    #expect(try await desktopCards.waitForResponse(cardID: cardID).value == "Swift")
    let final = try await desktop.replicaSnapshot(identity: desktopID)
    try await phone.installReplicaSnapshot(final, identity: phoneID)
    let projection = try await phone.projection(identity: phoneID)
    #expect(projection.cards.first?.state == "consumed")
    #expect(projection.messages.contains { $0.content == "Language?\nSwift" && $0.executorDeviceId == desktopID.deviceID })
}

@Test func cardAnswerIsAtomicIdempotentAndSurvivesRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let url = directory.appendingPathComponent("workspace.sqlite")
    let repository = try await workspaceTestRepository(url: url)
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Question")
    let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Choose a language")
    let cards = WorkspaceConversationCardService(repository: repository, identity: identity)
    let id = UUID(), command = UUID()
    try await cards.create(id: id, sourceMessageID: source, operationID: id, agentID: nil,
        content: .question(.init(prompt: "Language?", choices: ["Swift", "Java"], allowsCustomAnswer: false)))
    let response = WorkspaceCardResponse(action: "submit", value: "Swift")
    try await cards.respond(commandID: command, cardID: id, expectedVersion: 1, response: response)
    try await cards.respond(commandID: command, cardID: id, expectedVersion: 1, response: response)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await cards.respond(commandID: UUID(), cardID: id, expectedVersion: 1, response: .init(action: "submit", value: "Java"))
    }
    let reopened = try await workspaceTestRepository(url: url)
    let restored = WorkspaceConversationCardService(repository: reopened, identity: identity)
    #expect(try await restored.waitForResponse(cardID: id) == response)
    let projection = try await reopened.projection(identity: identity)
    #expect(projection.cards.count == 1)
    #expect(projection.messages.contains { $0.content == "Language?\nSwift" })
}

@Test func cardsRejectExpiredAnswersInvalidChoicesAndSecretValues() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Cards")
    let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Question")
    let service = WorkspaceConversationCardService(repository: repository, identity: identity)
    let now = Date(), question = UUID(), credential = UUID()
    try await service.create(id: question, sourceMessageID: source, operationID: question, agentID: nil,
        content: .question(.init(prompt: "Pick", choices: ["A"], allowsCustomAnswer: false)), expiresAt: now.addingTimeInterval(1), now: now)
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        try await service.respond(commandID: UUID(), cardID: question, expectedVersion: 1, response: .init(action: "submit", value: "B"), now: now)
    }
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        try await service.respond(commandID: UUID(), cardID: question, expectedVersion: 1, response: .init(action: "submit", value: "A"), now: now.addingTimeInterval(2))
    }
    try await service.create(id: credential, sourceMessageID: source, operationID: credential, agentID: nil,
        content: .credential(.init(name: "API key", purpose: "Connect service", reference: "card:" + credential.uuidString)))
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        try await service.respond(commandID: UUID(), cardID: credential, expectedVersion: 1, response: .init(action: "saved", value: "must-not-sync"))
    }
    let card = try #require(try await repository.record(BlotV3.ConversationCard.self, id: credential, workspaceID: identity.workspaceID))
    #expect(card.responseJSON == nil)
    #expect(!card.payloadJSON.contains("must-not-sync"))
}
