import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func memoryImportPreservesSourceAndDoesNotDuplicateOnRetry() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("memory.sqlite"))
    let identity = try await repository.localIdentity()
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("files"))
    let source = try await files.store(commandID: UUID(), name: "memory.txt", mediaType: "text/plain", data: Data("Reviewed facts".utf8))
    let command = UUID(), facts = WorkspaceMemoryImport.facts(from: "- Prefers Russian\n1. Works on Mac\n- Prefers Russian")
    #expect(facts == ["Prefers Russian", "Works on Mac"])
    try await WorkspaceMemoryImport.save(commandID: command, facts: facts, sourceID: source, repository: repository, identity: identity)
    try await WorkspaceMemoryImport.save(commandID: command, facts: facts, sourceID: source, repository: repository, identity: identity)
    let memories = try await repository.projection(identity: identity).memories
    #expect(memories.count == 2)
    #expect(memories.allSatisfy { $0.sourceId == source && $0.state == .active })
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        try await WorkspaceMemoryImport.save(commandID: UUID(), facts: [""], sourceID: source, repository: repository, identity: identity)
    }
    #expect(try await repository.projection(identity: identity).memories.count == 2)
}

@Test func purchaseOrderChecksTotalsAndNeverAcceptsASecretResponse() throws {
    let order = WorkspacePurchaseOrder(merchant: "Test shop", checkoutURL: URL(string: "https://shop.example/checkout")!, currency: "RUB",
        items: [.init(title: "Book", quantity: 2, unitAmountMinor: 1000)], taxMinor: 100, deliveryMinor: 200, totalMinor: 2300)
    try order.validate()
    try WorkspaceConversationCardService.validate(.init(action: "allow"), for: .purchase(order))
    #expect(throws: WorkspaceStorageError.invalidParameters) {
        try WorkspaceConversationCardService.validate(.init(action: "allow", value: "card details"), for: .purchase(order))
    }
    let invalid = WorkspacePurchaseOrder(merchant: order.merchant, checkoutURL: order.checkoutURL, currency: "RUB", items: order.items,
        taxMinor: 100, deliveryMinor: 200, totalMinor: 2000)
    #expect(throws: WorkspaceStorageError.invalidParameters) { try invalid.validate() }
}

private actor WorkflowCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

@Test func vaultImportsQuotedCSVAndScopesSecretsToTheOwner() async throws {
    let csv = "name,url,username,password\r\n\"Work, account\",https://example.com,user,\"p,ass\"\r\n"
    let imported = try WorkspaceVaultCSV.logins(csv)
    #expect(imported.count == 1)
    #expect(imported[0].title == "Work, account")
    #expect(imported[0].fields["password"] == "p,ass")
    let credentials = WorkflowCredentials()
    let first = WorkspaceVaultService(credentials: credentials, ownerID: UUID())
    let second = WorkspaceVaultService(credentials: credentials, ownerID: UUID())
    #expect(try await first.importLogins(imported) == 1)
    #expect(try await first.importLogins(imported) == 0)
    #expect(try await second.list().isEmpty)
    let saved = try await first.read(imported[0].id)
    await #expect(throws: WorkspaceStorageError.versionConflict) { try await first.save(imported[0]) }
    try await first.delete(saved.id, expectedVersion: saved.version)
    #expect(try await first.list().isEmpty)
    let invalid = WorkspaceVaultItem(title: "Card", kind: .card, fields: ["cvc": "123"])
    await #expect(throws: WorkspaceStorageError.invalidParameters) { try await first.save(invalid) }
}

@Test func customRulesPreferAskFirstAndNeverBypassMandatoryApproval() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("rules.sqlite"))
    let identity = try await repository.localIdentity(), service = WorkspaceRuleService(repository: repository, identity: identity)
    let allow = WorkspaceCustomRule(name: "Read site", toolID: "browser_click", resource: "https://example.com", decision: .allowAutomatically)
    try await service.save(allow)
    #expect(try await !service.requiresReview(toolID: "browser_click", resource: "https://example.com", agentID: nil, default: true))
    #expect(try await service.requiresReview(toolID: "browser_click", resource: "https://elsewhere.example", agentID: nil, default: true))
    #expect(try await service.requiresReview(toolID: "browser_click", resource: "https://example.com", agentID: nil, default: true, mandatory: true))
    let ask = WorkspaceCustomRule(name: "Ask for clicks", toolID: "browser_click", decision: .askFirst)
    try await service.save(ask)
    #expect(try await service.requiresReview(toolID: "browser_click", resource: "https://example.com", agentID: nil, default: false))
    let saved = try #require(try await service.rules().first { $0.id == ask.id })
    try await service.delete(saved)
    #expect(try await !service.requiresReview(toolID: "browser_click", resource: "https://example.com", agentID: nil, default: true))
}

