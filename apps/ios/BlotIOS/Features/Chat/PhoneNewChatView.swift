import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneNewChatView: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text(store.t("Choose an agent")).font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader).padding(.bottom, 12)
                ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                    Button { _Concurrency.Task { await store.startNewChat(with: agent.metadata.id) } } label: {
                        PhoneAgentRow(agent: agent, secondaryLines: 2)
                    }.buttonStyle(.plain).disabled(store.busy)
                }
                if store.snapshot.agents.isEmpty {
                    Button(store.t("Create your first agent")) { store.beginAgentCreation() }
                        .buttonStyle(WorkspaceButtonStyle()).padding(.vertical, 16)
                }
                Divider().padding(.vertical, 16)
                Button { _Concurrency.Task { await store.startNewChat(with: nil) } } label: {
                    HStack(spacing: 14) {
                        BlotIcon(symbol: "bubble.left.and.bubble.right").font(.title2).frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(store.t("Just chat with AI")).font(.body.weight(.medium))
                            Text(store.t("A separate conversation without tools")).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 76).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(store.busy)
                WorkspaceFeedback()
            }.padding(.horizontal, 24).padding(.top, 82).padding(.bottom, 24)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) { store.back() }
                Text(store.t("New chat")).font(.headline)
                Spacer()
                PhoneGlassCircleButton(symbol: "plus", title: store.t("Create agent")) { store.beginAgentCreation() }
            }.padding(.horizontal, 18).padding(.top, 6)
        }.workspaceGlassContainer()
    }
}
