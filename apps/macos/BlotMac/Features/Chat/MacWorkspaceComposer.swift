import BlotAppleIntegrations
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
    @State private var showingSkills = false
    @State private var selection: TextSelection?
    @State private var dismissedSkillDraft: String?
    @State private var skillIndex = 0
    @FocusState private var focused: Bool
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true

    private let controlDiameter: CGFloat = 34

    private var canSend: Bool {
        !store.busy && (!store.form.composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.form.composer.attachments.isEmpty)
    }

    var body: some View {
        @Bindable var store = store
        GlassEffectContainer(spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                if let name = store.branchSourceName {
                    HStack(spacing: 7) {
                        BlotIcon(symbol: "arrow.triangle.branch", size: 14)
                        Text("Chat from \(name)").lineLimit(1)
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 14).padding(.top, 5).accessibilityIdentifier("workspace.chat.branch-source")
                }
                if let quoted = store.currentReplyTarget {
                    HStack(alignment: .top) {
                        WorkspaceQuotedMessage(message: quoted)
                        Button { store.form.composer.replyToMessageID = nil } label: { BlotIcon(.close, size: 12).blotHitArea() }
                            .buttonStyle(BlotHitTargetButtonStyle(expansion: 8)).accessibilityLabel(store.t("Cancel reply")).macHoverTip(store.t("Cancel reply"))
                    }.padding(.horizontal, 10).padding(.top, 4)
                }
                if !store.form.composer.attachments.isEmpty { attachments }
                VStack(alignment: .leading, spacing: 12) {
                    TextField(placeholder, text: $store.form.composer.draft, selection: $selection, axis: .vertical)
                        .font(.system(size: 16)).textFieldStyle(.plain).lineLimit(1...6)
                        .focused($focused).disabled(store.busy).accessibilityLabel(store.t("Message"))
                        .padding(.vertical, 7).onSubmit {
                            if let query = skillQuery {
                                let matches = matchingSkills(query)
                                if !matches.isEmpty { insertSkill(matches[min(skillIndex, matches.count - 1)].name, at: query) }
                                return
                            }
                            if !teamLayout || sendOnReturn { send() }
                            else { store.form.composer.draft += "\n" }
                        }
                        .onKeyPress(.return, phases: .down) { event in
                            guard event.modifiers.contains(.command) else { return .ignored }
                            send(); return .handled
                        }
                        .onKeyPress(.upArrow) { moveSkillSelection(by: -1) }
                        .onKeyPress(.downArrow) { moveSkillSelection(by: 1) }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(MacTeamMessageMotion.coordinateSpace)) } action: { onInputFrameChange?($0) }
                        .padding(.horizontal, 4)
                    HStack(spacing: 4) {
                        MacActionMenu(edge: .top) {
                            BlotIconButton(store.t("Skills"), symbol: "shippingbox") { showingSkills = true }
                            BlotIconButton(store.t("Attach files"), symbol: "paperclip") { importingFiles = true }
                            WorkspaceMenuGap()
                            BlotIconButton(store.t("AI models"), symbol: "cpu") { store.navigate(.models) }
                            BlotIconButton(store.t("Files"), symbol: "folder") { store.navigate(.files) }
                            BlotIconButton(store.t("Task details"), symbol: "list.bullet") { store.navigate(.running) }
                        } label: {
                            BlotIcon(symbol: "paperclip", size: 16).frame(width: controlDiameter, height: controlDiameter)
                                .background(WorkspaceStyle.ink.opacity(0.055), in: Circle())
                        }.macHoverTip(toolsTitle).accessibilityLabel(toolsTitle)
                        MacComposerAccessMenu(selection: $store.form.preferences.accessMode)
                        Spacer(minLength: 2)
                        MacComposerModelMenu()
                        Button {
                            if store.isReplying { store.stopReply() }
                            else if canSend { send() }
                            else if store.voice.isActive { store.voice.end() }
                            else { store.beginVoiceConversation() }
                        } label: {
                            Group {
                                if store.isReplying { BlotIcon(.stop, size: 15) }
                                else if store.busy { ProgressView().controlSize(.mini).tint(BlotColor.onInverse) }
                                else { BlotIcon(symbol: canSend ? "arrow.up" : (store.voice.isActive ? "mic.slash.fill" : "mic.fill"), size: 14) }
                            }.frame(width: controlDiameter, height: controlDiameter)
                                .foregroundStyle(BlotColor.onInverse).background(BlotColor.inverse, in: Circle()).blotHitArea()
                        }.buttonStyle(BlotHitTargetButtonStyle(hoverIn: Circle(), hoverColor: BlotColor.onInverse.opacity(0.1)))
                            .disabled(!store.isReplying && !store.voice.isActive && (store.busy || (!canSend && (store.mode != .live || store.selectedConversationID == nil || store.route != .chat))))
                            .macHoverTip(store.t(store.isReplying ? "Stop reply" : (canSend ? "Send message" : (store.voice.isActive ? "End voice conversation" : "Call agent"))))
                            .accessibilityLabel(store.t(store.isReplying ? "Stop reply" : (canSend ? "Send message" : (store.voice.isActive ? "End voice conversation" : "Call agent"))))
                    }
                }.padding(13)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 19))
                    .overlay { RoundedRectangle(cornerRadius: 19).strokeBorder(BlotColor.hairline).allowsHitTesting(false) }
                if let query = skillQuery {
                    MacComposerSkillSuggestions(matches: matchingSkills(query), selectedIndex: skillIndex, russian: russian,
                        select: { insertSkill($0, at: query) }, manage: { store.navigate(.skills) })
                } else if showsStarters {
                    MacChatStarters(examples: taskExamples, russian: russian, draft: $store.form.composer.draft) {
                        selection = TextSelection(insertionPoint: store.form.composer.draft.endIndex)
                        focused = true
                    }
                    .id(destinationChat?.metadata.id ?? destinationAgent?.metadata.id)
                    .disabled(store.busy)
                }

            }
        }
        .kAnimation(KMotion.standard, value: canSend)
        .kAnimation(KMotion.standard, value: store.isReplying)
        .kAnimation(KMotion.standard, value: store.form.composer.replyToMessageID)
        .kAnimation(KMotion.standard, value: store.form.composer.attachments)
        .workspacePanelSheet(isPresented: $showingSkills) { WorkspaceSkillQuickPicker().environment(store) }
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
        .onChange(of: skillQuery?.text) { skillIndex = 0 }
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
    private var toolsTitle: String { russian ? "Инструменты и вложения" : "Tools and attachments" }

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

    private func moveSkillSelection(by direction: Int) -> KeyPress.Result {
        guard let query = skillQuery else { return .ignored }
        let count = matchingSkills(query).count
        guard count > 0 else { return .ignored }
        skillIndex = (min(skillIndex, count - 1) + direction + count) % count
        return .handled
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
                        Button { store.form.composer.attachments.removeAll { $0 == url } } label: { BlotIcon(.close, size: 10).blotHitArea() }
                            .buttonStyle(BlotHitTargetButtonStyle(expansion: 7)).accessibilityLabel(store.t("Remove attachment")).macHoverTip(store.t("Remove attachment"))
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
