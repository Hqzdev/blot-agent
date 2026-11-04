import BlotDesign
import BlotDomain
import SwiftUI

struct MacConversationBlockView: View {
    let block: MacConversationBlock
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        switch block.kind {
        case .question(let question): MacAgentQuestionView(question: question)
        case .received(let id): activity(conversationID: id, received: true)
        case .sent(let id): activity(conversationID: id, received: false)
        case .recipePreview: MacRecipePreview()
        }
    }

    @ViewBuilder private func activity(conversationID: UUID, received: Bool) -> some View {
        if let conversation = store.snapshot.conversations.first(where: { $0.metadata.id == conversationID }),
           let agent = store.snapshot.agents.first(where: { $0.metadata.id == conversation.agentId }) {
            Button { store.openConversation(conversationID) } label: {
                HStack(spacing: 5) {
                    if received {
                        Text("\(store.snapshot.messages.filter { $0.conversationId == conversationID }.count) " + store.t("messages with"))
                    } else { Text(store.t("Messaged")) }
                    WorkspaceAvatarView(agent: agent, size: 18)
                    Text(agent.name)
                }.font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                    .padding(.vertical, 14).frame(maxWidth: .infinity).contentShape(Rectangle())
            }.buttonStyle(.plain).help(store.t("Open chat") + " · " + agent.name)
        }
    }
}

private struct MacAgentQuestionView: View {
    let question: MacAgentQuestion
    @State private var answer = ""
    @Environment(WorkspaceStore.self) private var store
    private var answered: String? { store.desktopContent.answers[question.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.t(question.title)).font(.system(size: 14, weight: .medium))
            VStack(spacing: 0) {
                ForEach(Array(question.choices.enumerated()), id: \.offset) { index, choice in
                    if index > 0 { Divider() }
                    Button { send(store.t(choice)) } label: {
                        HStack(spacing: 9) {
                            Text(String(UnicodeScalar(65 + index)!)).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(WorkspaceStyle.secondary).frame(width: 20, height: 20)
                                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 6))
                            Text(store.t(choice)).font(.system(size: 13)).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            if answered == store.t(choice) { BlotIcon(.check, size: 13) }
                        }.padding(.horizontal, 10).frame(minHeight: 36).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.busy || answered != nil)
                }
            }.background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 8) {
                TextField(store.t("Type your own answer"), text: $answer).textFieldStyle(.plain).font(.system(size: 13))
                    .onSubmit { send(answer) }.disabled(store.busy || answered != nil)
                if !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { send(answer) } label: { BlotIcon(.arrowUp, size: 13) }
                        .buttonStyle(.plain).disabled(store.busy || answered != nil).accessibilityLabel(store.t("Send message"))
                }
            }.padding(.horizontal, 10).frame(minHeight: 34)
                .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
        }.padding(12).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: BlotRadius.panel))
            .padding(.bottom, 8)
    }

    private func send(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        _Concurrency.Task { await store.sendDesktopAnswer(value, questionID: question.id) }
    }
}
