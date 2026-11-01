import BlotAPI
import BlotDesign
import SwiftUI

/// Artifacts and reviews, tool operations, budget, Git and model requests for one run.
struct RunResultsView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    @Binding var evidence: WorkspaceEvidence?
    private var sessions: Set<UUID> { Set(app.workspace.rows("AGENT_SESSION", parentID: run.id).map(\.id)) }
    private var tasks: [WorkspaceRow] { app.workspace.rows("TASK", parentID: run.id) }
    private var operations: [WorkspaceRow] {
        app.workspace.rows("TOOL_OPERATION", projectID: run.projectId).filter {
            $0.data.uuid("sessionId").map(sessions.contains) == true
        }
    }

    var body: some View {
        if ["READY_FOR_ACCEPTANCE", "COMPLETED"].contains(run.data.text("status")) { RunGitView(run: run) }

        SettingsGroup(title: "Artifacts and independent review") {
            if tasks.isEmpty {
                EmptyState(icon: "file-text", title: "No artifacts yet",
                           detail: "Each task's result and its review appear here.")
            }
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 { SettingsDivider() }
                GroupContent(spacing: KSpace.sm) {
                    HStack {
                        Text(task.data.text("title")).font(KFont.label()).foregroundStyle(K.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        StatusBadge(status: task.data.text("status"))
                    }
                    if let id = task.data.uuid("artifactId") { ArtifactLink(id: id) }
                    let reviews = app.workspace.rows("REVIEW", parentID: task.id)
                    if reviews.isEmpty && task.data.uuid("artifactId") != nil {
                        Text("Waiting for review").font(KFont.caption()).foregroundStyle(K.text3)
                    }
                    ForEach(reviews, id: \.id) { review in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: KSpace.sm) {
                                KIcon("eye", size: 14, color: K.text3)
                                Text("Review").font(KFont.ui(13)).foregroundStyle(K.text2)
                                StatusBadge(status: review.data.text("decision"))
                                Spacer()
                                TextLink(title: "Record " + String(review.id.uuidString.prefix(8)), color: K.text3, size: 12) {
                                    evidence = WorkspaceEvidence(kind: "REVIEW", id: review.id)
                                }
                            }
                            KeyValueRow(label: "Checked SHA-256", value: review.data.text("artifactHash"), mono: true)
                            ForEach(review.data.strings("findings"), id: \.self) { finding in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    KIcon("flag", size: 12, color: K.warning).accessibilityLabel("Finding")
                                    Text(finding).font(KFont.ui(13)).foregroundStyle(K.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12)
                        .kCard(radius: K.rMd, fill: K.bg)
                    }
                }
            }
        }

        SettingsGroup(title: "Tool operations", detail: operations.isEmpty ? nil : "What the agents actually ran") {
            if operations.isEmpty {
                EmptyState(icon: "terminal", title: "No tool operations", detail: "Commands and file operations appear here.")
            }
            ForEach(Array(operations.enumerated()), id: \.element.id) { index, operation in
                if index > 0 { SettingsDivider() }
                GroupContent(spacing: KSpace.sm) {
                    HStack(spacing: KSpace.sm) {
                        KIcon("terminal", size: 14, color: K.text3)
                        Button { evidence = WorkspaceEvidence(kind: "TOOL_OPERATION", id: operation.id) } label: {
                            Text(operation.data.text("name")).font(KFont.mono(12)).foregroundStyle(K.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(KIconButtonStyle()).kFocusRing(radius: K.rSm)
                        .help("Show the operation record")
                        StatusBadge(status: operation.data.text("status"))
                    }
                    if !operation.data.text("error").isEmpty {
                        InlineFeedback(text: operation.data.text("error"), tone: .error)
                    }
                    KDisclosure("Result") {
                        CodeBlock(title: operation.data.text("name"), icon: "terminal",
                                  text: operation.data.value("result").formatted)
                    }
                    if operation.data.text("status") == "UNKNOWN" {
                        HStack {
                            Text("The outcome was not confirmed. Check what actually happened before continuing.")
                                .font(KFont.caption()).foregroundStyle(K.text2)
                            Spacer()
                            WorkspaceActionButton(
                                title: "Check outcome",
                                command: operation.data.text("name").hasPrefix("git.") ? "git.reconcile" : "tool.reconcile",
                                row: operation, icon: "rotate-ccw", success: "Outcome checked")
                        }
                    }
                }
            }
        }

        ForEach(app.workspace.rows("BUDGET", parentID: run.id), id: \.id) { budget in
            RunBudgetView(budget: budget)
        }

        let queue = app.workspace.rows("MODEL_REQUEST", projectID: run.projectId).filter {
            $0.data.uuid("runId") == run.id
        }
        SettingsGroup(title: "Model requests", detail: queue.isEmpty ? nil : "\(queue.count) requests") {
            if queue.isEmpty {
                SettingsRow(title: "No model requests yet")
            }
            ForEach(Array(queue.reversed().enumerated()), id: \.element.id) { index, request in
                if index > 0 { SettingsDivider() }
                ListRow(title: request.data.text("purpose"), subtitle: request.data.text("model"),
                        action: { evidence = WorkspaceEvidence(kind: "MODEL_REQUEST", id: request.id) }) {
                    IconTile(icon: "sparkle")
                } trailing: {
                    StatusBadge(status: request.data.text("status"))
                }
            }
        }
    }
}

private struct RunBudgetView: View {
    @Environment(AppState.self) private var app
    let budget: WorkspaceRow
    @State private var limit = ""
    private var spent: Int64 { budget.data.integer("spent") }
    private var reserved: Int64 { budget.data.integer("reserved") }
    private var total: Int64 { budget.data.integer("limit") }

    var body: some View {
        SettingsGroup(title: "Run budget") {
            GroupContent {
                HStack(spacing: KSpace.lg) {
                    metric("Spent", spent)
                    metric("Reserved", reserved)
                    metric("Limit", total)
                }
                ProgressView(value: Double(min(spent + reserved, max(total, 1))), total: Double(max(total, 1)))
                    .tint(K.inverse)
                    .accessibilityLabel("Budget used")
                    .accessibilityValue("\((spent + reserved).formatted()) of \(total.formatted()) tokens")
                if total > 0 && (spent + reserved) * 10 >= total * 9 {
                    InlineFeedback(text: "Almost all of the budget is used.", tone: .warning)
                }
                if budget.data.flag("usageUnknown") {
                    InlineFeedback(text: "Part of the usage is unknown and is counted conservatively.", tone: .warning)
                }
            }
            SettingsDivider()
            SettingsRow(title: "Raise the limit", detail: "Enter a new total above \(total.formatted()) tokens.") {
                HStack(spacing: KSpace.sm) {
                    KTextField(text: $limit, placeholder: "New limit", mono: true).frame(width: 140)
                    WorkspaceActionButton(
                        title: "Raise", command: "budget.increase", row: budget,
                        payload: .object([
                            "id": .string(budget.id.uuidString), "limit": .integer(Int64(limit) ?? 0),
                        ]), success: "Budget raised")
                    .disabled((Int64(limit) ?? 0) <= total)
                }
            }
        }
    }

    private func metric(_ title: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.formatted()).font(KFont.ui(15, .medium)).foregroundStyle(K.text).monospacedDigit()
            Text(title).font(KFont.caption()).foregroundStyle(K.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct RunGitView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    @State private var message = ""
    @State private var remote = "origin"
    @State private var refspec = ""
    @State private var preparing: String?
    @State private var error: String?
    private var busy: Bool { !app.workspace.commands.active.isEmpty }

    var body: some View {
        SettingsGroup(title: "Commit and push",
                      detail: "Each operation is prepared first. Review the exact parameters, approve it above, then run it.") {
            GroupContent {
                KTextField("Commit message", text: $message, placeholder: "fix: …", mono: true)
                HStack {
                    Spacer()
                    KButton(title: "Prepare commit", icon: "git-branch", loading: preparing == "git.prepare_commit") {
                        prepare("git.prepare_commit", arguments: ["message": .string(message)])
                    }
                    .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                }
            }
            SettingsDivider()
            GroupContent {
                HStack(alignment: .top, spacing: KSpace.md) {
                    KTextField("Remote", text: $remote, mono: true).frame(width: 140)
                    KTextField("Refspec", text: $refspec, placeholder: "refs/heads/codex/…:refs/heads/codex/…", mono: true)
                }
                if let error { InlineFeedback(text: error, tone: .error) }
                HStack {
                    Text("The server checks branch protection and that the push matches the accepted result.")
                        .font(KFont.caption()).foregroundStyle(K.text3)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    KButton(title: "Prepare push", icon: "arrow-up", loading: preparing == "git.prepare_push") {
                        prepare("git.prepare_push", arguments: ["remote": .string(remote), "refspec": .string(refspec)])
                    }
                    .disabled(remote.isEmpty || refspec.isEmpty || busy)
                }
            }
        }
        .onAppear { suggestRefspec() }
    }

    private func suggestRefspec() {
        guard refspec.isEmpty else { return }
        let marker = app.workspace.rows("CHECKPOINT", parentID: run.id).first {
            $0.data.text("phase") == "integration"
                && $0.data.integer("revision") == run.data.integer("requirementsVersion")
        }
        if let task = app.workspace.find("TASK", marker?.data.uuid("taskId")),
            let author = task.data.uuid("authorSessionId")
        {
            let ref = "refs/heads/codex/blot-" + author.uuidString.lowercased()
            refspec = ref + ":" + ref
        }
    }

    private func prepare(_ type: String, arguments: [String: BackendJSON]) {
        preparing = type
        error = nil
        Task {
            defer { preparing = nil }
            do {
                try await app.workspace.send(
                    type,
                    payload: .object(["runId": .string(run.id.uuidString), "arguments": .object(arguments)]),
                    row: run)
                app.toasts.show(type == "git.prepare_commit" ? "Commit prepared — approve it above" : "Push prepared — approve it above")
            } catch { self.error = error.localizedDescription }
        }
    }
}
