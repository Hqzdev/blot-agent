import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

#if os(macOS)
private actor SessionCredentials: WorkspaceCredentialStore {
    var data: [String: Data] = [:]
    func read(_ name: String) -> Data? { data[name] }
    func write(_ value: Data, name: String) { data[name] = value }
    func remove(_ name: String) { data[name] = nil }
}
private actor SessionExecutor: NativeExecuting {
    let implementation: NativeExecutor
    private(set) var requests = 0
    private var loseReply = false
    init(home: URL) { implementation = NativeExecutor(workspaceHome: home) }
    func dropWriteReply() { loseReply = true }
    func request(_ request: NativeRequest) async throws -> ChatJSON {
        requests += 1
        let value = try await implementation.request(request)
        if loseReply && request.operation == .workspaceWrite { loseReply = false; throw NativeExecutionError.unknown }
        return value
    }
    func stopAll() async { await implementation.stopAll() }
}
private struct SessionFixture {
    let folder: URL
    let home: URL
    let repository: WorkspaceRepository
    let identity: WorkspaceIdentity
    let executor: SessionExecutor
    let files: WorkspaceSessionFileService
    let tools: WorkspaceSessionFileTools
    let agent: UUID
    let conversation: UUID
    let source: UUID
    init(request: String = "Create files in my Blot folder", choice: WorkspaceDirectoryChoice? = nil, observe: Bool = false) async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BlotSessionFiles-" + UUID().uuidString).resolvingSymlinksInPath()
        home = folder.appendingPathComponent("Home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        repository = try await workspaceTestRepository(url: folder.appendingPathComponent("workspace.sqlite"))
        identity = try await repository.localIdentity()
        executor = SessionExecutor(home: home)
        files = WorkspaceSessionFileService(repository: repository, identity: identity, credentials: SessionCredentials(), makeExecutor: { [executor] in executor }, choose: { _, _ in choice })
        agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(), draft: .init(name: "File worker", instructions: "Use builtin file tools", toolIDs: WorkspaceSessionFileCatalog.toolIDs.sorted(), accessMode: observe ? .observe : .ask_first))
        conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "File session", agentID: agent)
        source = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation, content: request)
        tools = WorkspaceSessionFileTools(service: files, repository: repository, identity: identity)
    }
    var context: WorkspaceToolContext { .init(sourceMessageID: source, taskID: nil, allowedToolIDs: WorkspaceSessionFileCatalog.toolIDs, agentID: agent) }
    func call(_ name: String, _ fields: [String: ChatJSON], id: String = UUID().uuidString) -> ChatToolCall { .init(id: id, name: name, arguments: .object(fields)) }
    func root() async throws -> URL {
        let result = try await tools.execute(call("workspace_directory", [:]), context: context)
        #expect(result.mcpFields["path"]?.mcpString?.hasPrefix("~/Blot/") == true)
        let local = try await files.prepare(conversationID: conversation)
        return URL(fileURLWithPath: try #require(local.mcpFields["files_root"]?.mcpString))
    }
}

@Test func automaticSessionFilesCreateDirectoriesWriteWithCASAndReplayWithoutAPlugin() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let root = try await f.root()
    #expect(root.path.hasPrefix(f.home.appendingPathComponent("Blot/Sessions").path))
    #expect(try await f.repository.projection(identity: f.identity).connections.isEmpty)
    let directory = try await f.tools.execute(f.call("workspace_create_directory", ["path": .string("Reports/June")]), context: f.context)
    #expect(directory.mcpFields["state"] == .string("succeeded"))
    let call = f.call("workspace_write_file", ["path": .string("Reports/June/report.txt"), "content": .string("First result"), "expected_hash": .string("missing")], id: "create-report")
    let saved = try await f.tools.execute(call, context: f.context)
    let count = await f.executor.requests
    #expect(saved.mcpFields["state"] == .string("succeeded"))
    #expect(try await f.tools.execute(call, context: f.context) == saved)
    #expect(await f.executor.requests == count)
    let file = root.appendingPathComponent("Reports/June/report.txt")
    #expect(try String(contentsOf: file, encoding: .utf8) == "First result")
    let stale = try await f.tools.execute(f.call("workspace_write_file", ["path": .string("Reports/June/report.txt"), "content": .string("Overwrite"), "expected_hash": .string("missing")]), context: f.context)
    #expect(stale.mcpFields["state"] == .string("failed"))
    let read = try await f.tools.execute(f.call("workspace_read_file", ["path": .string("Reports/June/report.txt")]), context: f.context)
    let changed = try await f.tools.execute(f.call("workspace_write_file", ["path": .string("Reports/June/report.txt"), "content": .string("Updated result"), "expected_hash": read.mcpFields["sha256"]!]), context: f.context)
    #expect(changed.mcpFields["state"] == .string("succeeded"))
    #expect(try String(contentsOf: file, encoding: .utf8) == "Updated result")
    await f.files.suspend()
}

