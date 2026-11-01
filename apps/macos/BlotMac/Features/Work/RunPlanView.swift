import BlotAPI
import BlotDesign
import SwiftUI

/// Requirements and the proposed plan. The run starts only after the user approves this plan.
struct RunPlanView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    var body: some View {
        if let plan = app.workspace.find("PLAN", run.data.uuid("planId")) {
            let requirements = plan.data.items("requirements")
            let steps = plan.data.items("steps")
            if run.data.text("status") == "AWAITING_PLAN" {
                DecisionCard(icon: "list", tint: K.text2, title: "Review the plan before work starts") {
                    Text("Specialists start once you approve. To change scope, refine the goal below — Blot drafts a new version.")
                        .font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        WorkspaceActionButton(title: "Approve plan and start", command: "run.plan.approve", row: run,
                                              icon: "play", kind: .primary, success: "Plan approved — work has started")
                    }
                }
            }
            SettingsGroup(title: "Requirements", detail: "Version \(run.data.integer("requirementsVersion"))") {
                if requirements.isEmpty {
                    SettingsRow(title: "No requirements recorded")
                }
                ForEach(Array(requirements.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 { SettingsDivider() }
                    HStack(alignment: .firstTextBaseline, spacing: KSpace.md) {
                        Badge(text: entry.element.text("key"))
                        Text(entry.element.text("content")).font(KFont.ui(13)).foregroundStyle(K.text).lineSpacing(3)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, KSpace.lg).padding(.vertical, 12)
                }
            }
            SettingsGroup(title: "Proposed plan", detail: steps.isEmpty ? nil : "\(steps.count) steps") {
                ForEach(Array(steps.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 { SettingsDivider() }
                    PlanStepRow(step: entry.element)
                }
                SettingsDivider()
                GroupContent {
                    KDisclosure("Requirement coverage") {
                        CodeBlock(title: "coverage", icon: "list", text: plan.data.value("coverage").formatted)
                    }
                }
            }
        } else {
            SettingsGroup(title: "Plan") {
                if ["PLANNING", "RUNNING"].contains(run.data.text("status")) {
                    LoadingState(label: "Blot is drafting the plan…")
                } else {
                    EmptyState(icon: "list", title: "No plan yet", detail: "The plan appears here once Blot has drafted it.")
                }
            }
        }
    }
}

/// One step of the proposed plan: key, title, role, paths, acceptance criteria and dependencies.
private struct PlanStepRow: View {
    let step: BackendJSON

    var body: some View {
        HStack(alignment: .top, spacing: KSpace.md) {
            Badge(text: step.text("key"))
            VStack(alignment: .leading, spacing: 6) {
                Text(step.text("title")).font(KFont.label()).foregroundStyle(K.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    FaceAvatar(role: .backendRole(step.text("role")), size: 16)
                    Text(AgentRole.displayName(step.text("role"))).font(KFont.caption()).foregroundStyle(K.text2)
                }
                let paths = step.strings("paths")
                if !paths.isEmpty {
                    Text(paths.joined(separator: "  ")).font(KFont.mono(11)).foregroundStyle(K.text3)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(step.strings("criteria"), id: \.self) { criterion in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        KIcon("circle", size: 10, color: K.text3).accessibilityHidden(true)
                        Text(criterion).font(KFont.ui(13)).foregroundStyle(K.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                let dependencies = step.strings("dependencies")
                if !dependencies.isEmpty {
                    Text("Depends on " + dependencies.joined(separator: ", "))
                        .font(KFont.caption()).foregroundStyle(K.text3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, KSpace.lg).padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Tasks created from the approved plan, with status and retry for failed tasks.
struct RunTasksView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    @Binding var evidence: WorkspaceEvidence?
    var body: some View {
        let tasks = app.workspace.rows("TASK", parentID: run.id)
        SettingsGroup(title: "Tasks and dependencies", detail: tasks.isEmpty ? nil : progress(tasks)) {
            if tasks.isEmpty {
                EmptyState(icon: "list", title: "No tasks yet", detail: "Tasks are created when you approve the plan.")
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { SettingsDivider() }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: KSpace.sm) {
                        Button { evidence = WorkspaceEvidence(kind: "TASK", id: task.id) } label: {
                            Text(task.data.text("title")).font(KFont.label()).foregroundStyle(K.text)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                        .help("Show the task record")
                        StatusBadge(status: task.data.text("status"))
                        if ["FAILED", "INTERRUPTED"].contains(task.data.text("status")) {
                            WorkspaceActionButton(title: "Retry", command: "task.retry", row: task, icon: "rotate-ccw",
                                                  success: "Task restarted")
                        }
                    }
                    Text(AgentRole.displayName(task.data.text("role"))
                         + " · requirements v\(task.data.integer("requirementsVersion"))")
                        .font(KFont.caption()).foregroundStyle(K.text2)
                    ForEach(task.data.strings("criteria"), id: \.self) { criterion in
                        Text("• " + criterion).font(KFont.ui(13)).foregroundStyle(K.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(task.data.strings("dependencies"), id: \.self) { id in
                        if let dependency = app.workspace.find("TASK", id) {
                            HStack(spacing: 6) {
                                Text("Depends on " + dependency.data.text("title"))
                                    .font(KFont.caption()).foregroundStyle(K.text3)
                                StatusBadge(status: dependency.data.text("status"))
                            }
                        }
                    }
                }
                .padding(.horizontal, KSpace.lg).padding(.vertical, 14)
            }
        }
    }

    private func progress(_ tasks: [WorkspaceRow]) -> String {
        let done = tasks.filter { BackendStatus($0.data.text("status")).tone == .success }.count
        return "\(done) of \(tasks.count) done"
    }
}
