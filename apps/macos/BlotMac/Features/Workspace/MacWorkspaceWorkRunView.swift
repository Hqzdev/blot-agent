import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceWorkRunView: View {
    let run: WorkspaceWorkRun
    let compact: Bool
    var onInspect: () -> Void = {}
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var expanded = false
    @State private var hoveringResult = false
    private var isGroup: Bool { store.currentConversation?.kind == .group }
    private var ru: Bool { store.language == "ru" }
    private var progress: [BlotV3.Message] { run.progress.filter { store.chatContent.hasVisibleContent($0) } }
    private var waitingForAnswer: Bool {
        guard run.steps.contains(where: { $0.state == .waiting_tools }) else { return false }
        return run.progress.contains { message in
            store.chatContent.activities(for: message).contains { $0.state == .waitingForAnswer }
        }
    }
    private var agent: BlotV3.AgentProfile? {
        store.chatContent.agents.first { $0.metadata.id == (run.messages.first?.authorAgentId ?? store.currentConversation?.agentId) }
    }
    var body: some View {
        let waiting = waitingForAnswer
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                disclosure(waitingForAnswer: waiting)
                if expanded && !progress.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        if run.isRunning && !waiting {
                            MacChatWorkStatus(title: ru ? "Работаю" : "Working", start: startedAt, russian: ru)
                                .padding(.leading, isGroup ? 32 : 0)
                        }
                        progressRows(waitingForAnswer: waiting)
                    }
                    .padding(.leading, 3)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(.secondary.opacity(0.25))
                            .frame(width: 1)
                            .padding(.leading, isGroup ? 32 : 0)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            if let final = run.final { result(final) }
        }
        .onChange(of: run.isRunning) { _, _ in expanded = false }
        .onChange(of: store.messageNavigationTarget) { _, target in
            if let target, run.progress.contains(where: { $0.metadata.id == target }) { expanded = true }
        }
    }

    private func progressRows(waitingForAnswer: Bool) -> some View {
        ForEach(progress, id: \.metadata.id) { message in
            MacLiveTeamMessage(message: message, arriving: run.isRunning, inputFrame: nil, compact: compact,
                showsAuthor: false, showsAvatar: false,
                showsResults: false, showsActions: false, showsGenerating: !waitingForAnswer)
                .id(message.metadata.id)
        }
    }

    private func disclosure(waitingForAnswer: Bool) -> some View {
        HStack(spacing: 8) {
            if isGroup {
                if let agent { WorkspaceAvatarView(agent: agent, size: 24) }
                else { Color.clear.frame(width: 24, height: 24).accessibilityHidden(true) }
            }
            if progress.isEmpty { status(waitingForAnswer: waitingForAnswer) }
            else {
                Button {
                    let opens = !expanded
                    if opens && !run.isRunning { onInspect() }
                    withKAnimation(reduceMotion || systemReduceMotion || progress.count > 8, KMotion.standard) {
                        expanded = opens
                    }
                } label: {
                    HStack(spacing: 7) {
                        status(waitingForAnswer: waitingForAnswer)
                        BlotIcon(expanded ? .chevronDown : .chevronRight, size: BlotIconSize.inline)
                            .accessibilityHidden(true)
                    }.frame(minHeight: 28).contentShape(Rectangle())
                }.buttonStyle(BlotSecondaryTextButtonStyle())
                    .accessibilityValue(expanded ? (ru ? "Развёрнуто" : "Expanded") : (ru ? "Свёрнуто" : "Collapsed"))
            }
        }.accessibilityIdentifier("workspace.chat.work-run.\(run.id)")
    }

    @ViewBuilder private func status(waitingForAnswer: Bool) -> some View {
        if waitingForAnswer {
            Text(ru ? "Ожидаю вашего ответа" : "Waiting for your answer").font(.callout).foregroundStyle(.secondary)
        } else if run.isRunning {
            MacChatActivityLabel(title: ru ? "Думаю" : "Thinking").font(.callout)
        }
        else { MacChatWorkStatus(title: completionTitle, start: startedAt, end: endedAt, russian: ru) }
    }

    private var startedAt: Date {
        run.steps.map(\.metadata.createdAt).min() ?? run.messages[0].metadata.createdAt
    }

    private var endedAt: Date {
        run.final?.metadata.updatedAt ?? run.steps.map(\.metadata.updatedAt).max() ?? run.messages[0].metadata.updatedAt
    }

    private var completionTitle: String {
        if run.failed { return ru ? "Работа остановлена" : "Work stopped" }
        if run.final == nil { return ru ? "Действия" : "Actions" }
        return ru ? "Готово" : "Done"
    }

    private func result(_ final: BlotV3.Message) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MacLiveTeamMessage(message: final, arriving: false, inputFrame: nil, compact: compact,
                showsAuthor: false, showsAvatar: false, showsActivity: false, showsActions: false,
                resultArtifactIDs: run.artifactIDs)
            ForEach(run.changeArtifactIDs, id: \.self) { id in
                WorkspaceFileChangeCard(id: id).padding(.leading, isGroup ? 32 : 0).padding(.trailing, 44)
            }
            if final.delivery == .completed && !final.content.isEmpty {
                MacWorkspaceReplyActions(message: final, isHovered: hoveringResult).padding(.leading, isGroup ? 32 : 0)
            }
        }
        .contentShape(Rectangle())
        .onHover { hoveringResult = $0 }
    }
}