@Test func sessionFilesDenyTraversalSymlinksManagedHashAndForeignDirectories() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let root = try await f.root(), outside = f.folder.appendingPathComponent("Outside")
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data("Private".utf8).write(to: outside.appendingPathComponent("secret.txt"))
    try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
    for path in ["../Session.json", "/etc/passwd", "escape/secret.txt"] {
        let result = try await f.tools.execute(f.call("workspace_read_file", ["path": .string(path)]), context: f.context)
        #expect(result.mcpFields["state"] == .string("failed"))
    }
    let escaped = try await f.tools.execute(f.call("workspace_create_directory", ["path": .string("escape/created")]), context: f.context)
    #expect(escaped.mcpFields["state"] == .string("failed"))
    #expect(!FileManager.default.fileExists(atPath: outside.appendingPathComponent("created").path))
    let managed = try await f.tools.execute(f.call("workspace_write_file", ["path": .string("file.txt"), "content": .string("Bypass"), "expected_hash": .string("managed")]), context: f.context)
    #expect(managed.mcpFields["state"] == .string("failed"))
    let foreign = try await f.tools.execute(f.call("workspace_list_files", ["directory_id": .string(UUID().uuidString)]), context: f.context)
    #expect(foreign.mcpFields["state"] == .string("failed"))
    await f.files.suspend()
}

@Test func directoryPickerDenialAndObserveModeDoNotGrantWriteAccess() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let result = try await f.tools.execute(f.call("workspace_request_directory", ["purpose": .string("Create a report elsewhere"), "folder_name": .string("Reports")]), context: f.context)
    #expect(result.mcpFields["state"] == .string("failed")); #expect(try await f.files.directories().isEmpty)
    let reader = try await SessionFixture(observe: true); defer { cleanupWorkspaceTestStorage(reader.folder) }
    #expect(try await reader.tools.availableDefinitions(context: reader.context).allSatisfy { !WorkspaceSessionFileCatalog.writes($0.name) })
    let write = try await reader.tools.execute(reader.call("workspace_create_directory", ["path": .string("No")]), context: reader.context)
    #expect(write.mcpFields["state"] == .string("failed"))
    let local = WorkspaceLocalTools(repository: reader.repository, identity: reader.identity,
        files: WorkspaceFileService(repository: reader.repository, identity: reader.identity, directory: reader.folder.appendingPathComponent("Attachments")))
    let documentContext = WorkspaceToolContext(sourceMessageID: reader.source, taskID: nil, allowedToolIDs: ["document_create"], agentID: reader.agent)
    #expect(try await local.availableDefinitions(context: documentContext).isEmpty)
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        _ = try await local.execute(.init(id: "pdf", name: "document_create", arguments: .object(["name": .string("Denied"), "format": .string("pdf"), "content": .string("No writes")])), context: documentContext)
    }
    await f.files.suspend(); await reader.files.suspend()
}

@Test func sessionMirrorWritesChangedFinalRecordsAndPreservesWorkingFiles() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let root = try await f.root(), session = root.deletingLastPathComponent()
    let mirror = WorkspaceSessionMirror(repository: f.repository, identity: f.identity, files: f.files, indexURL: f.folder.appendingPathComponent("Mirror.json"))
    await mirror.synchronize()
    #expect(await mirror.lastError == nil)
    #expect(FileManager.default.fileExists(atPath: session.appendingPathComponent("Session.json").path))
    let message = session.appendingPathComponent("Messages/" + f.source.uuidString + ".json")
    #expect(try String(contentsOf: message, encoding: .utf8).contains("Create files in my Blot folder"))
    let count = await f.executor.requests
    await mirror.synchronize()
    #expect(await f.executor.requests == count)
    _ = try await f.tools.execute(f.call("workspace_write_file", ["path": .string("keep.txt"), "content": .string("User work"), "expected_hash": .string("missing")]), context: f.context)
    let reopened = WorkspaceSessionMirror(repository: f.repository, identity: f.identity, files: f.files, indexURL: f.folder.appendingPathComponent("Mirror.json"))
    let before = await f.executor.requests
    await reopened.synchronize()
    #expect(await f.executor.requests == before)
    #expect(try String(contentsOf: root.appendingPathComponent("keep.txt"), encoding: .utf8) == "User work")
    await f.files.suspend()
}

