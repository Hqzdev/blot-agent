import AppKit
import BlotDomain
import BlotWorkspace
import Foundation

private actor SessionVerificationCredentials: WorkspaceCredentialStore {
    var data: [String: Data] = [:]
    func read(_ name: String) -> Data? { data[name] }
    func write(_ value: Data, name: String) { data[name] = value }
    func remove(_ name: String) { data[name] = nil }
}
private struct SessionVerificationModel: ChatModel {
    let agent: UUID
    let picker: Bool
    func stream(request: ChatModelRequest) -> AsyncThrowingStream<ChatModelEvent, Error> {
        AsyncThrowingStream { continuation in
            do {
                let systems = request.messages.filter { $0.role == "system" }.map(\.content).joined(separator: "\n")
                continuation.yield(.usage(try ChatModelUsage(inputTokens: 50, outputTokens: 10)))
                if systems.contains("Select the interaction mode") {
                    continuation.yield(.text("{\"mode\":\"specialist\",\"agentID\":\"\(agent)\"}")); continuation.yield(.finished(.stop)); continuation.finish(); return
                }
                if !request.messages.contains(where: { $0.content.contains("Queued file task") }) { precondition(systems.contains("Local file work is built in")) }
                func result(_ name: String) -> [String: ChatJSON]? {
                    guard let value = request.messages.last(where: { $0.role == "tool" && $0.name == name }),
                          let decoded = try? JSONDecoder().decode(ChatJSON.self, from: Data(value.content.utf8)), case .object(let fields) = decoded else { return nil }
                    return fields
                }
                let queued = request.messages.last(where: { $0.role == "user" })?.content.contains("Queued file task") == true
                let filename = queued ? "Reports/queued.txt" : "Reports/result.txt"
                let directoryID = result("workspace_request_directory")?["directory_id"]
                var arguments: [String: ChatJSON] = [:]
                if let directoryID { arguments["directory_id"] = directoryID }
                let call: ChatToolCall
                if picker, result("workspace_request_directory") == nil {
                    call = .init(id: "directory-request", name: "workspace_request_directory", arguments: .object(["purpose": .string("Проверка Blot: создать тестовую папку и записать в неё файл. Выберите только подготовленный тестовый каталог."), "folder_name": .string("ApprovedFolder")]))
                } else if !picker, result("workspace_directory") == nil {
                    call = .init(id: "directory", name: "workspace_directory", arguments: .object([:]))
                } else if result("workspace_create_directory") == nil {
                    arguments["path"] = .string("Reports")
                    call = .init(id: "mkdir", name: "workspace_create_directory", arguments: .object(arguments))
                } else if result("workspace_write_file") == nil {
                    arguments["path"] = .string(filename); arguments["content"] = .string("Created by Blot\n"); arguments["expected_hash"] = .string("missing")
                    call = .init(id: "write", name: "workspace_write_file", arguments: .object(arguments))
                } else if result("workspace_read_file") == nil {
                    arguments["path"] = .string(filename)
                    call = .init(id: "read", name: "workspace_read_file", arguments: .object(arguments))
                } else if !picker && !queued && result("document_create") == nil {
                    call = .init(id: "pdf", name: "document_create", arguments: .object(["name": .string("Summary"), "format": .string("pdf"), "content": .string("Generated session document")]))
                } else {
                    precondition(result("workspace_read_file")?["content"] == .string("Created by Blot\n"))
                    continuation.yield(.text("File created and verified inside the approved directory.")); continuation.yield(.finished(.stop)); continuation.finish(); return
                }
                precondition(request.tools.contains { $0.name == call.name })
                continuation.yield(.toolCall(call)); continuation.yield(.finished(.toolCalls)); continuation.finish()
            } catch { continuation.finish(throwing: error) }
        }
    }
}

