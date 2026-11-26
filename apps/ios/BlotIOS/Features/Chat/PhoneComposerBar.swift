import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

/// One glass capsule contains attachment, text, and sending controls.
struct PhoneComposerBar: View {
    let menu: PhoneComposerMenuState
    let loadingAttachments: Bool
    let canSend: Bool
    @FocusState.Binding var focused: Bool
    let send: () -> Void
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.blotReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .bottom, spacing: 2) {
            Button {
                withKAnimation(reduceMotion, KMotion.panel) { menu.open() }
            } label: {
                BlotIcon(.plus, size: 23).frame(width: 34, height: 34)
                    .background(WorkspaceStyle.ink.opacity(0.055), in: Circle()).frame(width: 44, height: 48)
                    .foregroundStyle(colorScheme == .dark ? Color.white : WorkspaceStyle.ink)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.busy || loadingAttachments)
            .accessibilityLabel(store.t("Add attachment"))

            TextField(store.currentConversation?.kind == .group ? store.t("Message group") + " «" + (store.currentConversation?.title ?? "") + "»" : store.t("Ask") + " " + agentName, text: $store.form.composer.draft, axis: .vertical)
                .font(.body).textFieldStyle(.plain).lineLimit(1...5)
                .focused($focused).disabled(store.busy)
                .padding(.vertical, 14).padding(.leading, 2)
                .accessibilityLabel(store.t("Message"))

            sendingControl.frame(width: 44, height: 48)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(WorkspaceStyle.ink)
        .opacity(menu.isOpen ? 0 : 1)
        .allowsHitTesting(!menu.isOpen).accessibilityHidden(menu.isOpen)
        .frame(width: menu.isOpen ? 60 : nil, height: menu.isOpen ? 52 : nil)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 28))
        .overlay {
            if menu.isOpen {
                Button {
                    withKAnimation(reduceMotion, KMotion.panel) { menu.dismiss() }
                    focused = true
                } label: {
                    BlotIcon(symbol: "keyboard", size: 22)
                        .frame(maxWidth: .infinity, minHeight: 52).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityLabel(store.t("Message"))
            }
        }
        .kAnimation(KMotion.standard, value: canSend)
        .kAnimation(KMotion.standard, value: store.isReplying)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .anchorPreference(key: PhoneComposerMenuAnchor.self, value: .bounds) { bounds in
            .init(bounds: bounds, menu: menu)
        }
        .onChange(of: store.form.composer.draft) { _, _ in
            if menu.page == .sources {
                withKAnimation(reduceMotion, KMotion.panel) { menu.dismiss() }
            }
        }
    }

    private var agentName: String {
        store.snapshot.agents.first { $0.metadata.id == store.currentConversation?.agentId }?.name ?? "Ori"
    }

    @ViewBuilder private var sendingControl: some View {
        if loadingAttachments && !store.isReplying {
            ProgressView().accessibilityLabel(store.t("Adding attachments"))
        } else {
            Button {
                if store.isReplying { store.stopReply() }
                else if canSend && !store.busy { send() }
                else if store.voice.isActive { store.voice.end() }
                else { store.beginVoiceConversation() }
            } label: {
                BlotIcon(symbol: store.isReplying ? "stop.fill" : (canSend ? "arrow.up" : (store.voice.isActive ? "mic.slash.fill" : "mic.fill")), size: store.isReplying ? 13 : 18)
                    .foregroundStyle(BlotColor.onInverse)
                    .frame(width: 34, height: 34).background(BlotColor.inverse, in: Circle())
                    .frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isReplying && !store.voice.isActive && (store.busy || (!canSend && (store.mode != .live || store.selectedConversationID == nil || store.route != .chat))))
            .accessibilityLabel(store.t(store.isReplying ? "Stop reply" : (canSend ? "Send message" : (store.voice.isActive ? "End voice conversation" : "Call agent"))))
        }
    }
}
