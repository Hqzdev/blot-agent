import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceBranchAgentPicker: View {
    let messageID: UUID
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            WorkspacePanelFormHeader(title: "Branch in new agent") { Button(store.t("Close")) { dismiss() } }
            Text(ru ? "Выберите агента. В отдельный чат будет скопирован диалог до этого ответа. Разрешения инструментов останутся у выбранного агента." : "Choose an agent. The dialogue up to this response will be copied into a separate chat. The chosen agent keeps its own tool permissions.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                        Button {
                            _Concurrency.Task { if await store.branchConversation(from: messageID, to: agent.metadata.id) { dismiss() } }
                        } label: {
                            HStack(spacing: 12) {
                                WorkspaceAvatarView(agent: agent, size: 38)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agent.name).font(.body.weight(.medium))
                                    Text(agent.instructions).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(); BlotIcon(symbol: "arrow.up.right", size: 16).foregroundStyle(.secondary)
                            }.padding(12).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                                .background(WorkspaceStyle.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 18)).contentShape(RoundedRectangle(cornerRadius: 18))
                        }.buttonStyle(BlotPlainButtonStyle()).disabled(store.busy)
                            .accessibilityLabel("Branch to " + agent.name)
                    }
                }
            }
            if let error = store.error { Text(error).font(.callout).foregroundStyle(.red) }
        }.padding(22).frame(minWidth: 360, idealWidth: 440, maxWidth: 520, minHeight: 300, idealHeight: 460)
            .background(WorkspaceStyle.canvas).workspacePanelControls()
    }
}
