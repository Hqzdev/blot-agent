import BlotDesign
import BlotDomain
import SwiftUI

struct MacLiveTeamConversation: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(MacTeamPreferenceKey.compactMessages) private var compactMessages = false
    @State private var timeline: MacTeamMessageTimeline
    @State private var followsLatest = true
    @State private var nearBottom = true
    @State private var inputGeometry = MacWorkspaceInputGeometry()
    @State private var sendInputFrame: CGRect?
    @State private var history = WorkspaceTranscriptWindow()
    @State private var presentedInitialTail = false

    init(messages: [BlotV3.Message]) {
        _timeline = State(initialValue: MacTeamMessageTimeline(items: messages.suffix(WorkspaceTranscriptWindow.pageSize).map {
            .init(id: $0.metadata.id.uuidString, isUser: $0.role == .user)
        }))
    }

    private struct MessageUpdate: Equatable {
        let ids: [UUID]
        let reduced: Bool
    }
    private struct TailUpdate: Equatable {
        let rows: [UUID]
        let revealed: String?
        let replying: Bool
    }
    private var messages: [BlotV3.Message] { Array(history.messages(in: store.currentVisibleMessages)) }
    private var reduced: Bool { reduceMotion || systemReduceMotion }
    private var groupMembers: [BlotV3.AgentProfile] {
        let ids = Set((store.chatContent.participants).filter {
            $0.conversationId == store.selectedConversationID && $0.kind == .agent && !$0.removed
        }.map(\.participantId))
        return store.chatContent.agents.filter { ids.contains($0.metadata.id) }
    }

    private var isEmptyChat: Bool {
        messages.isEmpty && store.currentReplyDraft == nil
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            if store.currentConversation?.kind == .group { MacLiveTeamGroupAvatar(agents: groupMembers, size: 48) }
            Group {
                if store.currentConversation?.kind == .group { Text(store.t("Set a shared task for the team")) }
                else if store.chatContent.agents.isEmpty { Text(store.t("Create your first agent")) }
                else { WorkspaceWelcomeGreeting() }
            }.font(.system(size: 26, weight: .medium)).multilineTextAlignment(.center)
            if store.chatContent.agents.isEmpty {
                Button(store.t("Create agent")) { store.navigate(.createAgent) }.buttonStyle(WorkspaceButtonStyle())
            }
        }
    }

    var body: some View {
        let visibleMessages = messages.filter { timeline.visibleIDs.contains($0.metadata.id.uuidString) }
        let runs = store.chatContent.workRuns(messages: visibleMessages, responding: store.isReplying)
        let hiddenIDs = Set(runs.values.flatMap { $0.messages.dropFirst().map(\.metadata.id) })
        let transcriptMessages = visibleMessages.filter {
            !hiddenIDs.contains($0.metadata.id) && (runs[$0.metadata.id] != nil || $0.role != .assistant
                || $0.delivery != .running || store.chatContent.hasVisibleContent($0))
        }
        let tail = Array(visibleMessages.suffix(3))
        let tailUpdate = TailUpdate(rows: Array(transcriptMessages.suffix(3).map(\.metadata.id)),
            revealed: timeline.lastRevealedID, replying: store.isReplying)
        let authorIDs = WorkspaceMessageSeries.authorIDs(in: visibleMessages)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compactMessages ? 5 : 8) {
                    if history.hasEarlier(in: store.currentVisibleMessages) {
                        Button(store.language == "ru" ? "Загрузить предыдущие сообщения" : "Load earlier messages") {
                            let anchor = messages.first?.metadata.id
                            followsLatest = false
                            history.loadEarlier()
                            timeline.synchronize(items: messages.map { .init(id: $0.metadata.id.uuidString, isUser: $0.role == .user) }, immediate: true, followingLatest: false)
                            _Concurrency.Task { await _Concurrency.Task.yield(); if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
                        }.font(.callout).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(transcriptMessages.enumerated()), id: \.element.metadata.id) { index, message in
                        VStack(alignment: .leading, spacing: 5) {
                            if MacChatMessageContext.startsDate(message, after: index > 0 ? transcriptMessages[index - 1] : nil) {
                                Text(message.metadata.createdAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.top, 14).padding(.bottom, 10)
                            }
                            if let run = runs[message.metadata.id] {
                                MacWorkspaceWorkRunView(run: run, compact: compactMessages, onInspect: { followsLatest = false })
                            } else if let plan = store.groupPlan(for: message) {
                                WorkspaceGroupPlanCard(plan: plan, agents: store.chatContent.agents, skills: store.chatContent.skills, russian: store.language == "ru")
                            } else {
                                if message.role == .assistant, message.delivery == .completed,
                                   !message.content.isEmpty,
                                   store.chatContent.cards[message.metadata.id]?.contains(where: { $0.kind == "question" }) != true {
                                    MacChatWorkStatus(title: store.language == "ru" ? "Готово" : "Done",
                                        start: message.metadata.createdAt, end: message.metadata.updatedAt,
                                        russian: store.language == "ru")
                                        .accessibilityIdentifier("workspace.chat.reply-completed.\(message.metadata.id)")
                                }
                                MacLiveTeamMessage(message: message, arriving: timeline.entranceIDs.contains(message.metadata.id.uuidString),
                                    inputFrame: sendInputFrame, compact: compactMessages, showsAuthor: store.currentConversation?.kind == .group && authorIDs.contains(message.metadata.id),
                                    showsAvatar: authorIDs.contains(message.metadata.id))
                            }
                        }
                            .id(message.metadata.id).transition(.identity)
                            .onAppear { timeline.didAppear(message.metadata.id.uuidString) }
                    }
                    if let draft = store.currentReplyDraft,
                       !runs.values.contains(where: { $0.isRunning && $0.messages.first?.commandId == store.message(draft.messageID)?.commandId }) {
                        WorkspaceReplyBubble(draft: draft, compact: true, showsAvatar: !hasReplyAvatar(for: draft, in: visibleMessages))
                            .transition(reduced ? .opacity : .scale(scale: 0.82, anchor: .bottomLeading).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("team-live-bottom")
                }.scrollTargetLayout()
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
            }
            // Let the scroll view resolve its initial position during layout, rather
            // than scrolling through estimated heights of restored lazy rows.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            .defaultScrollAnchor(followsLatest ? .bottom : nil, for: .sizeChanges)
            .modifier(MacWorkspaceScrollAnchor())
            .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 72 } action: { _, value in
                nearBottom = value
                store.updateChatVisibility(store.selectedConversationID, atLatest: value)
            }
            .onScrollPhaseChange { old, phase in
                if phase == .interacting || phase == .decelerating || (phase == .idle && old != .animating) { followsLatest = nearBottom }
            }
            .task(id: tailUpdate) {
                guard presentedInitialTail else { presentedInitialTail = true; return }
                guard followsLatest else { return }
                // Coalesce message and tool snapshots, then let the new rows lay out once.
                await _Concurrency.Task.yield()
                guard !_Concurrency.Task.isCancelled, followsLatest else { return }
                let outgoing = tail.last?.role == .user
                withKAnimation(reduced, outgoing ? MacTeamMessageMotion.send : MacTeamMessageMotion.receive) {
                    proxy.scrollTo("team-live-bottom", anchor: .bottom)
                }
            }
            .task(id: store.selectedConversationID) {
                store.updateChatVisibility(store.selectedConversationID, atLatest: true)
            }
            .task(id: store.messageNavigationTarget) {
                guard let id = store.messageNavigationTarget, store.message(id)?.conversationId == store.selectedConversationID else { return }
                followsLatest = false
                history.reveal(id, in: store.currentVisibleMessages)
                timeline.synchronize(items: messages.map { .init(id: $0.metadata.id.uuidString, isUser: $0.role == .user) }, immediate: true, followingLatest: false)
                await _Concurrency.Task.yield()
                proxy.scrollTo(id, anchor: .center)
                store.messageNavigationTarget = nil
            }
            .onDisappear { store.clearChatVisibility(store.selectedConversationID) }
            .onChange(of: store.currentVisibleMessages.count) { previous, current in history.retainPosition(added: current - previous, followingLatest: followsLatest) }
            .task(id: MessageUpdate(ids: messages.map(\.metadata.id), reduced: reduced)) {
                let sent = timeline.synchronize(items: messages.map {
                    .init(id: $0.metadata.id.uuidString, isUser: $0.role == .user)
                }, immediate: reduced, followingLatest: followsLatest)
                if sent { followsLatest = true }
                do {
                    if sent && !reduced { try await _Concurrency.Task.sleep(for: MacTeamMessageMotion.sendLead) }
                    while !_Concurrency.Task.isCancelled && timeline.revealNext() {
                        try await _Concurrency.Task.sleep(for: MacTeamMessageMotion.replySpacing)
                    }
                } catch is CancellationError { }
                catch { assertionFailure("Unexpected message presentation delay") }
            }
            .overlay {
                GeometryReader { geometry in
                    MacTeamPointerInput(viewportInsets: geometry.safeAreaInsets).allowsHitTesting(false)
                }.allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { WorkspacePinnedGroupPlan().padding(.horizontal, 24).padding(.top, 6) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if isEmptyChat { welcome.padding(.bottom, 20) }
                WorkspaceVoicePanel()
                WorkspaceFeedback()
                MacWorkspaceComposer(teamLayout: true, showsStarters: isEmptyChat && !store.chatContent.agents.isEmpty, onInputFrameChange: { inputGeometry.frame = $0 }, onSend: { sendInputFrame = inputGeometry.frame })
            }.frame(maxWidth: isEmptyChat ? 660 : .infinity)
                .padding(.horizontal, 24).padding(.bottom, 12).padding(.top, isEmptyChat ? 62 : 6)
                .frame(maxWidth: .infinity, maxHeight: isEmptyChat ? .infinity : nil)
        }
        .coordinateSpace(name: MacTeamMessageMotion.coordinateSpace)
        .padding(.top, 66)
    }

    private func hasReplyAvatar(for draft: WorkspaceChatActivity.Draft, in messages: [BlotV3.Message]) -> Bool {
        guard let source = store.message(draft.messageID) else { return false }
        return messages.contains {
            $0.role == .assistant && $0.commandId == source.commandId && store.chatContent.hasVisibleContent($0)
                && (draft.agentIDs.isEmpty || $0.authorAgentId.map(draft.agentIDs.contains) == true)
        }
    }
}

