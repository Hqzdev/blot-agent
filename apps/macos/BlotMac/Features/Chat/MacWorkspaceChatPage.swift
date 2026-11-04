import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceChatPage: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var followsLatest = false
    @State private var visibleConversationID: UUID?
    private var activeDraft: WorkspaceChatActivity.Draft? {
        store.selectedConversationID.flatMap { store.chatActivity.drafts[$0] }
    }
    private var isHome: Bool { route == .home || route == .newChat }

    var body: some View {
        Group {
            if isHome { welcome }
            else { conversation.id(store.selectedConversationID) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                WorkspaceFeedback().font(MacWorkspaceStyle.caption)
                MacWorkspaceComposer()
            }.frame(maxWidth: MacWorkspaceStyle.composerWidth)
                .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 14)
                .frame(maxWidth: .infinity)
                .background(WorkspaceStyle.canvas)
        }
        .background(WorkspaceStyle.canvas)
    }

    private var welcome: some View {
        GeometryReader { geometry in
            VStack(spacing: 22) {
                WorkspaceAvatar(size: 44).opacity(0.38)
                Text(store.t("What are we doing today?"))
                    .font(.system(size: 26, weight: .regular))
                    .multilineTextAlignment(.center).accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 24).frame(maxWidth: 620)
            .position(x: geometry.size.width / 2, y: geometry.size.height * 0.46)
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(store.desktopContent.blocks(at: .top, in: store.selectedConversationID)) { block in
                        MacConversationBlockView(block: block)
                    }
                    if let first = store.currentMessages.first {
                        Text(first.metadata.createdAt, format: .dateTime.hour().minute())
                            .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                            .frame(maxWidth: .infinity).padding(.top, 20).padding(.bottom, 12)
                    }
                    ForEach(store.currentMessages, id: \.metadata.id) { message in
                        MacMessageBubble(message: message) { id in proxy.scrollTo(id, anchor: .center) }
                            .id(message.metadata.id)
                        ForEach(store.snapshot.artifacts.filter { message.artifactIds.contains($0.metadata.id) }, id: \.metadata.id) { file in
                            attachment(file).padding(.trailing, 70)
                        }
                        ForEach(store.desktopContent.blocks(at: .after(message.metadata.id), in: store.selectedConversationID)) { block in
                            MacConversationBlockView(block: block)
                        }
                    }
                    if store.currentMessages.isEmpty && store.desktopContent.blocks(at: .top, in: store.selectedConversationID).isEmpty {
                        Text(store.t("What would you like to work on?"))
                            .font(.system(size: 20)).foregroundStyle(WorkspaceStyle.secondary).padding(.top, 32)
                    }
                    if let activeDraft { WorkspaceReplyBubble(draft: activeDraft, compact: true) }
                    if let id = store.selectedConversationID, store.failedSends[id] != nil {
                        BlotIconButton(store.t("Retry"), symbol: "arrow.clockwise") {
                            _Concurrency.Task { await store.retryFailedSend() }
                        }.buttonStyle(.plain).disabled(store.busy)
                    }
                    if store.mode == .preview && !store.currentMessages.isEmpty { WorkspaceTaskPlan() }
                    Color.clear.frame(height: 1).id("mac-conversation-bottom")
                }.frame(maxWidth: MacWorkspaceStyle.readingWidth)
                    .padding(.horizontal, 20).padding(.bottom, 12).frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { $0.visibleRect.maxY >= $0.contentSize.height - 50 } action: { _, nearBottom in
                followsLatest = nearBottom; updateVisibility()
            }
            .onChange(of: store.currentMessages.count) { _, _ in
                if followsLatest || store.currentMessages.last?.role == .user { proxy.scrollTo("mac-conversation-bottom", anchor: .bottom) }
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
                if followsLatest { proxy.scrollTo("mac-conversation-bottom", anchor: .bottom) }
            }
            .onAppear {
                visibleConversationID = store.selectedConversationID
                if let id = store.selectedConversationID, store.chatInteractions.unreadCount(in: id) > 0 {
                    proxy.scrollTo("mac-conversation-bottom", anchor: .bottom)
                }
                updateVisibility()
            }
            .onChange(of: scenePhase) { _, _ in updateVisibility() }
            .onChange(of: store.selectedConversationID) { old, _ in
                store.clearChatVisibility(old); visibleConversationID = store.selectedConversationID; followsLatest = true
                proxy.scrollTo("mac-conversation-bottom", anchor: .bottom); updateVisibility()
            }
            .onDisappear { store.clearChatVisibility(visibleConversationID) }
        }
    }

    private func updateVisibility() {
        store.updateChatVisibility(scenePhase == .active && !isHome ? store.selectedConversationID : nil, atLatest: followsLatest)
    }

    private func attachment(_ file: BlotV3.Artifact) -> some View {
        Button {
            store.selectedRecordID = file.metadata.id
            store.navigate(.file)
        } label: {
            HStack(spacing: 10) {
                BlotIcon(file.mediaType == "application/pdf" ? .pdf : file.mediaType.hasPrefix("image/") ? .image : .document, size: 22)
                    .foregroundStyle(file.mediaType == "application/pdf" ? Color.red : WorkspaceStyle.secondary)
                    .frame(width: 34, height: 38).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(file.byteCount), countStyle: .file))
                        .font(.system(size: 11)).foregroundStyle(WorkspaceStyle.secondary)
                }
                Spacer(minLength: 0)
                BlotIcon(.download, size: 14).foregroundStyle(WorkspaceStyle.secondary)
            }.padding(7).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(MacWorkspaceStyle.edge))
        }.buttonStyle(.plain)
    }
}