@Test func mcpHeadersRejectNewlinesReservedNamesAndDuplicateAuthorization() throws {
    var configuration = MCPConfiguration(endpoint: "https://example.com/mcp")
    configuration.httpHeaders = ["X-Api-Key": "test-value"]
    try configuration.validate()
    configuration.httpHeaders = ["Host": "elsewhere.example"]
    #expect(throws: MCPError.configuration) { try configuration.validate() }
    configuration.httpHeaders = ["X-Key": "a\r\nb"]
    #expect(throws: MCPError.configuration) { try configuration.validate() }
    configuration.httpHeaders = ["Authorization": "Basic value"]; configuration.bearerToken = "token"
    #expect(throws: MCPError.configuration) { try configuration.validate() }
}

@Test func mcpOAuthBindsStateRedirectPKCEAndResource() throws {
    let attempt = try MCPOAuthAttempt(authorizationEndpoint: URL(string: "https://auth.example/authorize")!,
        tokenEndpoint: URL(string: "https://auth.example/token")!, resource: URL(string: "https://mcp.example/mcp")!,
        clientID: "test-client", redirectURI: URL(string: "blot-agent-macos:/mcp/oauth")!, scope: "read")
    let query = URLComponents(url: attempt.url, resolvingAgainstBaseURL: false)!.queryItems!
    let state = try #require(query.first { $0.name == "state" }?.value)
    #expect(query.first { $0.name == "code_challenge_method" }?.value == "S256")
    let fields = try attempt.tokenFields(callback: URL(string: "blot-agent-macos:/mcp/oauth?state=\(state)&code=one-time")!)
    #expect(fields["resource"] == "https://mcp.example/mcp")
    #expect((fields["code_verifier"]?.count ?? 0) >= 43)
    #expect(throws: MCPError.denied) { _ = try attempt.tokenFields(callback: URL(string: "blot-agent-macos:/mcp/oauth?state=wrong&code=one-time")!) }
    #expect(throws: MCPError.configuration) { _ = try attempt.tokenFields(callback: URL(string: "blot-agent-macos:/other?state=\(state)&code=one-time")!) }
    #expect(throws: MCPError.denied) { _ = try attempt.tokenFields(callback: URL(string: "blot-agent-macos:/mcp/oauth?state=\(state)&state=\(state)&code=one-time")!) }
}

@Test func pagesKeepVersionsRejectStaleEditsAndRestoreWithoutLosingHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("pages.sqlite"))
    let identity = try await repository.localIdentity()
    let files = WorkspaceFileService(repository: repository, identity: identity, directory: directory.appendingPathComponent("files"))
    let pages = WorkspacePageService(repository: repository, identity: identity, files: files)
    let id = UUID(), revisionID = UUID(), blocks: [WorkspacePageDocument.Block] = [.init(text: "First revision")]
    let first = try await pages.save(id: id, revisionID: revisionID, expectedRevision: nil, title: "Report", blocks: blocks)
    #expect(try await pages.save(id: id, revisionID: revisionID, expectedRevision: nil, title: "Report", blocks: blocks) == first)
    let second = try await pages.save(id: id, expectedRevision: first.revisionID, title: "Report", blocks: [.init(text: "Updated")], pinned: true)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await pages.save(id: id, expectedRevision: first.revisionID, title: "Stale", blocks: blocks)
    }
    let restored = try await pages.restore(pageID: id, revisionID: first.revisionID, expectedHeads: [second.revisionID])
    #expect(restored.blocks == first.blocks)
    #expect(restored.parents == [second.revisionID])
    #expect(try await pages.revisions(id).count == 3)
    #expect(try await pages.list().first?.document.revisionID == restored.revisionID)
    await #expect(throws: WorkspaceStorageError.versionConflict) {
        try await pages.restore(pageID: id, revisionID: first.revisionID, expectedHeads: [second.revisionID])
    }
    await #expect(throws: WorkspaceStorageError.invalidParameters) {
        try await pages.save(expectedRevision: nil, title: "Bad table", blocks: [.init(kind: .table, text: "", columns: ["A"], rows: [["1", "2"]])])
    }
    await #expect(throws: WorkspaceBrowserError.self) {
        try await pages.save(expectedRevision: nil, title: "Unsafe link", blocks: [.init(kind: .link, text: "javascript:alert(1)")])
    }
}