/// Geometry and scroll observations stay outside the transcript's rendering state.
@MainActor private final class MacWorkspaceInputGeometry { var frame: CGRect? }

private struct MacWorkspaceScrollAnchor: ViewModifier {
    @State private var id: UUID?
    func body(content: Content) -> some View { content.scrollPosition(id: $id, anchor: .top) }
}

struct MacLiveTeamMessage: View {
    let message: BlotV3.Message
    let arriving: Bool
    let inputFrame: CGRect?
    let compact: Bool
    let showsAuthor: Bool
    let showsAvatar: Bool
    var showsActivity = true
    var showsResults = true
    var showsActions = true
    var showsGenerating = true
    var resultArtifactIDs: [UUID]? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var hoveringReply = false
    private var isUser: Bool { message.role == .user }
    private var repeatsDocumentCard: Bool {
        guard showsResults, message.role == .assistant, message.delivery == .completed,
              MacChatMessageContext.quoteID(message) == nil else { return false }
        let ids = resultArtifactIDs ?? message.artifactIds
        guard ids.count == 1, let file = store.chatContent.artifacts[ids[0]],
              !file.mediaType.hasPrefix("image/") else { return false }
        return WorkspaceDocumentReceipt.matches(message.content, fileName: file.name)
    }
    private var hasReplyActions: Bool { !isUser && showsActions && message.delivery == .completed && !message.content.isEmpty }
    private var agent: BlotV3.AgentProfile? {
        store.chatContent.agents.first { $0.metadata.id == (message.authorAgentId ?? store.currentConversation?.agentId) }
    }
    private var reactions: [BlotV3.MessageReaction] {
        store.chatContent.reactions[message.metadata.id] ?? []
    }
    var body: some View {
        HStack(alignment: WorkspaceChatStyle.avatarBaseline, spacing: 8) {
            if isUser { Spacer(minLength: 72) }
            else if store.currentConversation?.kind == .group {
                if showsAvatar, let agent { WorkspaceAvatarView(agent: agent, size: 24).padding(.bottom, 3) }
                else { Color.clear.frame(width: 24, height: 24) }
            }
            VStack(alignment: .leading, spacing: 4) {
                if !isUser && showsAuthor {
                    Text(agent?.name ?? "Ori").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(agent.map { WorkspaceAvatarView.color($0.avatarColor).opacity(0.8) } ?? WorkspaceStyle.secondary)
                        .padding(.leading, 12).padding(.top, 12).padding(.bottom, 2)
                }
                if store.chatContent.cards[message.metadata.id] == nil && !repeatsDocumentCard && (!message.content.isEmpty || isUser && !message.artifactIds.isEmpty) {
                VStack(alignment: .leading, spacing: 6) {
                    if let id = MacChatMessageContext.quoteID(message), let quoted = store.message(id), store.groupPlan(for: quoted) == nil {
                        WorkspaceQuotedMessage(message: quoted)
                    }
                    WorkspaceMessageBody(text: message.content, markdown: !isUser, agents: store.chatContent.agents, skills: store.chatContent.skills).font(.system(size: 15)).lineSpacing(4)
                    if store.chatContent.activities(for: message).isEmpty { WorkspaceMessagePlugins(message: message) }
                    if isUser {
                        ForEach(message.artifactIds, id: \.self) { id in
                            if let artifact = store.chatContent.artifacts[id] {
                                Button { store.showGeneratedFile(id) } label: { BlotLabel(artifact.name, symbol: "doc.text") }.buttonStyle(.plain)
                            }
                        }
                    }
                }.padding(.horizontal, 14).padding(.vertical, compact ? 8 : 11)
                    .foregroundStyle(WorkspaceStyle.ink)
                    .background(isUser ? MacWorkspaceStyle.outgoingMessage : MacChatStyle.incoming, in: RoundedRectangle(cornerRadius: 20))
                    .alignmentGuide(WorkspaceChatStyle.avatarBaseline) { $0[.bottom] }
                    .modifier(MacTeamPressMenu(secondaryClick: true) { close in
                        Group {
                            MacTeamMessageMenuLayout(choices: WorkspaceChatInteractions.reactions, react: { store.toggleReaction($0, to: message.metadata.id) },
                                selected: { store.chatInteractions.messages[message.metadata.id]?.reaction == $0 },
                                perform: { action in
                                    switch action {
                                    case .reply: store.beginReply(to: message.metadata.id)
                                    case .copy: WorkspaceClipboard.copy(message.content)
                                    case .remember: store.rememberMessage(message.metadata.id)
                                    }
                                }, close: close)
                            if message.role == .user {
                                Button(action: { store.retryResponse(to: message.metadata.id); close() }) {
                                    BlotLabel(store.t("Retry response"), symbol: "arrow.clockwise")
                                }.buttonStyle(MacMenuRowStyle()).disabled(store.isReplying)
                            }
                            MacActionMenu(edge: .trailing, isSubmenu: true) {
                                ForEach(WorkspaceExportFormat.allCases, id: \.self) { format in
                                    Button(format.rawValue.uppercased()) { store.exportMessage(message.metadata.id, format: format); close() }
                                }
                            } label: {
                                BlotLabel(store.t("Export"), symbol: "chevron.right", size: BlotIconSize.control)

                            }
                        }
                    })
                    .modifier(MacTeamSwipeToReply { store.beginReply(to: message.metadata.id) })
                    .modifier(MacTeamMessageEntrance(animated: arriving && isUser, outgoing: true, inputFrame: inputFrame))
                    .padding(.leading, 0)
                }
                if !isUser && showsActivity { WorkspaceToolActivityView(message: message, inline: true).frame(maxWidth: 600, alignment: .leading) }
                if !isUser && showsResults { WorkspaceMessageResults(message: message, artifactIDs: resultArtifactIDs) }
                if !(store.chatContent.cards[message.metadata.id] ?? []).isEmpty {
                    WorkspaceConversationCards(message: message)
                        .alignmentGuide(WorkspaceChatStyle.avatarBaseline) { $0[.bottom] }
                }
                HStack(spacing: 5) {
                ForEach(WorkspaceChatInteractions.reactions, id: \.self) { reaction in
                    let count = reactions.filter { $0.emoji == reaction }.count
                    let mine = store.chatInteractions.messages[message.metadata.id]?.reaction == reaction
                    if count > 0 {
                    Button { store.toggleReaction(reaction, to: message.metadata.id) } label: {
                        HStack(spacing: 4) {
                            Text(reaction).font(.system(size: 14))
                            Text("\(count)").font(.system(size: 10, weight: .medium)).monospacedDigit()
                        }.padding(.horizontal, 8).padding(.vertical, 5)
                            .background(WorkspaceStyle.ink.opacity(mine ? 0.12 : 0.045), in: Capsule())
                            .overlay(Capsule().strokeBorder(WorkspaceStyle.ink.opacity(mine ? 0.35 : 0.08)))
                    }.buttonStyle(BlotPlainButtonStyle())
                        .accessibilityLabel((store.language == "ru" ? "Реакция " : "Reaction ") + reaction)
                    }
                }
                }
                if (showsGenerating && message.delivery == .running) || [.failed, .canceled, .interrupted].contains(message.delivery) {
                    Text(store.deliveryTitle(message.delivery)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                if hasReplyActions {
                    MacWorkspaceReplyActions(message: message, isHovered: hoveringReply)
                }
            }
            .contentShape(Rectangle())
            .onHover { if hasReplyActions { hoveringReply = $0 } }
            .frame(maxWidth: 760, alignment: isUser ? .trailing : .leading)
            .kAnimation(KMotion.standard, value: reactions)
            if !isUser { Spacer(minLength: 44) }
        }
        .modifier(MacTeamMessageEntrance(animated: arriving && !isUser, outgoing: false))
    }
}
