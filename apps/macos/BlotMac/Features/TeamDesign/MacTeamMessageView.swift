import BlotDesign
import SwiftUI

struct MacTeamMessageView: View {
    let message: MacDemoMessage
    let arriving: Bool
    let inputFrame: CGRect?
    let compact: Bool
    @Environment(MacTeamPresentation.self) private var presentation

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !message.isUser, let author = message.authorID, presentation.group != nil {
                let agent = presentation.agent(for: author)
                HStack(spacing: 8) {
                    MacTeamAvatar(agent: agent, size: 24)
                    Text(agent.name).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WorkspaceAvatarView.color(agent.color))
                }
            }
            HStack {
                if message.isUser { Spacer(minLength: 45) }
                VStack(alignment: message.isUser ? .trailing : .leading, spacing: 6) {
                    bubble
                        .modifier(MacTeamPressMenu(secondaryClick: true) { close in MacTeamMessageMenu(message: message, close: close) })
                        .modifier(MacTeamSwipeToReply { presentation.reply(to: message) })
                        .modifier(MacTeamMessageEntrance(
                            animated: arriving && message.isUser, outgoing: true, inputFrame: inputFrame))
                    if message.reactions?.isEmpty == false { MacTeamMessageReactions(message: message) }
                }
                if !message.isUser { Spacer(minLength: 20) }
            }
            ForEach(message.attachments, id: \.self) { name in
                HStack(spacing: 6) {
                    MacTeamFileIcon(filename: name, size: 20)
                    Text(name).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if !message.isUser { MacTeamMessageCard(message: message) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message.isUser ? "Ваше сообщение" : "Сообщение от " + presentation.authorName(of: message))
        .modifier(MacTeamMessageEntrance(animated: arriving && !message.isUser, outgoing: false))
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let original = presentation.messages.first(where: { $0.id == message.replyToID }) {
                Button { presentation.messageScrollTarget = original.id } label: {
                    MacTeamReplyQuote(message: original)
                }.buttonStyle(BlotPlainButtonStyle()).help("Перейти к сообщению")
            }
            MacTeamMentionText(source: message.text).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
        }
        .padding(.horizontal, 16).padding(.vertical, compact ? 9 : 12)
        .background(message.isUser ? WorkspaceStyle.surface : WorkspaceStyle.surface.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct MacTeamReplyQuote: View {
    let message: MacDemoMessage
    @Environment(MacTeamPresentation.self) private var presentation

    private var color: Color {
        message.isUser ? WorkspaceStyle.ink : WorkspaceAvatarView.color(presentation.agent(for: message.authorID ?? "").color)
    }

    var body: some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Ответ · " + presentation.authorName(of: message))
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(color)
                Text(presentation.messageText(message)).font(.system(size: 11))
                    .foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
}
