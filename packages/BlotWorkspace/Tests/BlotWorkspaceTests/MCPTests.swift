import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

private actor MCPCredentials: WorkspaceCredentialStore {
    var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

private actor MCPTestTransport: MCPTransport {
    var calls = 0
    var changed = false
    var unknown = false
    var errorResult = false
    var returnedText: String?
    var schema: ChatJSON { .object(["type": .string("object"), "properties": .object(["text": .object(["type": .string("string"), "minLength": .number(changed ? 2 : 1)])]), "required": .array([.string("text")]), "additionalProperties": .bool(false)]) }
    func change() { changed = true }
    func loseResponse() { unknown = true }
    func businessError() { errorResult = true }
    func echoCredential() { returnedText = "credential-value" }
    func exchange(_ message: ChatJSON) async throws -> ChatJSON? {
        let fields = message.mcpFields
        guard let id = fields["id"] else { return nil }
        let result: ChatJSON
        switch fields["method"]?.mcpString {
        case "initialize": result = .object(["protocolVersion": .string(MCPClient.version), "capabilities": .object(["tools": .object([:])])])
        case "tools/list": result = .object(["tools": .array([.object(["name": .string("echo"), "description": .string("Echo text"), "inputSchema": schema])])])
        case "tools/call":
            calls += 1
            if unknown { throw MCPError.unavailable }
            result = .object(["isError": .bool(errorResult), "content": .array([.object(["type": .string("text"), "text": returnedText.map(ChatJSON.string) ?? fields["params"]?.mcpFields["arguments"]?.mcpFields["text"] ?? .string("")])])])
        default: throw MCPError.protocolViolation
        }
        return .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
    }
    func close() {}
}

private struct MCPHarness {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let credentials = MCPCredentials()
    let transport = MCPTestTransport()
    let service: WorkspaceMCPService
    let agent: UUID
    let conversation: UUID
    let source: UUID
    init(request: String = "Use the MCP tool") async throws {
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("workspace.sqlite"))
        identity = try await repository.localIdentity()
        let server = transport
        service = WorkspaceMCPService(repository: repository, identity: identity, credentials: credentials, connect: { _ in MCPClient(transport: server) })
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "MCP agent", instructions: "Use approved tools"))
        conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "MCP", agentID: agent)
        source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: request)
    }
    func connect(token: String = "") async throws -> UUID {
        let inspection = try await service.inspect(name: "Test MCP", configuration: .init(endpoint: "https://example.test/mcp", bearerToken: token))
        return try await service.save(inspection, selectedTools: ["echo"], agentIDs: [agent])
    }
    func context(_ definition: ChatToolDefinition) -> WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil, allowedToolIDs: [definition.name], agentID: agent) }
}

@Test func mcpCallsRequireConfirmationAndReplayUsesDurableResult() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    _ = try await h.connect()
    let provider = try await h.service.provider { _, details in #expect(details.contains("hello")); return true }
    let definition = try #require(provider.definitions.first)
    let registry = try WorkspaceToolRegistry(providers: [provider])
    let call = ChatToolCall(id: "one", name: definition.name, arguments: .object(["text": .string("hello")]))
    let first = try await registry.execute(call, context: h.context(definition))
    let replay = try await registry.execute(call, context: h.context(definition))
    #expect(first == replay); #expect(first.mcpFields["state"] == .string("succeeded")); #expect(await h.transport.calls == 1)
    let projection = try await h.repository.projection(identity: h.identity)
    #expect(projection.invocations.count == 1); #expect(projection.invocations.first?.state == .succeeded)
    let record = try #require(try await h.repository.records(BlotV3.McpConnection.self, workspaceID: h.identity.workspaceID).first)
    #expect(record.endpoint == "device:" + h.identity.deviceID.uuidString)
    #expect(!String(decoding: try JSONEncoder().encode(record), as: UTF8.self).contains("example.test"))
}

