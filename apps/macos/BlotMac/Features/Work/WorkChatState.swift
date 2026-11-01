import BlotDesign
import Foundation
import Observation
import BlotAPI

struct WorkChatMessage: Identifiable {
    let id: UUID
    init(id: UUID = UUID(), text: String, fromUser: Bool) { self.id = id; self.text = text; self.fromUser = fromUser }
    let text: String
    let fromUser: Bool
}

struct WorkChatProject: Identifiable {
    let id: String
    let name: String
}

@Observable
final class WorkChatSession: Identifiable {
    let id: String
    private(set) var title: String
    let projectID: String?
    let assistant: AssistantProfile?
    private(set) var messages: [WorkChatMessage] = []
    private(set) var pendingMessage: WorkChatMessage?
    var visibleMessages: [WorkChatMessage] { messages + (pendingMessage.map { [$0] } ?? []) }
    var draft = ""
    private(set) var isSending = false
    private(set) var error: String?
    var backendID: UUID?
    private let createCommandID = UUID()
    private var pendingCommandID: UUID?
    private var pendingText: String?
    private var generationID: UUID?
    private var observation: _Concurrency.Task<Void, Never>?
    private(set) var canRetry = false

    init(id: String = UUID().uuidString, title: String, projectID: String? = nil,
         messages: [WorkChatMessage] = [], assistant: AssistantProfile? = nil) {
        self.id = id
        self.title = title
        self.projectID = projectID
        self.messages = messages
        self.assistant = assistant
    }

    func send(_ text: String) {
        guard !isSending else { return }
        isSending = true
        error = nil
        let commandID = pendingCommandID ?? UUID()
        pendingCommandID = commandID
        let content = pendingText ?? text
        pendingText = content
        pendingMessage = WorkChatMessage(text: content, fromUser: true)
        observation = Task {
            do {
                let client = BackendRuntime.shared.client
                if backendID == nil {
                    let receipt = try await client.command("conversation.create", payload: ["title": title], projectId: projectID.flatMap(UUID.init(uuidString:)), commandId: createCommandID)
                    backendID = try receipt.result.decode(BackendEntity<BackendJSON>.self).id
                }
                guard let backendID else { throw URLError(.cannotParseResponse) }
                nonisolated struct Message: Encodable, Sendable { let conversationId: UUID; let content: String }
                let receipt = try await client.command("conversation.send_message", payload: Message(conversationId: backendID, content: content), commandId: commandID)
                pendingCommandID = nil; pendingText = nil
                draft = ""
                generationID = receipt.operationId
                try await refreshMessages(backendID)
                pendingMessage = nil
                await observeGeneration(receipt.operationId)

            } catch let failure as BackendFailure {
                if failure.isDefiniteRejection { pendingCommandID = nil; pendingText = nil }
                self.error = failure.localizedDescription
            } catch { self.error = error.localizedDescription }
            isSending = false
        }
    }

    func loadHistory() async throws {
        guard let backendID else { return }
        try await refreshMessages(backendID)
        let jobs = try await BackendRuntime.shared.client.records("GENERATION", parentId: backendID, as: GenerationValue.self)
        if let active = jobs.last(where: { ["QUEUED", "RUNNING"].contains($0.data.status) }), observation == nil {
            generationID = active.id; isSending = true
            observation = Task { await observeGeneration(active.id); isSending = false }
        } else if let failed = jobs.last, ["FAILED", "INTERRUPTED"].contains(failed.data.status) {
            generationID = failed.id; canRetry = true; error = failed.data.error
        }
    }

    func cancel() {
        guard let generationID, isSending else { return }
        Task {
            do { _ = try await BackendRuntime.shared.client.command("generation.cancel", payload: ["id": generationID.uuidString]) }
            catch { self.error = error.localizedDescription }
        }
    }

    func retry() {
        guard let generationID, canRetry, !isSending else { return }
        isSending = true; error = nil
        observation = Task {
            do {
                let client = BackendRuntime.shared.client
                let previous = try await client.get("v2/records/GENERATION/\(generationID.uuidString)", as: BackendEntity<GenerationValue>.self)
                let receipt = try await client.command("generation.retry", payload: ["id": generationID.uuidString], expectedVersion: previous.version)
                self.generationID = receipt.operationId
                await observeGeneration(receipt.operationId)
            } catch { self.error = error.localizedDescription }
            isSending = false
        }
    }

    func stopObserving() { observation?.cancel(); observation = nil }

