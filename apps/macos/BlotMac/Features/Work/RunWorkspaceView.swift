import BlotAPI
import BlotDesign
import SwiftUI

/// A task (Blot Code) or team run (Motes): header with status and run controls, open decisions,
/// three sections — conversation, plan & tasks, results & Git — and a composer to refine the goal.
struct RunWorkspaceView: View {
    @Environment(AppState.self) private var app
    @Environment(\.blotReduceMotion) private var reduceMotion
    let runID: UUID
    @State private var tab: RunTab = .conversation
    @State private var refinement = ""
    @State private var steering = false
    @State private var steerError: String?
    @State private var evidence: WorkspaceEvidence?
    private var run: WorkspaceRow? { app.workspace.find("RUN", runID) }

    enum RunTab: String, CaseIterable, Identifiable {
        case conversation = "Conversation", plan = "Plan & tasks", results = "Results & Git"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .conversation: "messages-square"
            case .plan: "list"
            case .results: "git-pull-request"
            }
        }
    }

    var body: some View {
        if let run {
            let status = BackendStatus(run.data.text("status"))
            VStack(spacing: 0) {
                ContentColumn {
                    VStack(alignment: .leading, spacing: KSpace.lg) {
                        header(run, status: status)
                        KSegmented(options: RunTab.allCases, selection: $tab, label: \.rawValue, title: "Run section")
                    }
                    .padding(.top, KSpace.xl).padding(.bottom, KSpace.lg)
                }
                .kBorder(.bottom)
                ScrollView {
                    ContentColumn {
                        LazyVStack(alignment: .leading, spacing: KSpace.xl) {
                            RunDecisionsView(run: run)
                            Group {
                                switch tab {
                                case .conversation: RunMessagesView(run: run, evidence: $evidence)
                                case .plan:
                                    RunPlanView(run: run)
                                    RunTasksView(run: run, evidence: $evidence)
                                case .results: RunResultsView(run: run, evidence: $evidence)
                                }
                            }
                            .transition(.kAppear)
                        }
                        .padding(.vertical, KSpace.xl)
                        .id(tab)
                    }
                }
                .kAnimation(value: tab)
                if !status.isTerminal {
                    Composer(text: $refinement,
                             placeholder: "Refine the goal or constraints — Blot drafts a new plan version",
                             canSend: app.workspace.commands.active.isEmpty, sending: steering,
                             showsApproval: true, status: steerError, statusTone: .error) { steer(run) }
                        .composerPlacement()
                        .padding(.top, KSpace.md)
                }
            }
            .onAppear { if app.reviewVisible { tab = .results } }
            .onChange(of: app.reviewVisible) { _, visible in if visible { tab = .results } }
            .onChange(of: refinement) { _, _ in steerError = nil }
            .sheet(item: $evidence) { WorkspaceEvidenceView(evidence: $0) }
        } else if app.workspace.loading {
            ContentSkeleton()
        } else {
            EmptyState(icon: "message-square", title: "Run not found",
                       detail: "It may have been removed on the server. Choose another run in the sidebar.")
                .frame(maxHeight: .infinity)
        }
    }

    private func header(_ run: WorkspaceRow, status: BackendStatus) -> some View {
        VStack(alignment: .leading, spacing: KSpace.md) {
            Text(run.data.text("goal"))
                .font(KFont.ui(20, .semibold)).foregroundStyle(K.text)
                .lineLimit(3).textSelection(.enabled)
                .help(run.data.text("goal"))
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: KSpace.sm) {
                StatusBadge(status.label, tone: status.tone)
                if !run.data.text("waitingReason").isEmpty {
                    Text(run.data.text("waitingReason")).font(KFont.caption()).foregroundStyle(K.text2).lineLimit(2)
                }
                Spacer(minLength: KSpace.md)
                controls(run, status: status.raw)
            }
            .kAnimation(value: status)
        }
    }

    @ViewBuilder private func controls(_ run: WorkspaceRow, status: String) -> some View {
        KButton(title: "Graph", icon: "network", kind: .ghost) {
            app.selectedRunID = run.id.uuidString
            app.openGraph()
        }
        .help("Open the team graph for this run")
        if !BackendStatus(status).isTerminal {
            WorkspaceActionButton(title: "Stop", command: "run.stop", row: run, icon: "stop", kind: .danger,
                                  success: "Run stopped")
        }
        if ["PAUSED", "INTERRUPTED", "WAITING"].contains(status) {
            WorkspaceActionButton(title: "Resume", command: "run.resume", row: run, icon: "play", success: "Run resumed")
        } else if ["RUNNING", "PLANNING"].contains(status) {
            WorkspaceActionButton(title: "Pause", command: "run.pause", row: run, icon: "pause", success: "Run paused")
        }
        if status == "AWAITING_PLAN" {
            KButton(title: "Review plan", icon: "list", kind: .primary) {
                withKAnimation(reduceMotion) { tab = .plan }
            }
        }
        if status == "READY_FOR_ACCEPTANCE" {
            WorkspaceActionButton(title: "Accept result", command: "run.accept", row: run, icon: "check",
                                  kind: .primary, success: "Result accepted")
        }
    }

    private func steer(_ run: WorkspaceRow) {
        steering = true
        steerError = nil
        Task {
            defer { steering = false }
            do {
                _ = try await app.workspace.send(
                    "run.steer",
                    payload: .object([
                        "id": .string(run.id.uuidString),
                        "goal": .string(run.data.text("goal") + "\n\nУточнение пользователя:\n" + refinement),
                    ]), row: run)
                refinement = ""
                app.toasts.show("Sent — Blot is drafting a new plan version")
            } catch { steerError = error.localizedDescription }
        }
    }
}
