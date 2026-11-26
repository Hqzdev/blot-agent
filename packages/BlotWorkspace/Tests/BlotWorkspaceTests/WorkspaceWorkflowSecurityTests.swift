import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func googleMailEncodingRejectsHeaderInjectionAndPreservesUnicode() throws {
    let draft = WorkspaceCardContent.MailDraft(sender: "owner@example.org", recipient: "recipient@example.org", subject: "Проверка", body: "Привет\nМир")
    let encoded = try WorkspaceGoogleTools.mime(draft)
    var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    let message = String(decoding: try #require(Data(base64Encoded: base64)), as: UTF8.self)
    #expect(message.contains("Subject: =?UTF-8?B?"))
    #expect(message.contains("To: recipient@example.org\r\n"))
    var injected = draft; injected.recipient = "recipient@example.org\r\nBcc: other@example.org"
    #expect(throws: WorkspaceStorageError.invalidParameters) { try WorkspaceGoogleTools.mime(injected) }
    injected = draft; injected.subject = "hello\nBcc: other@example.org"
    #expect(throws: WorkspaceStorageError.invalidParameters) { try WorkspaceGoogleTools.mime(injected) }
}

@Test func messagingOAuthUsesPKCEAndStrictCallbackWithoutAClientSecret() throws {
    for provider in WorkspaceMessagingProvider.allCases {
        let callback = URL(string: "blot-agent-macos:/plugins/" + provider.rawValue)!
        let authorization = try WorkspaceMessagingAuthorization(provider: provider, clientID: "test-client-id", redirectURI: callback)
        let items = URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.first { $0.name == "code_challenge_method" }?.value == "S256")
        #expect(!items.contains { $0.name == "client_secret" || $0.name == "resource" })
        #expect(items.contains { $0.name == (provider == .slack ? "user_scope" : "scope") })
        let state = try #require(items.first { $0.name == "state" }?.value)
        let fields = try authorization.fields(URL(string: callback.absoluteString + "?state=" + state + "&code=one-time")!)
        #expect(fields["client_secret"] == nil && fields["resource"] == nil)
        #expect((fields["code_verifier"]?.count ?? 0) >= 43)
        #expect(throws: MCPError.denied) { try authorization.fields(URL(string: callback.absoluteString + "?state=wrong&code=x")!) }
    }
}

@Test func taughtTasksRejectUnidentifiedSecureOrMalformedTargets() throws {
    let task = WorkspaceTaughtTask(bundleID: "com.example.TeachingFixture", application: "Fixture", duration: 10,
        steps: [.init(action: .press, target: .init(role: "AXButton", title: "Save", identifier: "save"))])
    try task.validate()
    var invalid = task; invalid.steps = [.init(action: .setValue, target: .init(role: "AXSecureTextField", title: "Password", identifier: "pass"), value: "never record")]
    #expect(throws: WorkspaceStorageError.invalidParameters) { try invalid.validate() }
    invalid.steps = [.init(action: .press, target: .init(role: "AXButton", title: "", identifier: ""))]
    #expect(throws: WorkspaceStorageError.invalidParameters) { try invalid.validate() }
}

@Test func teamBotTasksAreDeduplicatedAndFreezeRestrictedInstructionsWithoutChangingTheAgent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("team.sqlite"))
    let identity = try await repository.localIdentity()
    let agentID = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Worker", instructions: "Personal agent instructions", toolIDs: ["page_read", "gmail_send"]))
    let channel = WorkspaceTeamBot.Channel(connectionID: UUID().uuidString, provider: "slack", workspace: "T1", channel: "C1", trigger: "@blot")
    let bot = WorkspaceTeamBot(id: UUID(), teamID: UUID(), ownerID: identity.ownerID, version: 1,
        configuration: .init(name: "Team helper", agentID: agentID, executorDeviceID: identity.deviceID, instructions: "Answer team questions", allowedTools: ["page_read", "unavailable"], channels: [channel], enabled: true))
    let tasks = WorkspaceTeamBotTasks(repository: repository, identity: identity)
    let id = try await tasks.enqueue(bot: bot, channel: channel, messageID: "1.000", author: "U1", text: "@blot summary")
    #expect(try await tasks.enqueue(bot: bot, channel: channel, messageID: "1.000", author: "U1", text: "@blot summary") == id)
    let projection = try await repository.projection(identity: identity)
    #expect(projection.tasks.count == 1)
    let task = try #require(projection.tasks.first)
    let configuration = try #require(projection.configurations.first { $0.metadata.id == task.configurationId })
    #expect(configuration.toolIds == ["page_read"])
    #expect(configuration.instructions.contains("Answer team questions"))
    #expect(!configuration.instructions.contains("Personal agent instructions"))
    #expect(projection.conversations.first { $0.metadata.id == task.conversationId }?.kind == .group)
    #expect(try await tasks.policy(id)?.bot.id == bot.id)
    let agent = try #require(projection.agents.first)
    #expect(agent.configurationId != configuration.metadata.id)
}

@Test func rejectingSuggestedMemoryKeepsItsSourceInConversationContext() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("memory-review.sqlite"))
    let identity = try await repository.localIdentity()
    let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Review")
    let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Original request")
    let service = WorkspaceMemoryService(repository: repository, identity: identity)
    let memory = try await service.create(commandID: UUID(), content: "Incorrect suggestion", sourceID: sourceID, candidate: true)
    try await service.reject(commandID: UUID(), memoryID: memory, expectedVersion: 1)
    let projection = try await repository.projection(identity: identity)
    #expect(projection.memories.isEmpty)
    let source = try #require(projection.messages.first { $0.metadata.id == sourceID })
    #expect(try WorkspaceContextBuilder().messages(for: source, projection: projection).last?.content == "Original request")
}

@Test func pageToolRetriesDoNotDuplicateArtifactsOrResultCards() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("page-tool.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Writer", instructions: "Write pages", toolIDs: ["page_create"]))
    let chat = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Pages", agentID: agent)
    let source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Create a report page")
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("files"))
    let pages = WorkspacePageService(repository: repository, identity: identity, files: files)
    let tools = WorkspacePageTools(service: pages, repository: repository, identity: identity)
    let call = ChatToolCall(id: "create-report", name: "page_create", arguments: .object(["title": .string("Report"), "content": .string("Reviewed report")]))
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: ["page_create"], agentID: agent, inlineCards: true)
    let first = try await tools.execute(call, context: context)
    #expect(try await tools.execute(call, context: context) == first)
    let projection = try await repository.projection(identity: identity)
    #expect(projection.cards.count == 1)
    #expect(try await pages.list().count == 1)
    #expect(try await pages.revisions().count == 1)
}
