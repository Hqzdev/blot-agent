import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

private actor NativeVerificationCredentials: WorkspaceCredentialStore {
    private var values: [String: Data] = [:]
    func read(_ name: String) -> Data? { values[name] }
    func write(_ value: Data, name: String) { values[name] = value }
    func remove(_ name: String) { values[name] = nil }
}

private actor NativeVerificationModel: ChatModel {
    private var polls = 0
    private func events(_ request: ChatModelRequest) throws -> [ChatModelEvent] {
        let tools = request.messages.filter { $0.role == "tool" }
        let queued = request.messages.last(where: { $0.role == "user" })?.content.contains("Second native task") == true
        let content = queued ? "after queued\n" : "after\n"
        func result(_ name: String) -> ChatJSON? {
            tools.last(where: { $0.name == name }).flatMap { try? JSONDecoder().decode(ChatJSON.self, from: Data($0.content.utf8)) }
        }
        func fields(_ value: ChatJSON?) -> [String: ChatJSON] { if case .object(let fields) = value { fields } else { [:] } }
        let call: ChatToolCall
        if result("project_read_file") == nil {
            call = .init(id: "read", name: "project_read_file", arguments: .object(["path": .string("a.txt")]))
        } else if result("project_write_file") == nil {
            guard let hash = fields(result("project_read_file"))["sha256"] else { throw NativeExecutionError.unknown }
            call = .init(id: "write", name: "project_write_file", arguments: .object(["path": .string("a.txt"), "content": .string(content), "expected_hash": hash]))
        } else if result("process_run") == nil {
            call = .init(id: "run", name: "process_run", arguments: .object(["executable": .string("/bin/sh"), "arguments": .array([.string("-c"), .string(queued ? "test \"$(cat a.txt)\" = 'after queued' && printf build-ok" : "test \"$(cat a.txt)\" = after && printf build-ok")])]))
        } else if fields(result("process_status"))["state"] != .string("succeeded") {
            polls += 1
            guard polls < 15, let id = fields(result("process_run"))["process_id"] else { throw NativeExecutionError.unknown }
            call = .init(id: "poll-\(polls)", name: "process_status", arguments: .object(["process_id": id]))
        } else if result("git_prepare_commit") == nil {
            call = .init(id: "prepare", name: "git_prepare_commit", arguments: .object(["paths": .array([.string("a.txt")]), "message": .string("Verified native task")]))
        } else if result("git_commit") == nil {
            guard let id = fields(result("git_prepare_commit"))["preparation_id"] else { throw NativeExecutionError.unknown }
            call = .init(id: "commit", name: "git_commit", arguments: .object(["preparation_id": id]))
        } else {
            guard fields(result("git_commit"))["state"] == .string("succeeded") else { throw NativeExecutionError.unknown }
            return [.text("Code changed, command passed, exact commit created."), .finished(.stop)]
        }
        guard request.tools.contains(where: { $0.name == call.name }) else { throw NativeExecutionError.accessDenied }
        return [.toolCall(call), .finished(.toolCalls)]
    }
    nonisolated func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            _Concurrency.Task {
                do {
                    try await _Concurrency.Task.sleep(for: .milliseconds(80))
                    continuation.yield(.usage(try ChatModelUsage(inputTokens: 50, outputTokens: 10)))
                    for event in try await events(request) { continuation.yield(event) }; continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
        }
    }
}

