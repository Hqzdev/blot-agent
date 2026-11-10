import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneSearchView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        let results = PhoneSearchResults(snapshot: store.snapshot, query: query)
        VStack(spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if !results.agents.isEmpty {
                        sectionTitle("Agents")
                        ForEach(results.agents, id: \.metadata.id) { agent in
                            Button {
                                focused = false
                                _Concurrency.Task {
                                    await store.openAgentChat(agent.metadata.id)
                                    if store.error == nil { dismiss() }
                                }
                            } label: { PhoneAgentRow(agent: agent) }
                                .buttonStyle(.plain).disabled(store.busy)
                                .accessibilityIdentifier("workspace.search.agent.\(agent.metadata.id)")
                        }
                    }
                    if !results.groups.isEmpty {
                        sectionTitle("Groups")
                        ForEach(results.groups, id: \.metadata.id) { group in
                            Button {
                                focused = false
                                store.openConversation(group.metadata.id)
                                dismiss()
                            } label: { PhoneSearchGroupRow(group: group) }
                                .buttonStyle(.plain).disabled(store.busy)
                                .accessibilityIdentifier("workspace.search.group.\(group.metadata.id)")
                        }
                    }
                    if results.isEmpty {
                        ContentUnavailableView {
                            BlotLabel(store.t("No results"), symbol: "magnifyingglass", size: 36)
                        } description: { Text(store.t("Try another name or clear the search.")) }
                    }
                    WorkspaceFeedback()
                }.padding(.horizontal, 20).padding(.bottom, 24)
            }.scrollDismissesKeyboard(.interactively)
        }
        .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
        .workspaceGlassContainer()
        .accessibilityIdentifier("workspace.search.sheet")
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack {
                Text(store.t("Search")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                PhoneGlassCircleButton(symbol: "xmark", title: store.t("Close")) { focused = false; dismiss() }
                    .accessibilityIdentifier("workspace.search.close")
            }
            HStack(spacing: 8) {
                BlotIcon(.search, size: 20).foregroundStyle(WorkspaceStyle.secondary)
                TextField(store.t("Search agents and groups"), text: $query)
                    .textFieldStyle(.plain).font(.body).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).focused($focused)
                    .accessibilityIdentifier("workspace.search.query")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        BlotIcon(.closeCircle, size: 18).foregroundStyle(WorkspaceStyle.secondary)
                            .frame(width: 32, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
                }
            }.padding(.horizontal, 14).frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(store.t(title)).font(.subheadline.weight(.medium)).foregroundStyle(WorkspaceStyle.secondary)
            .padding(.top, 16).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
    }
}

private struct PhoneSearchGroupRow: View {
    let group: BlotV3.Conversation
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        let identity = PhoneConversationIdentity(conversation: group, agents: store.snapshot.agents, participants: store.snapshot.participants ?? [])
        HStack(spacing: 14) {
            PhoneGroupAvatar(agents: identity.members, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(group.title).font(.body.weight(.medium))
                Text(identity.members.map(\.name).joined(separator: ", "))
                    .font(.subheadline).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if group.archived { BlotIcon(.archiveBox, size: 16).foregroundStyle(WorkspaceStyle.secondary).accessibilityLabel(store.t("Archive")) }
        }.frame(minHeight: 76).contentShape(Rectangle())
    }
}
