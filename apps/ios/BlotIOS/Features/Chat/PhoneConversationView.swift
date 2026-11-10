import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneConversationView: View {
    @AppStorage(PhoneSettingsPreferenceKey.compactMessages) private var compactMessages = false
    @Environment(WorkspaceStore.self) private var store
    @State private var pinnedNavigation = PhonePinnedMessageNavigation()
    @State private var visibleMessageIDs: Set<UUID> = []
    @State private var showsPinnedMessages = false
    @State private var followsLatest = true
    @State private var visibleConversationID: UUID?
    @State private var history = WorkspaceTranscriptWindow()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blotReduceMotion) private var reduceMotion

    private var activeDraft: WorkspaceChatActivity.Draft? {
        store.currentReplyDraft
    }

    private var identity: PhoneConversationIdentity {
        .init(conversation: store.currentConversation, agents: store.chatContent.agents, participants: store.chatContent.participants)
    }
    private var agent: BlotV3.AgentProfile? { identity.agent }

    var body: some View {
        let rows = PhoneMessageTimeline.rows(in: Array(history.messages(in: store.currentVisibleMessages)))
        let ids = rows.map(\.id)
        let animation = reduceMotion ? nil : PhoneMessageMotion.spring
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if history.hasEarlier(in: store.currentVisibleMessages) {
                        Button(store.language == "ru" ? "Загрузить предыдущие сообщения" : "Load earlier messages") {
                            let anchor = rows.first?.id
                            followsLatest = false
                            history.loadEarlier()
                            _Concurrency.Task { await _Concurrency.Task.yield(); if let anchor { proxy.scrollTo(anchor, anchor: .top) } }
                        }.font(.callout).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    if let first = rows.first?.message {
                        HStack(spacing: 4) {
                            Text(Calendar.current.isDateInToday(first.metadata.createdAt) ? store.t("Today") : first.metadata.createdAt.formatted(date: .abbreviated, time: .omitted))
                            Text(first.metadata.createdAt, format: .dateTime.hour().minute())
                        }.font(.caption2).foregroundStyle(WorkspaceStyle.secondary.opacity(0.65))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    ForEach(rows) { row in messageRow(row) }
                    if rows.isEmpty, activeDraft == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            if store.currentConversation?.kind == .group {
                                Text(store.t("Set a shared task for the team")).font(.title3.weight(.medium))
                            } else {
                                WorkspaceWelcomeGreeting().font(.title3.weight(.medium))
                                if let agent { Text(agent.instructions).foregroundStyle(WorkspaceStyle.secondary) }
                            }
                        }.padding(16)
                    }
                    if let activeDraft {
                        WorkspaceReplyBubble(draft: activeDraft).padding(.top, 16)
                            .transition(reduceMotion ? .opacity : .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
                    }
                    WorkspaceFeedback()
                    if let id = store.selectedConversationID, store.failedSends[id] != nil {
                        BlotIconButton(store.t("Retry"), symbol: "arrow.clockwise") {
                            _Concurrency.Task { await store.retryFailedSend() }
                        }.buttonStyle(.plain).disabled(store.busy)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }.scrollTargetLayout().padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)
                    .animation(visibleConversationID == store.selectedConversationID ? animation : nil, value: ids.last)
                    .animation(animation, value: activeDraft)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.01) { ids in
                visibleMessageIDs = Set(ids)
                updatePinnedNavigation()
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting || phase == .decelerating {
                    pinnedNavigation.beginScrolling()
                    updatePinnedNavigation()
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 80
            } action: { _, nearBottom in
                followsLatest = nearBottom
                updatePinnedNavigation()
                updateVisibility()
            }
            .onChange(of: ids, initial: true) { previous, ids in
                pinnedNavigation.setMessageOrder(store.currentMessageIDs)
                updatePinnedNavigation()
                if previous.last != ids.last && (followsLatest || rows.last?.message.role == .user) {
                    withAnimation(visibleConversationID == store.selectedConversationID ? animation : nil) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
            }
            .task(id: store.messageNavigationTarget) {
                guard let id = store.messageNavigationTarget,
                      store.currentMessages.contains(where: { $0.metadata.id == id }) else { return }
                history.reveal(id, in: store.currentVisibleMessages)
                await _Concurrency.Task.yield()
                followsLatest = false
                pinnedNavigation.reveal(id)
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) {
                    proxy.scrollTo(id, anchor: .center)
                }
                store.messageNavigationTarget = nil
                updateVisibility()
            }
            .onChange(of: activeDraft) { _, _ in
                if followsLatest { withAnimation(animation) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                header
                if let pinned = pinnedNavigation.selected(in: store.currentPinnedMessages) {
                    PhonePinnedMessagesBar(message: pinned,
                        index: store.currentPinnedMessages.firstIndex(where: { $0.metadata.id == pinned.metadata.id }) ?? 0,
                        count: store.currentPinnedMessages.count,
                        select: { selectPinnedMessage(pinned.metadata.id) },
                        showList: { showsPinnedMessages = true })
                }
            }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PhoneConversationComposer().padding(.horizontal, 30).padding(.vertical, 10)
        }
        .workspaceGlassContainer()
        .sheet(isPresented: $showsPinnedMessages) {
            PhonePinnedMessagesList(select: selectPinnedMessage).environment(store)
        }
        .onChange(of: store.currentPinnedMessages.map(\.metadata.id), initial: true) { _, _ in
            pinnedNavigation.reconcile(store.currentPinnedMessages)
        }
        .task(id: pinnedNavigation.highlightedID) {
            guard let id = pinnedNavigation.highlightedID else { return }
            do { try await _Concurrency.Task<Never, Never>.sleep(for: .seconds(1.5)) }
            catch { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { pinnedNavigation.clearHighlight(id) }
        }
        .onAppear { visibleConversationID = store.selectedConversationID; updateVisibility() }
        .onChange(of: scenePhase) { _, _ in updateVisibility() }
        .onChange(of: store.selectedConversationID) { old, new in
            store.clearChatVisibility(old); visibleConversationID = new; followsLatest = true
            history.reset()
            pinnedNavigation.reset(); pinnedNavigation.setMessageOrder(store.currentMessageIDs); pinnedNavigation.reconcile(store.currentPinnedMessages)
            visibleMessageIDs = []; showsPinnedMessages = false; updateVisibility()
        }
        .onChange(of: store.currentVisibleMessages.count) { previous, current in history.retainPosition(added: current - previous, followingLatest: followsLatest) }
        .onDisappear { store.clearChatVisibility(visibleConversationID) }

    }

    private func messageRow(_ row: PhoneMessageTimeline.Row) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let plan = store.groupPlan(for: row.message) {
                WorkspaceGroupPlanCard(plan: plan, agents: store.chatContent.agents, skills: store.chatContent.skills, russian: store.language == "ru")
                    .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20))
                    .contextMenu { WorkspaceMessageActionsMenu(message: row.message).environment(store) }
            } else {
                PhoneMessageBubble(message: row.message, showsDelivery: row.showsDelivery) { id in
                    store.messageNavigationTarget = id
                }
            }
            ForEach(row.message.artifactIds.compactMap { store.chatContent.artifacts[$0] }, id: \.metadata.id) { file in
                Button {
                    store.selectedRecordID = file.metadata.id
                    store.navigate(.file)
                } label: { PhoneFileRow(file: file) }
                    .buttonStyle(.plain).padding(.trailing, 44)
            }
        }
        .padding(.top, compactMessages ? row.spacing * 0.65 : row.spacing)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(WorkspaceStyle.ink.opacity(pinnedNavigation.highlightedID == row.id ? 0.09 : 0))
        }
        .id(row.id)
        .transition(PhoneMessageMotion.arrival(for: row.message.role, reduced: reduceMotion))
    }

    private func selectPinnedMessage(_ id: UUID) {
        pinnedNavigation.selectPin(id, in: store.currentPinnedMessages)
        store.messageNavigationTarget = id
    }

    private func updatePinnedNavigation() {
        pinnedNavigation.update(visibleIDs: visibleMessageIDs, pins: store.currentPinnedMessages, atBottom: followsLatest)
    }

    private func updateVisibility() {
        store.updateChatVisibility(scenePhase == .active ? store.selectedConversationID : nil, atLatest: followsLatest)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { store.back() }
            PhoneConversationTitle(identity: identity)
            Spacer(minLength: 0)
            Menu {
                Button { store.showBrowser() } label: { Label(store.language == "ru" ? "Браузер" : "Browser", systemImage: "globe") }
                BlotIconButton(store.t("Skills"), symbol: "shippingbox") { store.navigate(.skills) }
                BlotIconButton(store.t("Schedule this task"), symbol: "calendar.badge.plus") { store.navigate(.createSchedule) }
                BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                BlotIconButton(store.t("Computers"), symbol: "desktopcomputer") { store.navigate(.devices) }
                BlotIconButton(store.t("Task details"), symbol: "list.bullet") { store.navigate(.running) }
                if let chat = store.currentConversation { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
            } label: {
                BlotIcon(symbol: "ellipsis").font(.title3)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .frame(width: 44, height: 44)
            .accessibilityLabel(store.t("Chat actions"))
        }
    }


}

