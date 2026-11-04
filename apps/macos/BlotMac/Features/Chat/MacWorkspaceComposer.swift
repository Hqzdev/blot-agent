import BlotDesign
import BlotDomain
import SwiftUI
import UniformTypeIdentifiers

struct MacWorkspaceComposer: View {
    var teamLayout = false
    var onInputFrameChange: ((CGRect) -> Void)? = nil
    var onSend: (() -> Void)? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var importingFiles = false
    @FocusState private var focused: Bool
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true
    @AppStorage(MacTeamPreferenceKey.composerHints) private var composerHints = true

    private var canSend: Bool {
        !store.busy && (!store.form.composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.form.composer.attachments.isEmpty)
    }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 8) {
            if let quoted = store.currentReplyTarget {
                HStack(alignment: .top) {
                    WorkspaceQuotedMessage(message: quoted)
                    Button { store.form.composer.replyToMessageID = nil } label: { BlotIcon(.close, size: 12) }
                        .buttonStyle(.plain).accessibilityLabel(store.t("Cancel reply"))
                }.padding(.horizontal, 10).padding(.top, 4)
            }
            if !store.form.composer.attachments.isEmpty { attachments }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    BlotIconButton(store.t("Attach files"), symbol: "paperclip") { importingFiles = true }
                    Divider()
                    Picker(store.t("Access mode"), selection: $store.form.preferences.accessMode) {
                        Text(store.t("Observe")).tag(BlotV3.AccessMode.observe)
                        Text(store.t("Ask first")).tag(BlotV3.AccessMode.ask_first)
                        Text(store.t("Trusted scope")).tag(BlotV3.AccessMode.trusted_scope)
                    }
                    BlotIconButton(store.t("AI models"), symbol: "cpu") { store.navigate(.models) }
                    BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                } label: {
                    BlotIcon(.plus, size: 17).foregroundStyle(WorkspaceStyle.secondary)
                        .frame(width: 30, height: 30).background(WorkspaceStyle.surface, in: Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help(store.t("Add attachment")).accessibilityLabel(store.t("Add attachment"))
                TextField(placeholder, text: $store.form.composer.draft, axis: .vertical)
                    .font(.system(size: 13)).textFieldStyle(.plain).lineLimit(1...6)
                    .focused($focused).disabled(store.busy).accessibilityLabel(store.t("Message"))
                    .padding(.vertical, 7).onSubmit {
                        if !teamLayout || sendOnReturn { send() }
                        else { store.form.composer.draft += "\n" }
                    }
                    .onKeyPress(.return, phases: .down) { event in
                        guard event.modifiers.contains(.command) else { return .ignored }
                        send(); return .handled
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MacTeamMessageMotion.coordinateSpace)) } action: { onInputFrameChange?($0) }
                Button { if store.isReplying { store.stopReply() } else { send() } } label: {
                    Group {
                        if store.isReplying { BlotIcon(.stop, size: 15) }
                        else if store.busy { ProgressView().controlSize(.mini).tint(BlotColor.onInverse) }
                        else { BlotIcon(teamLayout || canSend ? .arrowUp : .microphoneOff, size: 15) }
                    }.frame(width: 30, height: 30)
                        .foregroundStyle(BlotColor.onInverse).background(BlotColor.inverse, in: Circle())
                }.buttonStyle(.plain).disabled(!canSend && !store.isReplying).opacity(canSend || store.isReplying ? 1 : 0.45)
                    .help(store.t(store.isReplying ? "Stop reply" : canSend ? "Send message" : "Voice is planned for a later release."))
                    .accessibilityLabel(store.t(store.isReplying ? "Stop reply" : canSend ? "Send message" : "Voice is planned for a later release."))
            }.padding(teamLayout ? 10 : 5)
                .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 23))
                .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(MacWorkspaceStyle.edge))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            if teamLayout && composerHints {
                Text("Прикрепите файл или задайте агенту задачу сообщением")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 14)
            }
        }
        .kAnimation(KMotion.standard, value: store.form.composer.replyToMessageID)
        .kAnimation(KMotion.standard, value: store.form.composer.attachments)
        .kAnimation(KMotion.standard, value: composerHints)
        .fileImporter(isPresented: $importingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                for url in urls where !store.form.composer.attachments.contains(url) { store.form.composer.attachments.append(url) }
            case .failure(let error): store.error = error.localizedDescription
            }
        }
        .task { focused = true }
        .onChange(of: store.replyFocusRequest) { _, _ in focused = true }
    }

    private var placeholder: String {
        let id = store.route == .home ? store.selectedAgentID : store.currentConversation?.agentId
        let name = store.snapshot.agents.first { $0.metadata.id == id }?.name ?? "Blot Agent"
        return store.t("Message agent") + " " + name
    }

    private var attachments: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(store.form.composer.attachments, id: \.self) { url in
                    HStack(spacing: 6) {
                        BlotIcon(.document, size: 12)
                        Text(url.lastPathComponent).lineLimit(1)
                        Button { store.form.composer.attachments.removeAll { $0 == url } } label: { BlotIcon(.close, size: 10) }
                            .buttonStyle(.plain).accessibilityLabel(store.t("Remove attachment"))
                    }.font(MacWorkspaceStyle.caption).padding(.horizontal, 8).padding(.vertical, 6)
                        .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.scrollIndicators(.hidden)
    }

    private func send() {
        guard canSend else { return }
        onSend?()
        _Concurrency.Task { await store.sendDesktopMessage() }
    }
}
