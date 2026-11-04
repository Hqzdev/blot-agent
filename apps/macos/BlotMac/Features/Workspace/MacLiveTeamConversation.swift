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
    @State private var inputFrame: CGRect?
    @State private var sendInputFrame: CGRect?

    init(messages: [BlotV3.Message]) {
        _timeline = State(initialValue: MacTeamMessageTimeline(items: messages.filter(WorkspaceMessagePresentation.isVisible).map {
            .init(id: $0.metadata.id.uuidString, isUser: $0.role == .user)
        }))
    }

    private struct MessageUpdate: Equatable {
        let ids: [UUID]
        let reduced: Bool
    }
    private var messages: [BlotV3.Message] { store.currentMessages.filter(WorkspaceMessagePresentation.isVisible) }
    private var reduced: Bool { reduceMotion || systemReduceMotion }
    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == (store.currentConversation?.agentId ?? store.selectedAgentID) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compactMessages ? 16 : 24) {
                    if messages.isEmpty, store.currentReplyDraft == nil {
                        VStack(spacing: 16) {
                            if let agent { WorkspaceAvatarView(agent: agent, size: 68, animated: true) }
                            else { WorkspaceAnimatedAvatar(size: 68) }
                            Group {
                                if store.snapshot.agents.isEmpty { Text("Создайте своего первого агента") }
                                else { WorkspaceWelcomeGreeting() }
                            }.font(.system(size: 25, weight: .medium)).multilineTextAlignment(.center)
                            if store.snapshot.agents.isEmpty {
                                Button("Создать агента") { store.navigate(.createAgent) }.buttonStyle(WorkspaceButtonStyle())
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 100)
                    }
                    ForEach(messages.filter { timeline.visibleIDs.contains($0.metadata.id.uuidString) }, id: \.metadata.id) { message in
                        MacLiveTeamMessage(message: message, arriving: timeline.entranceIDs.contains(message.metadata.id.uuidString),
                            inputFrame: sendInputFrame ?? inputFrame, compact: compactMessages)
                            .id(message.metadata.id).transition(.identity)
                            .onAppear { timeline.didAppear(message.metadata.id.uuidString) }
                    }
                    if let draft = store.currentReplyDraft {
                        WorkspaceReplyBubble(draft: draft, compact: true)
                            .transition(reduced ? .opacity : .scale(scale: 0.82, anchor: .bottomLeading).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("team-live-bottom")
                }.frame(maxWidth: 680, alignment: .leading).padding(.horizontal, 28).padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 72 } action: { _, value in
                nearBottom = value
                store.updateChatVisibility(store.selectedConversationID, atLatest: value)
            }
            .onScrollPhaseChange { old, phase in
                if phase == .interacting || phase == .decelerating || (phase == .idle && old != .animating) { followsLatest = nearBottom }
            }
            .onChange(of: timeline.lastRevealedID) { _, _ in
                guard followsLatest else { return }
                let outgoing = store.currentMessages.first { $0.metadata.id.uuidString == timeline.lastRevealedID }?.role == .user
                withKAnimation(reduced, outgoing ? MacTeamMessageMotion.send : MacTeamMessageMotion.receive) {
                    proxy.scrollTo("team-live-bottom", anchor: .bottom)
                }
            }
            .onChange(of: messages.last) { _, message in
                if followsLatest || message?.role == .user { proxy.scrollTo("team-live-bottom", anchor: .bottom) }
            }
            .onChange(of: store.currentReplyDraft) { _, _ in
                guard followsLatest else { return }
                withKAnimation(reduced, MacTeamMessageMotion.receive) { proxy.scrollTo("team-live-bottom", anchor: .bottom) }
            }
            .task(id: store.selectedConversationID) {
                followsLatest = true
                proxy.scrollTo("team-live-bottom", anchor: .bottom)
                store.updateChatVisibility(store.selectedConversationID, atLatest: true)
            }
            .onDisappear { store.clearChatVisibility(store.selectedConversationID) }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                WorkspaceFeedback()
                MacWorkspaceComposer(teamLayout: true, onInputFrameChange: { inputFrame = $0 }, onSend: { sendInputFrame = inputFrame })
            }.frame(maxWidth: 730).padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 8)
                .frame(maxWidth: .infinity).background(WorkspaceStyle.canvas)
        }
        .coordinateSpace(name: MacTeamMessageMotion.coordinateSpace)
        .kAnimation(MacTeamMessageMotion.receive, value: timeline.visibleIDs)
        .kAnimation(MacTeamMessageMotion.receive, value: store.currentReplyDraft)
    }
}

private struct MacLiveTeamMessage: View {
    let message: BlotV3.Message
    let arriving: Bool
    let inputFrame: CGRect?
    let compact: Bool
    @Environment(WorkspaceStore.self) private var store
    private var isUser: Bool { message.role == .user }
    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == (message.authorAgentId ?? store.currentConversation?.agentId) }
    }
    private var reactions: [BlotV3.MessageReaction] {
        (store.snapshot.reactions ?? []).filter { $0.messageId == message.metadata.id && !$0.removed }
    }
    var body: some View {
        HStack(alignment: .top) {
            if isUser { Spacer(minLength: 54) }
            VStack(alignment: .leading, spacing: 12) {
                if !isUser {
                    HStack(spacing: 9) {
                        if let agent { WorkspaceAvatarView(agent: agent, size: 22) }
                        Text(agent?.name ?? "Blot").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(agent.map { WorkspaceAvatarView.color($0.avatarColor) } ?? WorkspaceStyle.ink)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let id = message.replyToMessageId, let quoted = store.currentMessages.first(where: { $0.metadata.id == id }) {
                        WorkspaceQuotedMessage(message: quoted)
                    }
                    WorkspaceMessageText(text: message.content, markdown: !isUser).font(.system(size: 13)).lineSpacing(4)
                    ForEach(message.artifactIds, id: \.self) { id in
                        if let artifact = store.snapshot.artifacts.first(where: { $0.metadata.id == id }) {
                            Button { store.selectedRecordID = id; store.navigate(.file) } label: {
                                Label(artifact.name, systemImage: "doc.text").frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(.horizontal, 16).padding(.vertical, compact ? 9 : 12)
                    .background(isUser ? MacTeamStyle.field : WorkspaceStyle.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 20))
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
                                MacTeamNavigationButton(action: { store.retryResponse(to: message.metadata.id); close() }) {
                                    BlotLabel(store.t("Retry response"), symbol: "arrow.clockwise")
                                }.disabled(store.isReplying)
                            }
                            Menu(store.t("Export")) {
                                ForEach(WorkspaceExportFormat.allCases, id: \.self) { format in
                                    Button(format.rawValue.uppercased()) { store.exportMessage(message.metadata.id, format: format); close() }
                                }
                            }
                        }
                    })
                    .modifier(MacTeamSwipeToReply { store.beginReply(to: message.metadata.id) })
                    .modifier(MacTeamMessageEntrance(animated: arriving && isUser, outgoing: true, inputFrame: inputFrame))
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
                        .accessibilityLabel("Реакция " + reaction)
                    }
                }
                }
                if [.running, .failed, .canceled, .interrupted].contains(message.delivery) {
                    Text(store.deliveryTitle(message.delivery)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .kAnimation(KMotion.standard, value: reactions)
            if !isUser { Spacer(minLength: 0) }
        }
        .modifier(MacTeamMessageEntrance(animated: arriving && !isUser, outgoing: false))
    }
}
