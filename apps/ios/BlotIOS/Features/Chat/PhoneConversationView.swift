import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneConversationView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var followsLatest = true
    @State private var visibleConversationID: UUID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.blotReduceMotion) private var reduceMotion

    private var activeDraft: WorkspaceChatActivity.Draft? {
        store.currentReplyDraft
    }

    private var agent: BlotV3.AgentProfile? {
        store.snapshot.agents.first { $0.metadata.id == store.currentConversation?.agentId }
    }

    var body: some View {
        let rows = PhoneMessageTimeline.rows(in: store.currentMessages)
        let ids = rows.map(\.id)
        let animation = reduceMotion ? nil : PhoneMessageMotion.spring
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let first = rows.first?.message {
                        HStack(spacing: 4) {
                            Text(Calendar.current.isDateInToday(first.metadata.createdAt) ? store.t("Today") : first.metadata.createdAt.formatted(date: .abbreviated, time: .omitted))
                            Text(first.metadata.createdAt, format: .dateTime.hour().minute())
                        }.font(.caption2).foregroundStyle(WorkspaceStyle.secondary.opacity(0.65))
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    ForEach(rows) { row in
                        let message = row.message
                        PhoneMessageBubble(message: message, showsDelivery: row.showsDelivery) { id in
                            withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                        }
                            .id(message.metadata.id)
                            .padding(.top, row.spacing)
                            .transition(PhoneMessageMotion.arrival(for: message.role, reduced: reduceMotion))
                        ForEach(store.snapshot.artifacts.filter { message.artifactIds.contains($0.metadata.id) }, id: \.metadata.id) { file in
                            Button {
                                store.selectedRecordID = file.metadata.id
                                store.navigate(.file)
                            } label: { PhoneFileRow(file: file) }
                                .buttonStyle(.plain).padding(.trailing, 44)
                        }

                    }
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
                }.padding(.horizontal, 16).padding(.top, 68).padding(.bottom, 8)
                    .animation(visibleConversationID == store.selectedConversationID ? animation : nil, value: ids)
                    .animation(animation, value: activeDraft)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 80
            } action: { _, nearBottom in
                followsLatest = nearBottom
                updateVisibility()
            }
            .onChange(of: ids) { _, _ in
                if followsLatest || rows.last?.message.role == .user {
                    withAnimation(visibleConversationID == store.selectedConversationID ? animation : nil) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
            }
            .task(id: store.messageNavigationTarget) {
                guard let id = store.messageNavigationTarget,
                      store.currentMessages.contains(where: { $0.metadata.id == id }) else { return }
                await _Concurrency.Task.yield()
                followsLatest = false
                proxy.scrollTo(id, anchor: .center)
                store.messageNavigationTarget = nil
                updateVisibility()
            }
            .onChange(of: activeDraft) { _, _ in
                if followsLatest { withAnimation(animation) { proxy.scrollTo("conversation-bottom", anchor: .bottom) } }
            }
        }
        .overlay(alignment: .top) { header.padding(.horizontal, 18).padding(.top, 6) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PhoneConversationComposer().padding(.horizontal, 30).padding(.vertical, 10)
        }
        .workspaceGlassContainer()
        .onAppear { visibleConversationID = store.selectedConversationID; updateVisibility() }
        .onChange(of: scenePhase) { _, _ in updateVisibility() }
        .onChange(of: store.selectedConversationID) { old, new in
            store.clearChatVisibility(old); visibleConversationID = new; followsLatest = true; updateVisibility()
        }
        .onDisappear { store.clearChatVisibility(visibleConversationID) }

    }

    private func updateVisibility() {
        store.updateChatVisibility(scenePhase == .active ? store.selectedConversationID : nil, atLatest: followsLatest)
    }

    private var header: some View {
        HStack(spacing: 8) {
            PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { store.back() }
            Button { store.agentPickerVisible = true } label: {
                PhoneGlassCapsule {
                    HStack(spacing: 8) {
                        if let agent { WorkspaceAvatarView(agent: agent, size: 26) }
                        else { WorkspaceAvatar(size: 26) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent?.name ?? "Blot Agent").font(.body.weight(.medium)).lineLimit(1)
                            if let id = store.selectedConversationID, store.chatActivity.isTyping(in: id) {
                                WorkspaceTypingPreview().font(.caption2)
                            } else {
                                HStack(spacing: 4) {
                                    WorkspacePresenceDot(online: store.isAgentOnline(agent?.metadata.id, in: store.selectedConversationID), size: 6)
                                    Text(store.t(store.isAgentOnline(agent?.metadata.id, in: store.selectedConversationID) ? "Online" : "Not online"))
                                }.font(.caption2).foregroundStyle(WorkspaceStyle.secondary)
                            }
                        }
                        BlotIcon(symbol: "chevron.down", size: 12).font(.caption2)
                    }
                }
            }.buttonStyle(.plain).accessibilityLabel(store.t("Choose an agent"))
            Spacer(minLength: 0)
            Menu {
                BlotIconButton(store.t("Schedule this task"), symbol: "calendar.badge.plus") { store.navigate(.createSchedule) }
                BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                BlotIconButton(store.t("Computers"), symbol: "desktopcomputer") { store.navigate(.devices) }
                BlotIconButton(store.t("Task details"), symbol: "list.bullet") { store.navigate(.running) }
                if let chat = store.currentConversation { WorkspaceChatActionsMenu(chat: chat).environment(store).disabled(store.busy) }
            } label: {
                BlotIcon(symbol: "ellipsis").font(.title3).frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }.accessibilityLabel(store.t("Chat actions"))
        }
    }


}

private struct PhoneMessageBubble: View {
    let message: BlotV3.Message
    let showsDelivery: Bool
    let showMessage: (UUID) -> Void
    @Environment(WorkspaceStore.self) private var store

    private var isUser: Bool { message.role == .user }
    private var metadata: WorkspaceMessageMetadata? { store.chatInteractions.messages[message.metadata.id] }
    private var quoted: BlotV3.Message? {
        guard let id = metadata?.replyToMessageID ?? message.replyToMessageId else { return nil }
        return store.currentMessages.first { $0.metadata.id == id }
    }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 44) }
                VStack(alignment: .leading, spacing: 8) {
                    if let quoted {
                        Button { showMessage(quoted.metadata.id) } label: { WorkspaceQuotedMessage(message: quoted) }
                            .buttonStyle(.plain)
                    }
                    WorkspaceMessageText(text: store.mode == .live ? message.content : store.t(message.content), markdown: !isUser).font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(WorkspaceStyle.ink)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 26))
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

