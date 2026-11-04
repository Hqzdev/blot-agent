import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneSearchView: View {
    private enum Scope: String, CaseIterable { case all = "All", chats = "Chats", agents = "Agents", files = "Files" }
    @Environment(WorkspaceStore.self) private var store
    @State private var scope = Scope.all
    @FocusState private var focused: Bool

    private var query: String { store.form.search.query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var conversations: [BlotV3.Conversation] {
        guard scope == .all || scope == .chats else { return [] }
        return store.snapshot.conversations.filter { conversation in
            matches(conversation.title) || store.snapshot.messages.contains { $0.conversationId == conversation.metadata.id && matches($0.content) }
        }
    }
    private var agents: [BlotV3.AgentProfile] {
        guard scope == .all || scope == .agents else { return [] }
        return store.snapshot.agents.filter { matches($0.name) || matches($0.instructions) }
    }
    private var artifacts: [BlotV3.Artifact] {
        guard scope == .all || scope == .files else { return [] }
        return store.snapshot.artifacts.filter { matches($0.name) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Scope.allCases, id: \.self) { item in
                            Button { scope = item } label: {
                                Text(store.t(item.rawValue)).font(.subheadline)
                                    .foregroundStyle(scope == item ? BlotColor.onInverse : WorkspaceStyle.ink)
                                    .padding(.horizontal, 16).frame(minHeight: 38)
                                    .background(scope == item ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(scope == item ? .isSelected : [])
                        }
                    }
                }.scrollIndicators(.hidden).padding(.bottom, 16)
                if !conversations.isEmpty {
                    sectionTitle("Chats")
                    ForEach(conversations, id: \.metadata.id) { conversation in
                        Button { focused = false; store.openConversation(conversation.metadata.id) } label: {
                            HStack(spacing: 14) {
                                BlotIcon(symbol: "bubble.left.and.bubble.right").font(.title3).frame(width: 48, height: 48)
                                Text(store.t(conversation.title)).font(.body.weight(.medium))
                                Spacer(minLength: 0)
                            }.frame(minHeight: 60).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if !agents.isEmpty {
                    sectionTitle("Agents")
                    ForEach(agents, id: \.metadata.id) { agent in
                        Button {
                            focused = false
                            _Concurrency.Task { await store.openAgentChat(agent.metadata.id) }
                        } label: { PhoneAgentRow(agent: agent) }.buttonStyle(.plain).disabled(store.busy)
                    }
                }
                if !artifacts.isEmpty {
                    sectionTitle("Files")
                    ForEach(artifacts, id: \.metadata.id) { artifact in
                        Button {
                            focused = false
                            store.selectedRecordID = artifact.metadata.id
                            store.navigate(.file)
                        } label: {
                            PhoneFileRow(file: artifact)
                        }.buttonStyle(.plain)
                    }
                }
                if conversations.isEmpty && agents.isEmpty && artifacts.isEmpty {
                    ContentUnavailableView {
                        BlotLabel(store.t("No results"), symbol: "magnifyingglass", size: 44)
                    } description: { Text(query) }
                        .padding(.top, 36)
                }
                WorkspaceFeedback()
            }.padding(.horizontal, 18).padding(.top, 72).padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) { header.padding(.horizontal, 18).padding(.top, 6) }
        .workspaceGlassContainer()
        .sensoryFeedback(.selection, trigger: scope)
        .task { focused = true }
    }

    private var header: some View {
        @Bindable var store = store
        return HStack(spacing: 10) {
            PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { focused = false; store.back() }
            HStack(spacing: 8) {
                BlotIcon(symbol: "magnifyingglass").foregroundStyle(WorkspaceStyle.secondary)
                TextField(store.t("Search chats, files and agents"), text: $store.form.search.query)
                    .textFieldStyle(.plain).font(.subheadline).autocorrectionDisabled()
                    .textInputAutocapitalization(.never).focused($focused)
                if !store.form.search.query.isEmpty {
                    Button { store.form.search.query = "" } label: {
                        BlotIcon(symbol: "xmark.circle.fill", size: 17).foregroundStyle(WorkspaceStyle.secondary)
                    }.buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
                }
            }.padding(.horizontal, 14).frame(minHeight: 44).glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query) || store.t(text).localizedCaseInsensitiveContains(query)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(store.t(title)).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
            .padding(.top, 12).padding(.bottom, 4).accessibilityAddTraits(.isHeader)
    }
}