@Test func builtInToolsDoNotConsumeAssignedPluginCapacity() throws {
    let plugins = (0..<100).map { "plugin_\($0)" }
    let builtIn = WorkspaceSessionFileCatalog.toolIDs.union(WorkspaceBrowserCatalog.toolIDs)
    try WorkspaceAgentDraft(name: "Worker", instructions: "Work", toolIDs: plugins + builtIn.sorted()).validate()
    #expect(throws: Error.self) { try WorkspaceAgentDraft(name: "Worker", instructions: "Work", toolIDs: plugins + ["one_more"] + builtIn.sorted()).validate() }
}

@Test func externalDirectoryGrantIsBoundToTheChatAndCanBeRevoked() async throws {
    let f = try await SessionFixture(choice: .init(path: "/owner-selected/Folder", bookmark: Data())); defer { cleanupWorkspaceTestStorage(f.folder) }
    let request = f.call("workspace_request_directory", ["purpose": .string("Use the selected folder")], id: "choose")
    let granted = try await f.tools.execute(request, context: f.context)
    #expect(granted.mcpFields["state"] == .string("granted"))
    #expect(granted.mcpFields["path"] == nil)
    #expect(try await f.tools.execute(request, context: f.context) == granted)
    let id = try #require(granted.mcpFields["directory_id"]?.mcpString)
    let chat = try await WorkspaceChatService(repository: f.repository, identity: f.identity).createConversation(commandID: UUID(), title: "Other session", agentID: f.agent)
    let source = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(), conversationID: chat, content: "Read the folder")
    let context = WorkspaceToolContext(sourceMessageID: source, taskID: nil, allowedToolIDs: WorkspaceSessionFileCatalog.toolIDs, agentID: f.agent)
    let result = try await f.tools.execute(f.call("workspace_list_files", ["directory_id": .string(id)]), context: context)
    #expect(result.mcpFields["state"] == .string("failed"))
    try await f.files.revokeDirectory(UUID(uuidString: id)!)
    #expect(try await f.files.directories().isEmpty)
    await f.files.suspend()
}

@Test func sessionMirrorCopiesBinaryArtifactsWithoutOverwritingUserEdits() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let root = try await f.root(), session = root.deletingLastPathComponent()
    let artifacts = WorkspaceFileService(repository: f.repository, identity: f.identity, directory: f.folder.appendingPathComponent("Attachments"))
    let data = Data([0, 255, 128, 10, 1, 2, 3])
    let id = try await artifacts.store(commandID: UUID(), name: "binary.dat", mediaType: "application/octet-stream", data: data)
    _ = try await WorkspaceChatService(repository: f.repository, identity: f.identity).sendMessage(commandID: UUID(), conversationID: f.conversation, content: "Read the attached file", artifactIDs: [id])
    let mirror = WorkspaceSessionMirror(repository: f.repository, identity: f.identity, files: f.files, indexURL: f.folder.appendingPathComponent("Mirror.json"), artifacts: artifacts)
    await mirror.synchronize()
    #expect(await mirror.lastError == nil)
    let output = session.appendingPathComponent("Artifacts/" + id.uuidString + "/binary.dat")
    #expect(try Data(contentsOf: output) == data)
    try Data("User edit".utf8).write(to: output)
    let reopened = WorkspaceSessionMirror(repository: f.repository, identity: f.identity, files: f.files, indexURL: f.folder.appendingPathComponent("Mirror.json"), artifacts: artifacts)
    await reopened.synchronize()
    #expect(try Data(contentsOf: output) == Data("User edit".utf8))
    await f.files.suspend()
}

@Test func lostSessionWriteReplyRequiresVerificationAndDoesNotRepeatTheWrite() async throws {
    let f = try await SessionFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let root = try await f.root(); await f.executor.dropWriteReply()
    let result = try await f.tools.execute(f.call("workspace_write_file", ["path": .string("result.txt"), "content": .string("Written once"), "expected_hash": .string("missing")]), context: f.context)
    #expect(result.mcpFields["state"] == .string("unknown"))
    #expect(try String(contentsOf: root.appendingPathComponent("result.txt"), encoding: .utf8) == "Written once")
    #expect(try await f.tools.availableDefinitions(context: f.context).allSatisfy { !WorkspaceSessionFileCatalog.writes($0.name) })
    let projection = try await f.repository.projection(identity: f.identity)
    let invocation = try #require(projection.invocations.first { $0.state == .unknown })
    let before = await f.executor.requests
    try await f.files.resolve(invocationID: invocation.metadata.id, succeeded: true)
    #expect(await f.executor.requests == before)
    #expect(try await f.repository.record(BlotV3.Task.self, id: invocation.execution.taskId, workspaceID: f.identity.workspaceID)?.state == .completed)
    await f.files.suspend()
}
#endif