private struct PhoneMessageBubble: View {
    @AppStorage(PhoneSettingsPreferenceKey.compactMessages) private var compactMessages = false
    let message: BlotV3.Message
    let showsDelivery: Bool
    let showMessage: (UUID) -> Void
    @Environment(WorkspaceStore.self) private var store

    private var isUser: Bool { message.role == .user }
    private var metadata: WorkspaceMessageMetadata? { store.chatInteractions.messages[message.metadata.id] }
    private var quoted: BlotV3.Message? {
        guard let id = metadata?.replyToMessageID ?? message.replyToMessageId else { return nil }
        guard let value = store.message(id), store.groupPlan(for: value) == nil else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if message.role == .assistant, store.currentConversation?.kind == .group {
                PhoneGroupMessageAuthor(message: message)
            }
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    if let quoted {
                        Button { showMessage(quoted.metadata.id) } label: { WorkspaceQuotedMessage(message: quoted) }
                            .buttonStyle(.plain)
                    }
                    WorkspaceMessageText(text: store.mode == .live ? message.content : store.t(message.content), markdown: !isUser, agents: store.chatContent.agents, skills: store.chatContent.skills).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                    WorkspaceMessagePlugins(message: message)
                }
                .foregroundStyle(WorkspaceStyle.ink)
                .padding(.horizontal, compactMessages ? 12 : 14).padding(.vertical, compactMessages ? 8 : 12)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 26))
                .contextMenu { WorkspaceMessageActionsMenu(message: message).environment(store) }
                if !isUser { Spacer(minLength: 44) }
            }
            if let reaction = metadata?.reaction {
                Button { store.toggleReaction(reaction, to: message.metadata.id) } label: {
                    Text(reaction).font(.system(size: 20)).padding(.horizontal, 9).padding(.vertical, 4)
                        .background(WorkspaceStyle.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(WorkspaceStyle.secondary.opacity(0.15)))
                }.buttonStyle(.plain).padding(.horizontal, 14).accessibilityLabel(store.t("Remove reaction") + " " + reaction)
            }
            if store.mode == .live && showsDelivery {
                Text(store.deliveryTitle(message.delivery)).font(.caption2).foregroundStyle(WorkspaceStyle.secondary).padding(.trailing, 14)
            } else if isUser && showsDelivery {
                let read = message.delivery == .completed || store.chatActivity.readMessageIDs.contains(message.metadata.id) || store.chatInteractions.agentReadMessageIDs?.contains(message.metadata.id) == true
                Text(store.t(read ? "Read" : "Sent")).font(.caption2)
                    .foregroundStyle(WorkspaceStyle.secondary).padding(.trailing, 14)
            }
        }
    }
}

