import BlotAPI
import BlotDesign
import SwiftUI

/// Open questions from agents and prepared actions waiting for permission, shown above every tab.
struct RunDecisionsView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    private var sessionIDs: Set<UUID> { Set(app.workspace.rows("AGENT_SESSION", parentID: run.id).map(\.id)) }
    var body: some View {
        ForEach(
            app.workspace.rows("CHECKPOINT", projectID: run.projectId).filter {
                $0.data.flag("open")
                    && ($0.parentId == run.id || $0.parentId.map(sessionIDs.contains) == true)
            }, id: \.id
        ) { question in RunQuestionView(question: question).transition(.kAppear) }
        ForEach(
            app.workspace.rows("PREPARED_ACTION", projectID: run.projectId).filter {
                $0.data.uuid("sessionId").map(sessionIDs.contains) == true
                    && ["PREPARED", "EXECUTING"].contains($0.data.text("status"))
            }, id: \.id
        ) { action in PreparedActionView(action: action).transition(.kAppear) }
    }
}

/// «Approval Card» chrome: warning glyph, 13 pt title, strong border.
struct DecisionCard<Content: View>: View {
    var icon = "exclamationmark.shield"
    var tint: Color = K.warning
    let title: String
    var accessory: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: KSpace.md) {
            HStack(spacing: KSpace.sm) {
                KIcon(icon, size: 16, color: tint).accessibilityHidden(true)
                Text(title).font(KFont.label()).foregroundStyle(K.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                if let accessory { Badge(text: accessory) }
            }
            content()
        }
        .padding(14)
        .kCard(stroke: K.borderStrong)
        .accessibilityElement(children: .contain)
    }
}

private struct RunQuestionView: View {
    @Environment(AppState.self) private var app
    let question: WorkspaceRow
    @State private var answer = ""
    @State private var sending: String?
    @State private var error: String?
    private var busy: Bool { sending != nil || !app.workspace.commands.active.isEmpty }

    var body: some View {
        DecisionCard(icon: "message-square", tint: K.text2, title: "Blot needs your answer") {
            Text(question.data.text("question")).font(KFont.body()).foregroundStyle(K.text).lineSpacing(4)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            let options = question.data.strings("options")
            if !options.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: KSpace.sm) { optionButtons(options) }
                    VStack(alignment: .leading, spacing: KSpace.sm) { optionButtons(options) }
                }
            }
            KTextArea(text: $answer, placeholder: options.isEmpty ? "Your answer" : "Or write your own answer",
                      minHeight: 64, maxHeight: 160)
            if let error { InlineFeedback(text: error, tone: .error) }
            HStack {
                Spacer()
                KButton(title: "Send answer", icon: "arrow-up", kind: .primary, loading: sending == answer && !answer.isEmpty) {
                    submit(answer)
                }
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .disabled(busy)
    }

    @ViewBuilder private func optionButtons(_ options: [String]) -> some View {
        ForEach(options, id: \.self) { option in
            KButton(title: option, loading: sending == option) { submit(option) }
        }
    }

    private func submit(_ content: String) {
        sending = content
        error = nil
        Task {
            defer { sending = nil }
            do {
                try await app.workspace.send(
                    "user.answer",
                    payload: .object(["id": .string(question.id.uuidString), "answer": .string(content)]),
                    row: question)
                app.toasts.show("Answer sent")
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// A prepared tool or Git action waiting for a one-time grant. Also used in Settings › Permissions.
struct PreparedActionView: View {
    @Environment(AppState.self) private var app
    let action: WorkspaceRow
    private var grants: [WorkspaceRow] {
        app.workspace.rows("GRANT", parentID: action.id).filter {
            !$0.data.flag("revoked") && $0.data.integer("usesRemaining") > 0
                && $0.data.text("actionHash") == action.data.text("hash")
                && WorkspaceDate.parse($0.data.text("expiresAt")).map { $0 > Date() } == true
        }
    }
    var body: some View {
        let status = action.data.text("status")
        DecisionCard(title: "Allow \(action.data.text("capability"))?",
                     accessory: status == "EXECUTING" ? nil : "one time · 5 min") {
            CodeBlock(title: "Arguments", icon: "terminal", text: action.data.value("arguments").formatted, maxHeight: 180)
            VStack(alignment: .leading, spacing: 6) {
                KeyValueRow(label: "SHA-256", value: action.data.text("hash"), mono: true)
                KeyValueRow(label: "Base commit", value: action.data.text("baseSha"), mono: true)
            }
            if let artifactID = action.data.value("arguments").uuid("artifactId") {
                ArtifactLink(id: artifactID)
            }
            if status == "PREPARED" {
                if grants.isEmpty {
                    HStack(spacing: KSpace.sm) {
                        Spacer()
                        WorkspaceActionButton(title: "Deny", command: "permission.deny", row: action, icon: "xmark",
                                              success: "Action denied")
                        WorkspaceActionButton(
                            title: "Allow once", command: "permission.grant", row: action,
                            payload: .object([
                                "id": .string(action.id.uuidString), "seconds": .integer(300),
                                "uses": .integer(1),
                            ]), icon: "check", kind: .primary, success: "Allowed once for 5 minutes")
                    }
                } else {
                    InlineFeedback(text: "Permission granted for this exact action.", tone: .success)
                    HStack(spacing: KSpace.sm) {
                        Spacer()
                        ForEach(grants, id: \.id) { grant in
                            WorkspaceActionButton(title: "Revoke", command: "permission.revoke", row: grant,
                                                  icon: "rotate-ccw", kind: .ghost, success: "Permission revoked")
                        }
                        if action.data.text("capability").hasPrefix("git.") {
                            WorkspaceActionButton(title: "Run Git operation", command: "git.execute", row: action,
                                                  icon: "play", kind: .primary, success: "Git operation started")
                        }
                    }
                }
            } else {
                HStack(spacing: KSpace.sm) {
                    ProgressView().controlSize(.small)
                    Text("Executing…").font(KFont.ui(13)).foregroundStyle(K.text2)
                }
            }
        }
    }
}

enum WorkspaceDate {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    /// Short, local representation for timestamps stored by the backend.
    static func display(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