@Test func mcpDenialChangedArgumentsAndSchemaNeverReachTool() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    _ = try await h.connect()
    let provider = try await h.service.provider { _, _ in false }
    let definition = try #require(provider.definitions.first)
    let call = ChatToolCall(id: "deny", name: definition.name, arguments: .object(["text": .string("hello")]))
    _ = try await provider.execute(call, context: h.context(definition))
    #expect(await h.transport.calls == 0)
    let accepted = try await h.service.provider { _, _ in true }
    let changed = ChatToolCall(id: "deny", name: definition.name, arguments: .object(["text": .string("different")]))
    let changedResult = try await accepted.execute(changed, context: h.context(definition))
    #expect(changedResult.mcpFields["state"] == .string("failed"))
    await h.transport.change()
    let schemaResult = try await accepted.execute(.init(id: "schema", name: definition.name, arguments: call.arguments), context: h.context(definition))
    #expect(schemaResult.mcpFields["state"] == .string("failed")); #expect(await h.transport.calls == 0)
}

@Test func mcpUnknownOutcomeBlocksNewCallsUntilOwnerReconciles() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    let connectionID = try await h.connect()
    let provider = try await h.service.provider { _, _ in true }
    let definition = try #require(provider.definitions.first)
    await h.transport.loseResponse()
    let call = ChatToolCall(id: "lost", name: definition.name, arguments: .object(["text": .string("hello")]))
    let result = try await provider.execute(call, context: h.context(definition))
    #expect(result.mcpFields["state"] == .string("unknown"))
    #expect(try await provider.availableDefinitions(context: h.context(definition)).isEmpty)
    _ = try await provider.execute(.init(id: "other", name: call.name, arguments: call.arguments), context: h.context(definition))
    #expect(await h.transport.calls == 1)
    let projection = try await h.repository.projection(identity: h.identity)
    let invocation = try #require(projection.invocations.first)
    try await h.service.resolve(invocationID: invocation.metadata.id, succeeded: true)
    #expect(try await !provider.availableDefinitions(context: h.context(definition)).isEmpty)
    try await h.service.disconnect(id: connectionID)
    #expect(try await provider.availableDefinitions(context: h.context(definition)).isEmpty)
}

@Test func mcpRevocationDuringConfirmationAndForeignReplicaCannotAuthorizeCalls() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    let id = try await h.connect()
    let service = h.service, agent = h.agent
    let provider = try await service.provider { _, _ in
        try await service.refresh(id: id)
        return true
    }
    let definition = try #require(provider.definitions.first)
    _ = try await provider.execute(.init(id: "revoke", name: definition.name, arguments: .object(["text": .string("hello")])), context: h.context(definition))
    #expect(await h.transport.calls == 0)
    try await service.setAccess(id: id, selectedTools: ["echo"], agentIDs: [agent])
    let other = try await workspaceTestRepository(url: h.folder.appendingPathComponent("other.sqlite"))
    let otherIdentity = try await other.joinWorkspace(ownerID: h.identity.ownerID, workspaceID: h.identity.workspaceID)
    try await other.installReplicaSnapshot(h.repository.replicaSnapshot(identity: h.identity), identity: otherIdentity)
    let foreign = WorkspaceMCPService(repository: other, identity: otherIdentity, credentials: MCPCredentials())
    #expect(try await foreign.provider { _, _ in true }.definitions.isEmpty)
    let reopened = WorkspaceMCPService(repository: h.repository, identity: h.identity, credentials: h.credentials)
    #expect(try await reopened.access().first?.enabled == true)
    #expect(try await reopened.provider { _, _ in true }.definitions.count == 1)
}

@Test func mcpReadOnlyRequestsAndInvalidArgumentsCannotReachTool() async throws {
    let h = try await MCPHarness(request: "Только чтение"); defer { cleanupWorkspaceTestStorage(h.folder) }
    _ = try await h.connect()
    let provider = try await h.service.provider { _, _ in true }
    let definition = try #require(provider.definitions.first)
    #expect(try await provider.availableDefinitions(context: h.context(definition)).isEmpty)
    let registry = try WorkspaceToolRegistry(providers: [provider])
    await #expect(throws: WorkspaceToolError.invalidArguments) {
        _ = try await registry.execute(.init(id: "invalid", name: definition.name, arguments: .object(["text": .number(1)])), context: h.context(definition))
    }
    #expect(await h.transport.calls == 0)
}

