import BlotDesign
import SwiftUI

struct WorkspaceTaskPlan: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        WorkspaceCard {
            VStack(alignment: .leading, spacing: spacing) {
                #if os(macOS)
                Text(store.t("Plan")).font(.system(size: 14, weight: .medium))
                #else
                Text(store.t("Plan")).font(.title2)
                #endif
                ForEach(Array(["Collect data from service websites", "Compare against your criteria", "Prepare report and email"].enumerated()), id: \.offset) { i, text in
                    HStack(alignment: .top, spacing: 16) { Text(String(format: "%02d", i + 1)).font(.caption.monospaced()).foregroundStyle(WorkspaceStyle.secondary); Text(store.t(text)) }
                }
                HStack { WorkspaceAvatar(color: WorkspaceAvatarView.color("purple"), size: 22); WorkspaceAvatar(size: 28); Text(store.t("CEO + Researcher · email shown before sending")).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
                HStack { WorkspaceV3ActionButton(title: "Start", action: .start, next: .running)
                    Button(store.t("Edit plan")) { store.form.composer.draft = store.t("Update the plan"); store.notice = "Describe the changes in the message field." }.buttonStyle(WorkspaceButtonStyle(.secondary)) }
            }
        }
    }
    private var spacing: CGFloat {
        #if os(macOS)
        12
        #else
        22
        #endif
    }
}