@main struct VerifyNativeExecution {
    static func require(_ value: Bool, _ message: String = "Native verification failed") { precondition(value, message) }
    @MainActor static func wait(_ condition: () async throws -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: .seconds(20))
        while try await !condition(), ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(20)) }
        require(try await condition(), "Native verification timed out")
    }
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("workspace.sqlite")), identity = try await repository.localIdentity()
        let code = directory.appendingPathComponent("code"); try FileManager.default.createDirectory(at: code, withIntermediateDirectories: true)
        let executor = NativeXPCClient()
        for args in [["init", "-b", "mac/native-check"], ["config", "user.name", "Native verification"], ["config", "user.email", "native@example.test"]] {
            try await git(executor, root: code, args: args)
        }
        try Data("before\n".utf8).write(to: code.appendingPathComponent("a.txt"))
        try Data("user\n".utf8).write(to: code.appendingPathComponent("user.txt"))
        try await git(executor, root: code, args: ["add", "."]); try await git(executor, root: code, args: ["commit", "-m", "Initial"])
        try Data("user staged\n".utf8).write(to: code.appendingPathComponent("user.txt")); try await git(executor, root: code, args: ["add", "user.txt"])
        await executor.stopAll()
        let credentials = NativeVerificationCredentials()
        let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "Engineer", instructions: "Complete the coding task with tools", modelID: "compatible"))
        let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Native", agentID: agent)
        var model = NativeVerificationModel()
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"), repository: repository, identity: identity,
            maximumOutputTokens: 64, mcpCredentials: credentials, makeModel: { _ in model })
        _ = try await service.load()
        let native = try await service.nativeService()
        let project = try await native.connect(name: "Native test", root: code, bookmark: nil, agents: [agent], trustedCLI: true)
        try await native.select(projectID: project, conversationID: conversation)
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: "Change a.txt, verify it and commit the exact change")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        let approvals = _Concurrency.Task { @MainActor in
            while !_Concurrency.Task.isCancelled {
                if let pending = service.appleIntegrations.interactions.pending {
                    require(pending.details.contains("Native test"), "Wrong confirmation project")
                    service.appleIntegrations.interactions.finish(pending.id, result: .success(.bool(true)))
                }
                try? await _Concurrency.Task.sleep(for: .milliseconds(10))
            }
        }
        defer { approvals.cancel() }
        for try await _ in try await service.responses(to: source) {}
        let first = try await service.currentSnapshot()
        require(first.toolInvocations?.filter { $0.state == .succeeded }.count == 3, "Expected write, process and commit")
        require(first.artifacts.contains { $0.name.hasSuffix(".log") }, "Command log was not saved")
        let status = try await native.inspect(projectID: project, operation: .gitStatus)
        require(status.contains("user.txt") && !status.contains("a.txt"), "User staging or final task tree changed unexpectedly")
        print("PASS: chat → read/hash → exact write → signed XPC command → poll/log → prepared diff → approved exact commit; user staging preserved")

        model = NativeVerificationModel()
        let task = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
            agentID: agent, goal: "Second native task: change a.txt, verify it and commit the exact change", executorDeviceID: identity.deviceID, projectID: project)
        try await wait { try await service.currentSnapshot().tasks?.first { $0.metadata.id == task }?.state == .completed }
        print("PASS: project-bound queue task executes native tools and completes from actual results")
        await service.stopAll()
        let reopened = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"), identity: identity, mcpCredentials: credentials, makeModel: { _ in NativeVerificationModel() })
        _ = try await reopened.load()
        require(try await reopened.nativeService().projects().count == 1)
        require(try await reopened.currentSnapshot().projects?.first?.repositoryPath == "device:" + identity.deviceID.uuidString)
        try await reopened.nativeService().disconnect(project)
        require(try await reopened.nativeService().projects().isEmpty)
        await reopened.stopAll()
        print("PASS: project identity and local authority persist across reopen; disconnect revokes access")
    }
    static func git(_ executor: NativeXPCClient, root: URL, args: [String]) async throws {
        let command = NativeCommand(projectID: UUID(), root: root.path, executable: "/usr/bin/git", arguments: args,
            environment: ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"])
        _ = try await executor.request(.init(.start, command: command))
        for _ in 0..<200 {
            let json = try await executor.request(.init(.status, command: command))
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let value = try decoder.decode(NativeProcessSnapshot.self, from: JSONEncoder().encode(json))
            if value.finishedAt != nil { require(value.exitCode == 0, value.stderr); return }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
        throw NativeExecutionError.unavailable
    }
}