    private func observeGeneration(_ id: UUID) async {
        canRetry = false
        while !Task.isCancelled {
            do {
                guard let backendID else { break }
                try await refreshMessages(backendID)
                let generation = try await BackendRuntime.shared.client.get("v2/records/GENERATION/\(id.uuidString)", as: BackendEntity<GenerationValue>.self)
                error = nil
                if !["QUEUED", "RUNNING"].contains(generation.data.status) {
                    canRetry = ["FAILED", "INTERRUPTED"].contains(generation.data.status)
                    if generation.data.status != "COMPLETED" { error = generation.data.error ?? generation.data.status }
                    break
                }
                try await Task.sleep(for: .milliseconds(500))
            } catch is CancellationError { break }
            catch let failure as BackendFailure { error = failure.localizedDescription; break }
            catch {
                self.error = error.localizedDescription
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }

    private func refreshMessages(_ id: UUID) async throws {
        let rows = try await BackendRuntime.shared.client.records("MESSAGE", parentId: id, as: MessageValue.self)
        messages = rows.sorted { $0.data.ordinal < $1.data.ordinal }.map { WorkChatMessage(id: $0.id, text: $0.data.content, fromUser: $0.data.role == "user") }
    }

    private nonisolated struct MessageValue: Codable, Sendable { let role: String; let content: String; let ordinal: Int64 }
    private nonisolated struct GenerationValue: Codable, Sendable { let status: String; let error: String? }

    func rename(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        guard let backendID else { self.title = title; return }
        Task {
            do {
                let client = BackendRuntime.shared.client
                let row = try await client.get("v2/records/CONVERSATION/\(backendID.uuidString)", as: BackendEntity<BackendJSON>.self)
                _ = try await client.command("conversation.update", payload: ["id": backendID.uuidString, "title": title], expectedVersion: row.version)
                self.title = title
            } catch { self.error = error.localizedDescription }
        }
    }
}

@Observable
final class WorkChatState {
    private(set) var projects: [WorkChatProject]
    private(set) var sessions: [WorkChatSession]
    private(set) var selectedProjectID: String?
    private(set) var expandedProjectID: String?
    var draft = ""

    init(projects: [WorkChatProject] = [], sessions: [WorkChatSession] = []) {
        self.projects = projects
        self.sessions = sessions
        expandedProjectID = projects.first?.id
    }

    func load() async throws {
        nonisolated struct ConversationValue: Codable, Sendable { let title: String; let mode: String; let archived: Bool }
        let client = BackendRuntime.shared.client
        let conversations = try await client.records("CONVERSATION", as: ConversationValue.self)
        sessions = conversations.filter { $0.data.mode == "WORK" && !$0.data.archived }.map { row in
            let session = WorkChatSession(id: row.id.uuidString, title: row.data.title, projectID: row.projectId?.uuidString)
            session.backendID = row.id
            return session
        }
        for session in sessions { try await session.loadHistory() }
        updateProjects(try await client.records("PROJECT", as: BackendJSON.self))
    }

    func updateProjects(_ rows: [WorkspaceRow]) {
        projects = rows.filter { !$0.data.flag("archived") }.map {
            WorkChatProject(id: $0.id.uuidString, name: $0.data.text("name"))
        }
        if let selectedProjectID, !projects.contains(where: { $0.id == selectedProjectID }) {
            self.selectedProjectID = nil
        }
    }

    func registerProject(id: String, name: String) {
        guard !projects.contains(where: { $0.id == id }) else { return }
        projects.append(WorkChatProject(id: id, name: name))
    }

    func clear() { sessions.forEach { $0.stopObserving() }; sessions = []; projects = []; selectedProjectID = nil; expandedProjectID = nil; draft = "" }

    var selectedProject: WorkChatProject? { projects.first { $0.id == selectedProjectID } }

    func selectProject(_ id: String?) {
        guard id == nil || projects.contains(where: { $0.id == id }) else { return }
        selectedProjectID = id
    }

    func toggleProject(_ id: String) {
        guard projects.contains(where: { $0.id == id }) else { return }
        expandedProjectID = expandedProjectID == id ? nil : id
        selectedProjectID = id
    }

    func session(_ id: String) -> WorkChatSession? { sessions.first { $0.id == id } }

    func create(_ text: String) -> WorkChatSession {
        let session = WorkChatSession(title: String(text.prefix(80)), projectID: selectedProjectID)
        session.send(text)
        sessions.insert(session, at: 0)
        draft = ""
        return session
    }

    func create(assistant: AssistantProfile) -> WorkChatSession {
        let session = WorkChatSession(title: assistant.name, projectID: selectedProjectID, assistant: assistant)
        sessions.insert(session, at: 0)
        return session
    }

    func add(_ session: WorkChatSession) { sessions.insert(session, at: 0) }
}

extension AppState {
    func openAssistantChat(_ assistant: AssistantProfile) {
        openWorkChat(workChat.create(assistant: assistant).id)
    }
    var currentWorkChat: WorkChatSession? {
        guard product == .work, case let .chat(id) = workRoute else { return nil }
        return workChat.session(id)
    }

    var workChatDraft: String {
        get { currentWorkChat?.draft ?? workChat.draft }
        set {
            if let chat = currentWorkChat { chat.draft = newValue }
            else { workChat.draft = newValue }
        }
    }

    func openWorkChat(_ id: String? = nil) {
        if let id, workChat.session(id) == nil { return }
        if let id { shell.markRead("chat:" + id) }
        if let id { workChat.selectProject(workChat.session(id)?.projectID) }
        switchProduct(.work)
        workRoute = id.map { .chat(id: $0) } ?? .home
        if id != nil { shell.lastWorkChat = workRoute }
    }

    func openWorkChatProject(_ id: String) {
        guard workChat.projects.contains(where: { $0.id == id }) else { return }
        workChat.toggleProject(id)
        openWorkChat()
    }

    func openQuickChat() {
        workChat.selectProject(nil)
        openWorkChat()
    }

    func sendWorkChatMessage() {
        let text = workChatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let chat = currentWorkChat { chat.send(text) }
        else { openWorkChat(workChat.create(text).id) }
        pokeBlot(.sent)
    }
}