@MainActor @main
struct VerifySessionFiles {
    static var completionWindow: NSWindow?
    static func main() {
        setbuf(stdout, nil)
        let picker = CommandLine.arguments.contains("--picker-test")
        let app = NSApplication.shared; app.setActivationPolicy(picker ? .regular : .accessory)
        _Concurrency.Task { @MainActor in
            do {
                if picker {
                    try await verify(group: false, picker: true)
                    let window = NSWindow(contentRect: CGRect(x: 150, y: 150, width: 620, height: 180), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                    window.title = "Blot — проверка доступа к папке завершена"
                    let text = NSTextField(wrappingLabelWithString: "Папка создана после выбора родительского каталога. Файл записан и прочитан через сохранённый bookmark. Тестовая сессия удалена; посторонние данные не затронуты.")
                    text.frame = CGRect(x: 24, y: 24, width: 570, height: 110); window.contentView?.addSubview(text)
                    completionWindow = window; window.makeKeyAndOrderFront(nil); app.activate(ignoringOtherApps: true)
                } else {
                    try await verify(group: false, picker: false)
                    try await verify(group: true, picker: false)
                    print("PASS: automatic session files and real signed XPC verification completed"); exit(0)
                }
            } catch { print("FAIL: \(error)"); exit(1) }
        }
        app.run()
    }
    static func verify(group: Bool, picker: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlotFileVerification-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try WorkspaceRepository(url: directory.appendingPathComponent("workspace.sqlite")), identity = try await repository.localIdentity()
        let agents = WorkspaceAgentService(repository: repository, identity: identity)
        let agent = try await agents.save(commandID: UUID(), draft: .init(name: "Writer", instructions: "Use the built-in file tools", modelID: "compatible"))
        let conversation: UUID
        if group {
            let other = try await agents.save(commandID: UUID(), draft: .init(name: "Colleague", instructions: "Help only when needed", modelID: "compatible"))
            conversation = try await WorkspaceGroupService(repository: repository, identity: identity).create(commandID: UUID(), title: "File team", agentIDs: [agent, other])
        } else { conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "File session", agentID: agent) }
        let service = try LocalWorkspaceService(databaseURL: directory.appendingPathComponent("workspace.sqlite"), repository: repository, identity: identity,
            maximumOutputTokens: 128, mcpCredentials: SessionVerificationCredentials(), automaticBrowserAccess: true, automaticSessionFiles: true,
            makeModel: { _ in SessionVerificationModel(agent: agent, picker: picker) })
        _ = try await service.load()
        guard service.sessionFilesFailure == nil, let files = try await service.sessionFileService() else { throw NativeExecutionError.unavailable }
        let prepared = try await files.prepare(conversationID: conversation)
        guard case .object(let fields) = prepared, case .string(let root) = fields["files_root"], case .string(let session) = fields["session_root"] else { throw NativeExecutionError.unknown }
        precondition(root.hasPrefix("/Users/") && root.contains("/Blot/Sessions/"))
        if picker {
            _ = try await files.request(.workspaceMkdir, root: session, parameters: ["path": "PickerParent"])
            print("PICKER_PARENT=" + session + "/PickerParent")
        }
        let sourceID = try await WorkspaceChatService(repository: repository, identity: identity).sendMessage(commandID: UUID(), conversationID: conversation,
            content: picker ? "Create a folder elsewhere and write the verification file after I choose its parent" : "Create a Reports directory in Blot and write result.txt there")
        let source = try await repository.record(BlotV3.Message.self, id: sourceID, workspaceID: identity.workspaceID)!
        for try await _ in try await service.responses(to: source) {}
        let snapshot = try await service.currentSnapshot()
        precondition(snapshot.messages.contains { $0.role == .assistant && $0.content.contains("File created and verified") })
        precondition(snapshot.connections.isEmpty)
        if !picker {
            let read = try await files.request(.workspaceRead, root: root, parameters: ["path": "Reports/result.txt"])
            precondition(read.fields["content"] == .string("Created by Blot\n"))
        }
        await service.sessionMirror?.synchronize()
        let mirrorError = await service.sessionMirror?.lastError
        precondition(mirrorError == nil)
        let history = try await files.request(.workspaceRead, root: session, parameters: ["path": "Messages/" + sourceID.uuidString + ".json"])
        precondition(history.fields["content"]?.string?.contains("Create") == true)
        if !picker {
            guard let artifact = snapshot.artifacts.first(where: { $0.name == "Summary.pdf" }) else { throw NativeExecutionError.unknown }
            let exported = try await files.request(.workspaceList, root: session, parameters: ["path": "Artifacts/" + artifact.metadata.id.uuidString])
            guard case .array(let entries) = exported.fields["entries"] else { throw NativeExecutionError.unknown }
            precondition(entries.contains { $0.fields["name"] == .string("Summary.pdf") })
            print("PASS: generated PDF is copied from the app container into the visible session Artifacts directory")
        }
        if !group && !picker {
            let task = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
                agentID: agent, goal: "Queued file task: create queued.txt in Reports", executorDeviceID: identity.deviceID)
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while ContinuousClock.now < deadline {
                let state = try await repository.record(BlotV3.Task.self, id: task, workspaceID: identity.workspaceID)!.state
                if state == .completed { break }
                if [.failed, .interrupted].contains(state) { throw NativeExecutionError.unknown }
                try await _Concurrency.Task.sleep(for: .milliseconds(20))
            }
            let read = try await files.request(.workspaceRead, root: root, parameters: ["path": "Reports/queued.txt"])
            precondition(read.fields["content"] == .string("Created by Blot\n"))
            print("PASS: queued task uses the same automatic session files without plugin assignment")
        }
        try await service.close()
        try await LocalWorkspaceService.eraseSessionFiles(ownerID: identity.ownerID)
        print("PASS: \(picker ? "native directory picker, bookmark and new folder" : group ? "group" : "chat") → built-in file tools → actual ~/Blot files → session history → scoped cleanup")
    }
}

private extension ChatJSON {
    var fields: [String: ChatJSON] { if case .object(let value) = self { value } else { [:] } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
}
