import BlotAPI
import BlotDesign
import SwiftUI

/// «16 · Motes — Team chat»: who is working, the run's messages by channel, and messages between agents.
struct RunMessagesView: View {
    @Environment(AppState.self) private var app
    let run: WorkspaceRow
    @Binding var evidence: WorkspaceEvidence?
    @State private var channel = ""
    private var sessions: [WorkspaceRow] { app.workspace.rows("AGENT_SESSION", parentID: run.id) }
    private var conversations: [WorkspaceRow] {
        app.workspace.rows("CONVERSATION", projectID: run.projectId).filter {
            $0.data.uuid("runId") == run.id
        }
    }
    private var messages: [WorkspaceRow] {
        let ids = Set(conversations.map(\.id))
        return app.workspace.rows("MESSAGE", projectID: run.projectId).filter {
            $0.parentId.map(ids.contains) == true && (channel.isEmpty || $0.parentId?.uuidString == channel)
        }.sorted {
            if $0.parentId == $1.parentId { return $0.data.integer("ordinal") < $1.data.integer("ordinal") }
            return ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
    }
    private var inbox: [WorkspaceRow] {
        let ids = Set(sessions.map(\.id))
        return app.workspace.rows("INBOX", projectID: run.projectId).filter {
            $0.data.uuid("recipientSessionId").map(ids.contains) == true
        }
    }

    var body: some View {
        SettingsGroup(title: "Team", detail: sessions.isEmpty ? nil : "\(sessions.count) specialists on this run") {
            if sessions.isEmpty {
                EmptyState(icon: "users", title: "No specialists yet",
                           detail: "Assignments appear after you approve the plan.")
            }
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                if index > 0 { SettingsDivider() }
                sessionRow(session)
            }
        }

        VStack(alignment: .leading, spacing: KSpace.lg) {
            HStack {
                Text("Messages").font(KFont.body(.medium)).foregroundStyle(K.text).accessibilityAddTraits(.isHeader)
                Spacer()
                ChoiceMenu(selection: $channel,
                           options: [ChoiceOption(id: "", title: "All channels")] + conversations.map {
                               ChoiceOption(id: $0.id.uuidString,
                                            title: $0.data.text("title") + " · " + String($0.id.uuidString.prefix(8)))
                           },
                            accessibilityTitle: "Channel")
            }
            if messages.isEmpty {
                EmptyState(icon: "messages-square", title: "No messages yet",
                           detail: channel.isEmpty ? "Planning and agent messages appear here as the run progresses."
                                                   : "This channel has no messages yet.")
                    .kCard()
            }
            ForEach(messages, id: \.id) { message in
                MessageBlock(message: message, author: author(message)).transition(.kAppear)
            }
        }
        .kAnimation(value: messages.count)

        if !inbox.isEmpty {
            SettingsGroup(title: "Between agents", detail: "Questions and handoffs the specialists sent each other.") {
                ForEach(Array(inbox.enumerated()), id: \.element.id) { index, message in
                    if index > 0 { SettingsDivider() }
                    GroupContent(spacing: 6) {
                        HStack(spacing: KSpace.sm) {
                            Text(role(message.data.uuid("senderSessionId"))).font(KFont.label())
                            KIcon("arrow-right", size: 12, color: K.text3).accessibilityLabel("to")
                            Text(role(message.data.uuid("recipientSessionId"))).font(KFont.label())
                            Spacer()
                            StatusBadge(message.data.flag("processed") ? "Processed" : "Waiting",
                                        tone: message.data.flag("processed") ? .success : .attention)
                        }
                        .foregroundStyle(K.text)
                        Text(message.data.text("content")).font(KFont.ui(13)).foregroundStyle(K.text2).lineSpacing(3)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        TextLink(title: "View source record", color: K.text3, size: 12) {
                            evidence = WorkspaceEvidence(kind: "INBOX", id: message.id)
                        }
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: WorkspaceRow) -> some View {
        let role = AgentRole.backendRole(session.data.text("role"))
        let waiting = session.data.text("waitingReason")
        let depth = session.data.integer("depth")
        return ListRow(title: AgentRole.displayName(session.data.text("role")),
                       subtitle: [waiting.isEmpty ? nil : waiting,
                                  depth > 0 ? "Mote of " + String(session.data.text("parentSessionId").prefix(8)) : nil,
                                  "Session " + String(session.id.uuidString.prefix(8))]
                           .compactMap { $0 }.joined(separator: " · "),
                       action: { evidence = WorkspaceEvidence(kind: "AGENT_SESSION", id: session.id) }) {
            FaceAvatar(role: role, size: 32)
        } trailing: {
            StatusBadge(status: session.data.text("status"))
            KButton(title: "Channel", icon: "messages-square", kind: .ghost, height: 28) {
                channel = session.data.text("conversationId")
            }
            .help("Show only this specialist's channel")
        }
    }

    private func role(_ id: UUID?) -> String {
        guard let session = app.workspace.find("AGENT_SESSION", id) else { return "You" }
        return AgentRole.displayName(session.data.text("role"))
    }

    private func author(_ message: WorkspaceRow) -> MessageAuthor {
        if let session = sessions.first(where: { $0.data.uuid("conversationId") == message.parentId }) {
            let role = AgentRole.backendRole(session.data.text("role"))
            return MessageAuthor(name: AgentRole.displayName(session.data.text("role")), role: role,
                                 detail: message.data.text("role"))
        }
        return MessageAuthor(name: message.data.text("role") == "user" ? "You" : "Planning", role: .blot,
                             detail: message.data.text("role"))
    }
}

struct MessageAuthor {
    let name: String
    let role: AgentRole
    let detail: String
}

/// One message in a run: avatar and author line, then text, or a collapsible tool call / result.
private struct MessageBlock: View {
    @Environment(AppState.self) private var app
    let message: WorkspaceRow
    let author: MessageAuthor

    private var isUser: Bool { message.data.text("role") == "user" }
    private var isTool: Bool { message.data.text("role") == "tool" || message.data.value("functionCall") != .null }

    var body: some View {
        if isUser && !isTool {
            UserBubble(text: message.data.text("content"))
        } else {
            HStack(alignment: .top, spacing: KSpace.md) {
                FaceAvatar(role: author.role, size: 28)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: KSpace.sm) {
                        Text(author.name).font(KFont.label()).foregroundStyle(K.text)
                        Text(author.detail).font(KFont.mono(11)).foregroundStyle(K.text3)
                        if let generation = app.workspace.find("GENERATION", message.data.uuid("generationId")),
                           generation.data.text("status") != "COMPLETED" {
                            StatusBadge(status: generation.data.text("status"))
                        }
                    }
                    if isTool {
                        KDisclosure(message.data.text("role") == "tool"
                                    ? "Tool result · " + message.data.text("functionName") : "Tool call") {
                            if !message.data.text("content").isEmpty {
                                CodeBlock(title: message.data.text("functionName"), icon: "terminal",
                                          text: message.data.text("content"))
                            }
                            if message.data.value("functionCall") != .null {
                                CodeBlock(title: "Call", icon: "terminal", text: message.data.value("functionCall").formatted)
                            }
                        }
                    } else {
                        AgentText(text: message.data.text("content"))
                    }
                    if let generation = app.workspace.find("GENERATION", message.data.uuid("generationId")),
                       !generation.data.text("error").isEmpty {
                        InlineFeedback(text: generation.data.text("error"), tone: .error)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
