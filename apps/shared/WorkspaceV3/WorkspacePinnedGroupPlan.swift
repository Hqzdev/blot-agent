import BlotDomain
import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspacePinnedGroupPlan: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        if let id = store.selectedConversationID.flatMap({ store.chatContent.pinnedPlans[$0] }),
           let plan = store.message(id) {
            Button { store.messageNavigationTarget = id } label: {
                HStack(spacing: 10) {
                    BlotIcon(.pin, size: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        WorkspaceLocalizedText(store.language == "ru" ? "План работы" : "Work plan").font(.caption.weight(.semibold))
                        if let progress = store.groupPlan(for: plan) {
                            Text("\(progress.completedCount)/\(progress.steps.count) · " + (progress.steps.first { !$0.completed }?.task ?? (store.language == "ru" ? "Все пункты выполнены" : "All steps completed")))
                                .font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                        } else {
                            Text(plan.content).font(.caption).lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    BlotIcon(.chevronRight, size: 12)
                }.padding(12).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain).accessibilityIdentifier("workspace.chat.pinned-plan")
        }
    }
}
