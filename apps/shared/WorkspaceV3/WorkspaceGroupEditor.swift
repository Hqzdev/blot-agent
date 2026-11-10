import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceGroupEditor: View {
    let conversationID: UUID?
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkspaceGroupDraft
    @State private var query = ""
    @State private var saveError: String?
    @FocusState private var nameFocused: Bool
    #if os(macOS)
    @Environment(\.macSheetSize) private var sheetSize
    #endif

    init(conversation: BlotV3.Conversation? = nil, participants: [BlotV3.ConversationParticipant] = []) {
        conversationID = conversation?.metadata.id
        let members = participants.filter { $0.conversationId == conversation?.metadata.id && $0.kind == .agent && !$0.removed }
        _draft = State(initialValue: WorkspaceGroupDraft(title: conversation?.title ?? "", selectedIDs: members.map(\.participantId),
            coordinatorID: conversation?.agentId, expectedVersion: conversation?.metadata.version))
    }

    private var agents: [BlotV3.AgentProfile] { store.snapshot.agents }
    private var selected: [BlotV3.AgentProfile] {
        draft.selectedIDs.compactMap { id in agents.first { $0.metadata.id == id } }
    }
    private var filtered: [BlotV3.AgentProfile] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return agents.filter { text.isEmpty || $0.name.localizedStandardContains(text) || $0.instructions.localizedStandardContains(text) }
    }
    private var availableIDs: Set<UUID> { Set(agents.map(\.metadata.id)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            #if os(macOS)
            Divider().opacity(0.5)
            if sheetSize.height < 560 {
                ScrollView { editorContent.frame(height: 420) }
            } else { editorContent }
            #else
            ScrollView { editorContent }.scrollDismissesKeyboard(.interactively)
            #endif
            Divider().opacity(0.5)
            footer
        }
        .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
        #if os(macOS)
        .frame(width: sheetSize.width, height: sheetSize.height)
        #else
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        #endif
        .onAppear {
            draft.reconcile(availableIDs: availableIDs)
            #if os(macOS)
            nameFocused = true
            #endif
        }
        .onChange(of: availableIDs) { _, ids in draft.reconcile(availableIDs: ids) }
        .interactiveDismissDisabled(store.busy)
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            nameField
            #if os(macOS)
            HStack(alignment: .top, spacing: 24) {
                agentPicker.frame(maxWidth: .infinity)
                selectionPanel.frame(width: 228)
            }
            #else
            selectionPanel
            agentPicker
            #endif
            if let saveError {
                Label(saveError, systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(pageInset).disabled(store.busy)
    }

    private var pageInset: CGFloat {
        #if os(iOS)
        PhonePageLayout.inset
        #else
        24
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(iOS)
        PhonePageLayout.sectionSpacing
        #else
        20
        #endif
    }

    private var controlSize: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private var header: some View {
        #if os(iOS)
        PhonePageHeader(title: store.t(conversationID == nil ? "New group" : "Group members"), back: { dismiss() })
            .disabled(store.busy)
        #else
        HStack(spacing: 14) {
            Image(systemName: "person.2.fill").font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t(conversationID == nil ? "New group" : "Group members"))
                    .font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Text(store.t("Choose the agents who will work together."))
                    .font(.callout).foregroundStyle(WorkspaceStyle.secondary)
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .frame(width: controlSize, height: controlSize).contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel(store.t("Close")).disabled(store.busy)
        }.padding(24)
        #endif
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(store.t("Group name")).font(.callout.weight(.semibold))
            TextField(store.t("For example, Product launch"), text: $draft.title)
                .textFieldStyle(.plain).font(.body).padding(13)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .focused($nameFocused).focusEffectDisabled()
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(WorkspaceStyle.ink.opacity(nameFocused ? 0.35 : 0.06)))
                .accessibilityLabel(store.t("Group name"))
        }
    }

    private var agentPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(WorkspaceStyle.secondary)
                TextField(store.t("Search agents"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: controlSize, height: controlSize)
                    }
                        .buttonStyle(.plain).foregroundStyle(WorkspaceStyle.secondary).accessibilityLabel(store.t("Clear search"))
                }
            }.padding(12).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text(store.t("Agents")).font(.callout.weight(.semibold))
                Text(filtered.count, format: .number).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                Spacer()
                Button(store.t("Select all")) { draft.selectAll(filtered.map(\.metadata.id)) }
                    .buttonStyle(.plain).font(.caption.weight(.medium))
                    .disabled(filtered.isEmpty || filtered.allSatisfy { draft.selectedIDs.contains($0.metadata.id) })
            }
            #if os(macOS)
            ScrollView { agentRows }.scrollIndicators(.hidden)
            #else
            agentRows
            #endif
        }.frame(maxHeight: .infinity, alignment: .top)
    }

    private var agentRows: some View {
        LazyVStack(spacing: 6) {
            ForEach(filtered, id: \.metadata.id) { agent in
                WorkspaceGroupAgentRow(agent: agent, selected: draft.selectedIDs.contains(agent.metadata.id)) {
                    draft.toggle(agent.metadata.id)
                }
            }
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: agents.isEmpty ? "person.2" : "magnifyingglass").font(.title2)
                    Text(store.t(agents.isEmpty ? "No agents yet" : "No agents found")).font(.body.weight(.medium))
                    Text(store.t(agents.isEmpty ? "Add agents to your team first." : "Try another name or clear the search."))
                        .font(.callout).multilineTextAlignment(.center)
                }.foregroundStyle(WorkspaceStyle.secondary).frame(maxWidth: .infinity).padding(.vertical, 36)
            }
        }
    }

    private var selectionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(store.t("Selected")).font(.callout.weight(.semibold))
                Text(selected.count, format: .number).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                Spacer()
                Button(store.t("Clear selection")) { draft.clear() }
                    .buttonStyle(.plain).font(.caption).disabled(selected.isEmpty)
            }
            #if os(macOS)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(selected, id: \.metadata.id) { agent in selectedRow(agent) }
                    if selected.isEmpty {
                        Text(store.t("Choose agents from the list.")).font(.callout)
                            .foregroundStyle(WorkspaceStyle.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }
                }
            }.scrollIndicators(.hidden)
            #else
            if !selected.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(selected, id: \.metadata.id) { agent in selectedRow(agent) }
                    }
                }.scrollIndicators(.hidden)
            }
            #endif
            if !selected.isEmpty { coordinatorPicker }
        }.padding(16).background(WorkspaceStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 18))
    }

    private func selectedRow(_ agent: BlotV3.AgentProfile) -> some View {
        HStack(spacing: 9) {
            WorkspaceAvatarView(agent: agent, size: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(agent.name).font(.callout.weight(.medium)).lineLimit(1)
                if draft.coordinatorID == agent.metadata.id {
                    Text(store.t("Coordinator")).font(.caption2).foregroundStyle(WorkspaceStyle.secondary)
                }
            }
            Spacer(minLength: 3)
            Button { draft.remove(agent.metadata.id) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: controlSize, height: controlSize).contentShape(Circle())
            }.buttonStyle(.plain).foregroundStyle(WorkspaceStyle.secondary)
                .accessibilityLabel(store.t("Remove participant") + ": " + agent.name)
        }
    }

    private var coordinatorPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(store.t("Coordinator")).font(.caption.weight(.medium)).foregroundStyle(WorkspaceStyle.secondary)
            Menu {
                ForEach(selected, id: \.metadata.id) { agent in
                    Button { draft.coordinate(with: agent.metadata.id) } label: {
                        if draft.coordinatorID == agent.metadata.id { Label(agent.name, systemImage: "checkmark") }
                        else { Text(agent.name) }
                    }
                }
            } label: {
                HStack {
                    Text(selected.first { $0.metadata.id == draft.coordinatorID }?.name ?? "").lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption2)
                }.font(.callout)
            }
            #if os(macOS)
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            #endif
                .padding(10).background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(store.t("Choose a coordinator"))
            Text(store.t("The coordinator leads the group's work."))
                .font(.caption).foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(iOS)
            footerHint
            #endif
            HStack(spacing: 12) {
                #if os(macOS)
                footerHint
                Spacer(minLength: 8)
                #endif
                Button(store.t("Cancel")) { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary))
                    .keyboardShortcut(.cancelAction).disabled(store.busy)
                Button(action: save) {
                    HStack(spacing: 8) {
                        if store.busy { ProgressView().controlSize(.small) }
                        Text(store.t(conversationID == nil ? "Create group" : "Save changes"))
                    }
                    #if os(iOS)
                    .frame(maxWidth: .infinity)
                    #endif
                }.buttonStyle(WorkspaceButtonStyle()).keyboardShortcut(.defaultAction)
                    .disabled(store.busy || !draft.canSave)
            }
        }.padding(.horizontal, pageInset).padding(.vertical, 18)
    }

    private var footerHint: some View {
        Text(store.t(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a group name"
            : selected.isEmpty ? "Select at least one agent" : "You can change the group members later."))
            .font(.caption).foregroundStyle(WorkspaceStyle.secondary)
    }

    private func save() {
        saveError = nil
        _Concurrency.Task {
            let success: Bool
            if let conversationID, let version = draft.expectedVersion {
                success = await store.updateGroup(conversationID, expectedVersion: version, title: draft.title,
                    agentIDs: draft.orderedAgentIDs)
            } else { success = await store.createGroup(title: draft.title, agentIDs: draft.orderedAgentIDs, commandID: draft.creationCommandID) }
            if success { dismiss() }
            else { saveError = store.error ?? store.t("Couldn't save the group.") }
        }
    }
}