@Test func mcpSchemasAcceptUnionsReferencesAndAdditionalProperties() throws {
    let schema: ChatJSON = .object(["type": .string("object"), "$defs": .object(["nullable": .object(["type": .array([.string("string"), .string("null")])])]),
        "properties": .object(["value": .object(["$ref": .string("#/$defs/nullable")])]), "additionalProperties": .object(["type": .string("integer")])])
    try MCPJSONSchema.validate(.object(["value": .null, "extra": .number(4)]), schema: schema)
    #expect(throws: WorkspaceToolError.invalidArguments) { try MCPJSONSchema.validate(.object(["extra": .string("no")]), schema: schema) }
}

@Test func mcpToolErrorsStayFailedAndCredentialEchoIsRedactedBeforePersistence() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    _ = try await h.connect(token: "credential-value")
    await h.transport.businessError(); await h.transport.echoCredential()
    let provider = try await h.service.provider { _, _ in true }, definition = try #require(provider.definitions.first)
    let result = try await provider.execute(.init(id: "error", name: definition.name, arguments: .object(["text": .string("hello")])), context: h.context(definition))
    #expect(result.mcpFields["state"] == .string("failed"))
    let invocation = try #require(try await h.repository.projection(identity: h.identity).invocations.first)
    #expect(invocation.state == .failed); #expect(invocation.result?.contains("credential-value") == false)
    #expect(invocation.result?.contains("[redacted]") == true)
}

@Test func mcpSchemaChangingWhileOwnerConfirmsCannotExecute() async throws {
    let h = try await MCPHarness(); defer { cleanupWorkspaceTestStorage(h.folder) }
    _ = try await h.connect()
    let server = h.transport
    let provider = try await h.service.provider { _, _ in await server.change(); return true }
    let definition = try #require(provider.definitions.first)
    let result = try await provider.execute(.init(id: "change", name: definition.name, arguments: .object(["text": .string("hello")])), context: h.context(definition))
    #expect(result.mcpFields["state"] == .string("failed")); #expect(await h.transport.calls == 0)
}

#if os(macOS)
@Test func mcpRealStdioInitializesDiscoversCallsAndCancels() async throws {
    let script = #"""
import json,sys,time,os
for line in sys.stdin:
    m=json.loads(line)
    if 'id' not in m: continue
    method=m.get('method')
    if method=='initialize': r={'protocolVersion':'2025-11-25','capabilities':{'tools':{}}}
    elif method=='tools/list': r={'tools':[{'name':'echo','inputSchema':{'type':'object','properties':{}}}]}
    elif method=='tools/call':
        if m['params']['arguments'].get('wait'): time.sleep(10)
        r={'content':[{'type':'text','text':'real '+str('HOME' not in os.environ)}]}
    else: continue
    print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':r}),flush=True)
"""#
    let config = MCPConfiguration(transport: .stdio, endpoint: "/usr/bin/python3", arguments: ["-u", "-c", script], workingDirectory: "/private/tmp", timeout: 2, trustedLocalProcess: true)
    let client = try MCPClient.connect(configuration: config)
    do {
        #expect(try await client.tools().map(\.name) == ["echo"])
        let result = try await client.call(name: "echo", arguments: .object([:]))
        #expect(String(decoding: try JSONEncoder().encode(result), as: UTF8.self).contains("real True"))
        let task = _Concurrency.Task { try await client.call(name: "echo", arguments: .object(["wait": .bool(true)])) }
        try await _Concurrency.Task.sleep(for: .milliseconds(80)); task.cancel()
        await #expect(throws: (any Error).self) { _ = try await task.value }
        await client.close()
    } catch { await client.close(); throw error }
}

@Test func mcpStdioTimeoutClosesANonresponsiveServer() async throws {
    let client = try MCPClient.connect(configuration: .init(transport: .stdio, endpoint: "/usr/bin/python3",
        arguments: ["-c", "import time; time.sleep(30)"], workingDirectory: "/private/tmp", timeout: 1, trustedLocalProcess: true))
    let start = ContinuousClock.now
    await #expect(throws: MCPError.timeout) { _ = try await client.tools() }
    #expect(ContinuousClock.now - start < .seconds(3))
    await client.close()
}
#endif
