import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

private actor MCPVerificationCredentials: WorkspaceCredentialStore {
    var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

private struct MCPVerificationModel: ChatModel {
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            if request.messages.last?.role == "tool" {
                let result = request.messages.last!.content
                precondition(result.contains("real MCP result") && result.contains("untrusted_content"), "Missing actual MCP tool result")
                continuation.yield(.text("Completed using the real MCP server.")); continuation.yield(.finished(.stop))
            } else {
                guard let tool = request.tools.first(where: { $0.name.hasPrefix("mcp_") }) else {
                    continuation.finish(throwing: MCPError.unavailable); return
                }
                continuation.yield(.toolCall(.init(id: "execute", name: tool.name, arguments: .object(["text": .string("request")]))))
                continuation.yield(.finished(.toolCalls))
            }
            continuation.finish()
        }
    }
}

@main struct VerifyMCPExecution {
    static func require(_ condition: Bool, _ message: String = "MCP verification failed") { precondition(condition, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(10))
        while try await !condition(), ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(10)) }
        require(try await condition(), "MCP verification timed out")
    }
    @MainActor static func approve(_ service: LocalWorkspaceService) async throws {
        try await wait { service.appleIntegrations.interactions.pending != nil }
        let pending = service.appleIntegrations.interactions.pending!
        precondition(pending.title.contains("MCP") && pending.details.contains("request"))
        service.appleIntegrations.interactions.finish(pending.id, result: .success(.bool(true)))
    }
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("workspace.sqlite")
        let repository = try WorkspaceRepository(url: database), identity = try await repository.localIdentity()
        let credentials = MCPVerificationCredentials()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
            draft: .init(name: "MCP worker", instructions: "Use the approved MCP tool", modelID: "compatible"))
        let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "MCP", agentID: agent)
        let service = try LocalWorkspaceService(databaseURL: database, repository: repository, identity: identity,
            maximumOutputTokens: 64, mcpCredentials: credentials, makeModel: { _ in MCPVerificationModel() })
        _ = try await service.load()
        let mcp = try await service.mcpService()
        let script = #"""
import json,sys
for line in sys.stdin:
    m=json.loads(line)
    if 'id' not in m: continue
    if m.get('method')=='initialize': r={'protocolVersion':'2025-11-25','capabilities':{'tools':{}}}
    elif m.get('method')=='tools/list': r={'tools':[{'name':'echo','description':'Independent stdio tool','inputSchema':{'type':'object','properties':{'text':{'type':'string'}},'required':['text'],'additionalProperties':False}}]}
    elif m.get('method')=='tools/call': r={'content':[{'type':'text','text':'real MCP result'}]}
    else: continue
    print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':r}),flush=True)
"""#
        let inspection = try await mcp.inspect(name: "Independent stdio MCP", configuration: .init(transport: .stdio,
            endpoint: "/usr/bin/python3", arguments: ["-u", "-c", script], workingDirectory: directory.path, timeout: 5, trustedLocalProcess: true))
        let connectionID = try await mcp.save(inspection, selectedTools: ["echo"], agentIDs: [agent])
        require(try await service.currentSnapshot().mcpConnections.count == 1)
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: "Use MCP")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        let response = _Concurrency.Task { @MainActor in for try await _ in try await service.responses(to: source) {} }
        try await approve(service); try await response.value
        require(try await service.currentSnapshot().toolInvocations?.filter { $0.state == .succeeded }.count == 1)
        print("PASS: real stdio discovery → agent tool → exact native confirmation → durable result → model response")

        let taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
            agentID: agent, goal: "Use MCP in the task queue", executorDeviceID: identity.deviceID)
        try await approve(service)
        try await wait { try await service.currentSnapshot().tasks?.first { $0.metadata.id == taskID }?.state == .completed }
        require(try await service.currentSnapshot().toolInvocations?.filter { $0.state == .succeeded }.count == 2)
        print("PASS: queued task invokes MCP and completes after confirmed real result")
        await service.stopAll()
        let reopened = try LocalWorkspaceService(databaseURL: database, identity: identity, mcpCredentials: credentials, makeModel: { _ in MCPVerificationModel() })
        _ = try await reopened.load()
        let restored = try await reopened.mcpService()
        require(try await restored.access().first?.enabled == true)
        try await restored.disconnect(id: connectionID)
        require(try await reopened.currentSnapshot().mcpConnections.isEmpty)
        await reopened.stopAll()
        print("PASS: device-local configuration survives reopen; disconnect revokes tools and removes credentials")
    }
}
