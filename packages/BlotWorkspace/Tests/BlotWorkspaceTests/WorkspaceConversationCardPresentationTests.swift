import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func cookieCardSelectionCannotExpandTheApprovedDomainSet() throws {
    let transfer = WorkspaceCardContent.CookieTransfer(sourceProfileID: UUID(), destinationProfileID: UUID(), domains: ["example.org", "example.com"])
    let selected = WorkspaceCardResponse(action: "allow_domains", value: "[\"example.org\"]")
    try WorkspaceConversationCardService.validate(selected, for: .cookies(transfer))
    #expect(try WorkspaceConversationCardService.selectedCookieDomains(selected, transfer: transfer) == ["example.org"])
    #expect(try WorkspaceConversationCardService.selectedCookieDomains(.init(action: "allow"), transfer: transfer) == transfer.domains)
    for raw in ["[]", "[\"other.example\"]", "[\"example.org\",\"example.org\"]", "not-json"] {
        #expect(throws: WorkspaceStorageError.invalidParameters) {
            try WorkspaceConversationCardService.validate(.init(action: "allow_domains", value: raw), for: .cookies(transfer))
        }
    }
    #expect(throws: WorkspaceStorageError.invalidParameters) {
        try WorkspaceConversationCardService.validate(.init(action: "allow", value: "[\"example.org\"]"), for: .cookies(transfer))
    }
    // Old executors recognize only "allow" and therefore reject the new subset action.
    #expect(selected.action != "allow")
}

@Test func taskCardCountsDiffHunksAndDecodesOlderPayloads() throws {
    let diff = """
    diff --git a/a.swift b/a.swift
    --- a/a.swift
    +++ b/a.swift
    @@ -1,2 +1,3 @@
    -old
    +new
    +++a real added line beginning with pluses
     context
    diff --git a/b.swift b/b.swift
    --- a/b.swift
    +++ b/b.swift
    @@ -1 +1 @@
    ---a real deleted line beginning with minuses
    +replacement
    """
    let count = try #require(WorkspaceTaskResultCard.statistics(diff))
    #expect(count.additions == 3)
    #expect(count.deletions == 2)
    #expect(WorkspaceTaskResultCard.statistics("Binary files a/a and b/a differ") == nil)
    let legacy = Data("{\"state\":\"completed\",\"title\":\"Done\",\"files\":[]}".utf8)
    let restored = try JSONDecoder().decode(WorkspaceCardContent.TaskResult.self, from: legacy)
    #expect(restored.additions == nil && restored.deletions == nil)
}

@Test func questionDismissalPersistsWithoutInventingAnAnswer() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("question.sqlite"))
    let identity = try await repository.localIdentity()
    let chat = WorkspaceChatService(repository: repository, identity: identity)
    let conversation = try await chat.createConversation(commandID: UUID(), title: "Question")
    let source = try await chat.sendMessage(commandID: UUID(), conversationID: conversation, content: "Ask")
    let cards = WorkspaceConversationCardService(repository: repository, identity: identity)
    let id = UUID()
    try await cards.create(id: id, sourceMessageID: source, operationID: id, agentID: nil, content: .question(.init(prompt: "Choose", choices: ["A"])))
    try await cards.respond(commandID: UUID(), cardID: id, expectedVersion: 1, response: .init(action: "dismiss"))
    let response = try await cards.waitForResponse(cardID: id)
    #expect(response.action == "dismiss" && response.value == nil)
    #expect(try await repository.projection(identity: identity).messages.contains { $0.content == "Choose" })
}
