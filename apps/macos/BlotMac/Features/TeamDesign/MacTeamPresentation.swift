import Foundation
import Observation

@MainActor @Observable
final class MacTeamPresentation {
    let demo: MacDemoSession
    var selection: MacTeamSelection = .agent("chief")
    var sheet: MacTeamSheet?
    var settingsVisible = false
    var settingsSearchFocusRequest = 0
    var inspectorVisible = true
    var sidebarVisible = true
    var inspectorTab = "Обзор"
    private var lastAgentID = "chief"
    var draft = ""
    var replyToID: String?
    var composerFocusRequest = 0
    var messageScrollTarget: String?
    var attachedDocumentIDs: [String] = []
    var selectedSkill = false
    var editingMemoryID: String?
    var editingSkillID: String?
    var selectedEmailID = "anna"
    var selectedDocumentID = "sop"
    var selectedTemplateID = "builder"

    init(demo: MacDemoSession? = nil) { self.demo = demo ?? MacDemoSession() }

    var agents: [MacTeamAgent] { demo.state.agents }
    var routines: [MacTeamRoutine] {
        get { demo.state.routines }
        set { demo.update { $0.routines = newValue } }
    }
    var settings: MacDemoSettings {
        get { demo.state.settings }
        set { demo.update { $0.settings = newValue } }
    }
    var plugins: [MacTeamPlugin] {
        MacTeamSamples.plugins.map { plugin in
            var plugin = plugin
            plugin.accounts = demo.state.connections.filter { $0.pluginID == plugin.id }.map(\.label)
            return plugin
        }
    }
    var group: MacDemoGroup? {
        guard case .group(let id) = selection else { return nil }
        return demo.state.groups.first { $0.id == id }
    }
    var agent: MacTeamAgent {
        if case .agent(let id) = selection { return agent(for: id) }
        if let first = group?.agentIDs.first { return agent(for: first) }
        return agent(for: lastAgentID)
    }
    var conversationKey: String {
        switch selection {
        case .agent(let id): "agent:" + id
        case .group(let id): "group:" + id
        case .library: "agent:" + agent.id
        }
    }
    var messages: [MacDemoMessage] { demo.state.threads[conversationKey] ?? [] }
    var isConversation: Bool {
        if case .library = selection { return false }
        return true
    }
    var title: String {
        switch selection {
        case .agent: agent.name
        case .group: group?.name ?? "Группа"
        case .library(let destination): destination.title
        }
    }
    var relevantMemories: [MacDemoMemory] {
        demo.state.memories.filter {
            $0.agentID == nil || $0.agentID == agent.id || group?.agentIDs.contains($0.agentID ?? "") == true
        }
    }
    var relevantSkills: [MacDemoSkill] {
        demo.state.skills.filter { $0.agentID == agent.id || group?.agentIDs.contains($0.agentID) == true }
    }
    var pendingEmail: MacDemoEmail? { demo.state.emails.first { $0.id == selectedEmailID } }
    var canSendEmail: Bool { demo.canSendEmail(selectedEmailID) }
    func dateLabel(_ date: Date) -> String {
        date.formatted(
            .dateTime.day().month(.abbreviated).hour().minute().locale(
                Locale(identifier: settings.language == "Русский" ? "ru_RU" : "en_US")))
    }
    var document: MacDemoDocument? { demo.state.documents.first { $0.id == selectedDocumentID } }
    var template: MacDemoTemplate {
        MacDemoTemplates.all.first { $0.id == selectedTemplateID } ?? MacDemoTemplates.all[0]
    }
    var usageFraction: Double { min(1, Double(settings.usedActions) / Double(settings.weeklyLimit)) }

    func members(of group: MacDemoGroup) -> [MacTeamAgent] {
        group.agentIDs.compactMap { id in agents.first { $0.id == id } }
    }

    func agent(for id: String) -> MacTeamAgent { agents.first { $0.id == id } ?? agents[0] }
    func showSettings() {
        sheet = nil
        settingsVisible = true
    }
    func closeSettings() { settingsVisible = false }

    func open(_ selection: MacTeamSelection) {
        self.selection = selection
        if case .agent(let id) = selection { lastAgentID = id }
        draft = ""
        replyToID = nil
        messageScrollTarget = nil
        attachedDocumentIDs = []
        if case .group(let id) = selection { demo.prepareCollaboration(in: id) }
        if case .agent(let id) = selection, agents.first(where: { $0.id == id })?.unread == true {
            demo.update { state in
                if let index = state.agents.firstIndex(where: { $0.id == id }) { state.agents[index].unread = false }
            }
        }
    }
    func saveAgent(_ agent: MacTeamAgent, openConversation: Bool = true) {
        demo.saveAgent(agent)
        if openConversation { open(.agent(agent.id)) }
        sheet = nil
    }
    func sendDraft() {
        demo.send(
            draft, conversation: conversationKey, agentID: agent.id,
            groupIDs: group?.agentIDs ?? [],
            attachments: attachedDocumentIDs.compactMap { id in demo.state.documents.first { $0.id == id }?.title },
            replyToID: replyToID)
        draft = ""
        replyToID = nil
        attachedDocumentIDs = []
        selectedSkill = false
    }
    func send(_ text: String) {
        draft = text
        sendDraft()
    }
    func showEmail(_ id: String) {
        selectedEmailID = id
        sheet = .email
    }
    func showDocument(_ id: String) {
        selectedDocumentID = id
        sheet = .document
    }
    func editMemory(_ id: String? = nil) {
        editingMemoryID = id
        sheet = .memory
    }
    func editSkill(_ id: String? = nil) {
        editingSkillID = id
        sheet = .skill
    }
    func importTemplate() {
        let id = demo.importTemplate(template)
        sheet = nil
        open(.agent(id))
    }
    func runRoutine(_ id: String) {
        guard let routine = routines.first(where: { $0.id == id }) else { return }
        demo.runRoutine(id)
        sheet = nil
        open(.agent(routine.agentID))
    }
}
