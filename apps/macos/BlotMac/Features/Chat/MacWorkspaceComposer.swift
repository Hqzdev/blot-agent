import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI
import UniformTypeIdentifiers

struct MacWorkspaceComposer: View {
    var teamLayout = false
    var showsStarters = false
    var onInputFrameChange: ((CGRect) -> Void)? = nil
    var onSend: (() -> Void)? = nil
    @Environment(WorkspaceStore.self) private var store
    @State private var importingFiles = false
    @State private var selection: TextSelection?
    @State private var dismissedSkillDraft: String?
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
                MacActionMenu(edge: .top) {
                    BlotIconButton(store.t("Skills"), symbol: "shippingbox") { store.navigate(.skills) }
                    BlotIconButton(store.t("Attach files"), symbol: "paperclip") { importingFiles = true }
                    WorkspaceMenuGap()
                    MacComposerAccessMenu(selection: $store.form.preferences.accessMode)
                    WorkspaceMenuGap()
                    BlotIconButton(store.t("AI models"), symbol: "cpu") { store.navigate(.models) }
                    BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                    BlotIconButton(store.t("Task details"), symbol: "list.bullet") { store.navigate(.running) }
                } label: {
                    BlotIcon(.plus, size: 17).frame(width: 30, height: 30)
                        .foregroundStyle(WorkspaceStyle.ink).background(WorkspaceStyle.surface, in: Circle())
                }
                    .help(store.t("Add attachment")).accessibilityLabel(store.t("Add attachment"))
                TextField(placeholder, text: $store.form.composer.draft, selection: $selection, axis: .vertical)
                    .font(.system(size: 13)).textFieldStyle(.plain).lineLimit(1...6)
                    .focused($focused).disabled(store.busy).accessibilityLabel(store.t("Message"))
                    .padding(.vertical, 7).onSubmit {
                        if let query = skillQuery {
                            if let skill = matchingSkills(query).first { insertSkill(skill.name, at: query) }
                            return
                        }
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
                        else { BlotIcon(.arrowUp, size: 15) }
                    }.frame(width: 30, height: 30)
                        .foregroundStyle(BlotColor.onInverse).background(BlotColor.inverse, in: Circle())
                }.buttonStyle(.plain)
                    .help(store.t(store.isReplying ? "Stop reply" : "Send message"))
                    .accessibilityLabel(store.t(store.isReplying ? "Stop reply" : "Send message"))
            }.padding(teamLayout ? 10 : 5)
                .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 23))
                .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(MacWorkspaceStyle.edge))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
            if let query = skillQuery {
                MacComposerSkillSuggestions(matches: matchingSkills(query), russian: russian,
                    select: { insertSkill($0, at: query) }, manage: { store.navigate(.skills) })
            } else if showsStarters {
                MacChatStarters(examples: taskExamples, russian: russian, draft: $store.form.composer.draft) {
                    selection = TextSelection(insertionPoint: store.form.composer.draft.endIndex)
                    focused = true
                }
                .id(destinationChat?.metadata.id ?? destinationAgent?.metadata.id)
                .disabled(store.busy)
            } else if teamLayout && composerHints {
                Text(store.currentConversation?.kind == .group ? "Задайте общую задачу — команда распределит работу по ролям" : "Прикрепите файл или задайте агенту задачу сообщением")
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
        .onChange(of: store.form.composer.draft) { _, draft in
            if dismissedSkillDraft != draft { dismissedSkillDraft = nil }
        }
        .onKeyPress(.escape) {
            guard skillQuery != nil else { return .ignored }
            dismissedSkillDraft = store.form.composer.draft
            return .handled
        }
        .onChange(of: store.replyFocusRequest) { _, _ in focused = true }
    }

    private var destinationChat: BlotV3.Conversation? {
        [.home, .newChat].contains(store.route) ? nil : store.currentConversation
    }

    private var destinationAgent: BlotV3.AgentProfile? {
        let agents = store.snapshot.agents
        if let chat = destinationChat { return agents.first { $0.metadata.id == chat.agentId } }
        if let id = store.selectedAgentID { return agents.first { $0.metadata.id == id } }
        return agents.first
    }

    private var taskExamples: [MacChatTaskExample] {
        let agent = destinationAgent
        let ids = Set((store.snapshot.skillAssignments ?? []).filter { $0.assigned && $0.agentID == agent?.metadata.id }.map(\.skillID))
        let names = (store.snapshot.skills ?? []).filter { !$0.archived && ids.contains($0.metadata.id) }.map(\.name)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return MacChatTaskExample.suggestions(for: agent, skills: names, group: destinationChat?.kind == .group, russian: store.language == "ru")
    }

    private var russian: Bool { store.language == "ru" }

    private var placeholder: String {
        russian ? "Опишите задачу или введите @ для скиллов" : "Describe a task or type @ for skills"
    }

    private var skillQuery: MacComposerSkillQuery? {
        guard dismissedSkillDraft != store.form.composer.draft else { return nil }
        return MacComposerSkillQuery(draft: store.form.composer.draft, selection: selection)
    }

    private func matchingSkills(_ query: MacComposerSkillQuery) -> [BlotV3.Skill] {
        (store.snapshot.skills ?? []).filter { !$0.archived && (query.text.isEmpty || $0.name.localizedCaseInsensitiveContains(query.text)) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func insertSkill(_ name: String, at query: MacComposerSkillQuery) {
        var draft = store.form.composer.draft
        let needsSpace = draft[query.range.upperBound...].first?.isWhitespace != true
        let insertion = "@" + name + (needsSpace ? " " : "")
        let offset = draft.distance(from: draft.startIndex, to: query.range.lowerBound) + insertion.count
        draft.replaceSubrange(query.range, with: insertion)
        store.form.composer.draft = draft
        selection = TextSelection(insertionPoint: draft.index(draft.startIndex, offsetBy: offset))
        dismissedSkillDraft = draft
        focused = true
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
