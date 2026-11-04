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
    @Environment(\.blotReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var store = store
        HStack(alignment: .bottom, spacing: 2) {
            Button {
                withKAnimation(reduceMotion, KMotion.panel) { menu.open() }
            } label: {
                BlotIcon(.plus, size: 26).frame(width: 44, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(store.busy || loadingAttachments)
            .accessibilityLabel(store.t("Add attachment"))

            TextField(store.t("Ask") + " " + agentName, text: $store.form.composer.draft, axis: .vertical)
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
        store.snapshot.agents.first { $0.metadata.id == store.currentConversation?.agentId }?.name ?? "Blot Agent"
    }

    @ViewBuilder private var sendingControl: some View {
        if loadingAttachments && !store.isReplying {
            ProgressView().accessibilityLabel(store.t("Adding attachments"))
        } else {
            Button {
                if store.isReplying { store.stopReply() }
                else { send() }
            } label: {
                BlotIcon(symbol: store.isReplying ? "stop.fill" : "arrow.up", size: store.isReplying ? 13 : 18)
                    .foregroundStyle(BlotColor.onInverse.opacity(canSend || store.isReplying ? 1 : 0.45))
                    .frame(width: 34, height: 34).background(BlotColor.inverse, in: Circle())
                    .frame(width: 44, height: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.isReplying && (!canSend || store.busy))
            .accessibilityLabel(store.t(store.isReplying ? "Stop reply" : "Send message"))
        }
    }
}
