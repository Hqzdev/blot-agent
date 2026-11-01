import BlotDesign
import Foundation
import Observation
import BlotAPI

/// Owns loading and recoverable commands independently of tab presentation.
@MainActor
@Observable
final class PhoneWorkspaceModel {
    private let client: BackendClient
    private(set) var conversations: [BackendEntity<BackendJSON>] = []
    private(set) var runs: [BackendEntity<BackendJSON>] = []
    private(set) var projects: [BackendEntity<BackendJSON>] = []
    private(set) var loading = true
    private(set) var busy = false
    private(set) var loadError: String?
    private(set) var chatError: String?
    private(set) var runError: String?
    var title = ""
    var goal = ""
    var selectedProject: UUID?
    private var pendingChat: UUID?
    private var pendingTitle: String?
    private var pendingRun: UUID?
    private var pendingGoal: String?
    private var pendingProject: UUID?

    init(client: BackendClient) { self.client = client }

    var chats: [BackendEntity<BackendJSON>] { conversations.filter { $0.data.text("mode") == "WORK" } }
    var chatPending: Bool { pendingChat != nil }
    var runPending: Bool { pendingRun != nil }
    var canCreateChat: Bool { !busy && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canCreateRun: Bool { !busy && selectedProject != nil && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func refresh() async {
        defer { loading = false }
        do {
            let conversations = try await client.records("CONVERSATION", as: BackendJSON.self)
            let runs = try await client.records("RUN", as: BackendJSON.self)
            let projects = try await client.records("PROJECT", as: BackendJSON.self)
            try Task.checkCancellation()
            self.conversations = conversations
            self.runs = runs
            self.projects = projects
            if !projects.contains(where: { $0.id == selectedProject }) { selectedProject = projects.first?.id }
            loadError = nil
        } catch is CancellationError { }
        catch { loadError = error.localizedDescription }
    }

    func createChat() async {
        guard canCreateChat else { return }
        busy = true
        defer { busy = false }
        let id = pendingChat ?? UUID()
        pendingChat = id
        let content = pendingTitle ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingTitle = content
        do {
            _ = try await client.command("conversation.create", payload: ["title": content], commandId: id)
            pendingChat = nil; pendingTitle = nil; title = ""; chatError = nil
            await refresh()
        } catch let failure as BackendFailure {
            if failure.isDefiniteRejection { pendingChat = nil; pendingTitle = nil }
            chatError = failure.localizedDescription
        } catch { chatError = error.localizedDescription }
    }

    func createRun() async {
        guard canCreateRun, let selectedProject else { return }
        busy = true
        defer { busy = false }
        let id = pendingRun ?? UUID()
        if pendingRun == nil {
            pendingGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
            pendingProject = selectedProject
        }
        pendingRun = id
        do {
            _ = try await client.command("run.create", payload: ["goal": pendingGoal ?? goal], projectId: pendingProject, commandId: id)
            pendingRun = nil; pendingGoal = nil; pendingProject = nil; goal = ""; runError = nil
            await refresh()
        } catch let failure as BackendFailure {
            if failure.isDefiniteRejection { pendingRun = nil; pendingGoal = nil; pendingProject = nil }
            runError = failure.localizedDescription
        } catch { runError = error.localizedDescription }
    }
}
