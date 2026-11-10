import Foundation
import Observation

/// Owns the first blot's draft until both its profile and first chat are saved.
@MainActor @Observable
final class PhoneFirstAgentSetup {
    enum Step: Int, CaseIterable {
        case introduction, name, appearance, role, preparing
    }

    enum Role: String, CaseIterable, Identifiable {
        case assistant, chiefOfStaff, mealPlanner, research, design, inbox, custom
        var id: Self { self }

        var title: String {
            switch self {
            case .assistant: "General assistant"
            case .chiefOfStaff: "Chief of Staff"
            case .mealPlanner: "Meal planner"
            case .research: "UX Research"
            case .design: "Design"
            case .inbox: "Inbox Triage"
            case .custom: "Your own role"
            }
        }

        var summary: String {
            self == .assistant ? "Everyday tasks, ideas, and planning." : instructions
        }

        var instructions: String {
            switch self {
            case .assistant: "Help with everyday tasks, ideas, and planning. Ask for missing details and confirm significant actions."
            case .chiefOfStaff: "Reads tomorrow’s calendar, preps a morning digest"
            case .mealPlanner: "Plans the week’s meals and builds your shopping list"
            case .research: "Challenges assumptions and finds evidence."
            case .design: "Proposes UI and checks the details."
            case .inbox: "Organizes email and prepares replies."
            case .custom: ""
            }
        }
    }

    var draft = WorkspaceAgentForm(shape: "cloud", color: "orange")
    private(set) var step: Step = .introduction
    private(set) var selectedRole: Role?
    private(set) var isSaving = false
    private var createdAgentID: UUID?

    var canContinue: Bool {
        switch step {
        case .introduction, .appearance: true
        case .name: !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .role: selectedRole != nil && !draft.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .preparing: false
        }
    }

    func advance() {
        guard canContinue, let next = Step(rawValue: step.rawValue + 1) else { return }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        step = next
    }

    func back() {
        guard !isSaving, let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    func select(_ role: Role, instructions: String) {
        guard selectedRole != role else { return }
        selectedRole = role
        draft.instructions = instructions
    }

    func skipRole(instructions: String) {
        guard step == .role else { return }
        selectedRole = .assistant
        draft.instructions = instructions
        advance()
    }

    func finish(using store: WorkspaceStore) async {
        guard !isSaving, step == .preparing else { return }
        isSaving = true
        defer { isSaving = false }
        store.form.agent = draft
        if let createdAgentID {
            store.selectedAgentID = createdAgentID
            await store.perform(.saveAgent)
        } else {
            await store.perform(.createAgent)
            guard store.error == nil else { return }
            createdAgentID = store.selectedAgentID
        }
        guard store.error == nil, let createdAgentID else { return }
        store.selectedAgentID = createdAgentID
        await store.perform(.createConversation)
        guard store.error == nil, let chatID = store.selectedConversationID else { return }
        store.preferredAgentID = createdAgentID
        store.selectTab(.chats)
        store.openConversation(chatID)
    }
}
