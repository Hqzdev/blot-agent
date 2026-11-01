import BlotAPI
import BlotDesign
import SwiftUI

/// «01 · Home — New task» and the new Motes run: the pet, one question, and a composer whose
/// context bar picks the project and the token budget. Sending asks the backend to draft a plan.
struct RunCreationView: View {
    @Environment(AppState.self) private var app
    let team: Bool
    @State private var budget = "100000"
    @State private var error: String?
    private static let minimumBudget: Int64 = 8192

    private var project: Binding<String> {
        Binding(
            get: { team ? app.newRun.projectID : app.newTask.projectID },
            set: { if team { app.newRun.projectID = $0 } else { app.newTask.projectID = $0 } })
    }
    private var goal: Binding<String> {
        Binding(
            get: { team ? app.newRun.goal : app.newTask.draft },
            set: { if team { app.newRun.goal = $0 } else { app.newTask.draft = $0 } })
    }
    private var key: String { team ? "create-team-run" : "create-code-run" }
    private var projectName: String? { app.projects.first { $0.id == project.wrappedValue }?.name }
    private var budgetValue: Int64? { Int64(budget.filter(\.isNumber)) }
    private var budgetError: String? {
        guard let value = budgetValue else { return "Enter the token budget as a number." }
        return value < Self.minimumBudget ? "The token budget must be at least \(Self.minimumBudget.formatted())." : nil
    }
    private var sending: Bool { app.workspace.commands.active.contains(key) }
    private var awaitingConfirmation: Bool { !sending && app.workspace.commands.pending[key] != nil }

    var body: some View {
        VStack(spacing: 0) {
            if app.projects.isEmpty && !app.workspace.loading {
                Spacer()
                EmptyState(icon: "git-branch", title: "Connect a repository",
                           detail: "Blot works on Git repositories on this Mac. Add one to start \(team ? "a team run" : "a task").",
                           actionTitle: "Add repository…", actionIcon: "plus") {
                    app.openProfileSettings(.git)
                }
                Spacer()
            } else {
                Spacer(minLength: KSpace.xl)
                VStack(spacing: KSpace.lg) {
                    PrimaryBlot(context: team ? .newRun : .home)
                    Text(title)
                        .font(KFont.pageTitle(.regular)).foregroundStyle(K.text)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text("Blot drafts a plan first. Work starts after you approve it, and an independent reviewer checks the result.")
                        .font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                        .multilineTextAlignment(.center).frame(maxWidth: 460)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, K.pageInset)
                Spacer(minLength: KSpace.xl)
                VStack(alignment: .leading, spacing: KSpace.sm) {
                    Composer(text: goal, placeholder: team ? "Describe the goal for the team" : "Describe what to build or fix",
                             canSend: UUID(uuidString: project.wrappedValue) != nil && budgetError == nil && !awaitingConfirmation,
                             sending: sending, showsApproval: true,
                             status: error ?? budgetError ?? (awaitingConfirmation ? "The server has not confirmed the previous request yet. Use Send again above." : nil),
                             statusTone: (error ?? budgetError) != nil ? .error : .warning,
                             onSend: create) {
                        ChoiceMenu(selection: project,
                                   options: app.projects.map { ChoiceOption(id: $0.id, title: $0.name) },
                                   placeholder: "Choose project",
                                   accessibilityTitle: "Project")
                        BudgetChip(value: $budget)
                    }
                    Text("Commands run in a prepared virtual machine. File changes, commits and pushes each need your approval.")
                        .font(KFont.caption()).foregroundStyle(K.text3)
                        .padding(.horizontal, KSpace.md)
                }
                .composerPlacement()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { selectProject() }
        .onChange(of: app.projects.map(\.id)) { _, _ in selectProject() }
        .onChange(of: goal.wrappedValue) { _, _ in error = nil }
    }

    private var title: String {
        let name = projectName ?? "your project"
        return team ? "What should the team build in \(name)?" : "What should we build in \(name)?"
    }

    private func selectProject() {
        if !app.projects.contains(where: { $0.id == project.wrappedValue }) {
            project.wrappedValue = app.projects.first?.id ?? ""
        }
    }

    private func create() {
        guard let projectID = UUID(uuidString: project.wrappedValue), let tokens = budgetValue else { return }
        let content = goal.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        error = nil
        app.pokeBlot(.sent)
        Task {
            do {
                let receipt = try await app.workspace.send(
                    "run.create",
                    payload: .object(["goal": .string(content), "tokenBudget": .integer(tokens)]),
                    projectID: projectID, key: key)
                goal.wrappedValue = ""
                app.toasts.show("Blot is drafting the plan")
                if team {
                    app.openWorkRun(receipt.operationId.uuidString)
                } else {
                    app.openTask(projectID: projectID.uuidString, taskID: receipt.operationId.uuidString)
                }
            } catch {
                self.error = error.localizedDescription
                app.react(.error)
            }
        }
    }
}

/// Context-bar chip with an inline numeric field for the run's token budget.
private struct BudgetChip: View {
    @Binding var value: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            KIcon("gauge", size: 14, color: K.text2)
            TextField("", text: $value, prompt: Text("100000").foregroundColor(K.text3))
                .textFieldStyle(.plain).font(KFont.mono(12)).foregroundStyle(K.text)
                .frame(width: 64).focused($focused)
                .accessibilityLabel("Token budget")
            Text("tokens").font(KFont.ui(13)).foregroundStyle(K.text3)
        }
        .padding(.horizontal, 8).frame(height: 28)
        .overlay(RoundedRectangle(cornerRadius: K.rMd, style: .continuous)
            .strokeBorder(focused ? K.focus : .clear, lineWidth: 2))
        .kHover(radius: K.rMd)
        .help("Maximum tokens this run may spend")
    }
}
