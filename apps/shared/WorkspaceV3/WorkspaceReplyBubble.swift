import BlotDesign
import SwiftUI

struct WorkspaceReplyBubble: View {
    let draft: WorkspaceChatActivity.Draft
    var compact = false
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceTypingIndicator(size: compact ? 4 : 6)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 26))
            Spacer(minLength: compact ? 54 : 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.t("Agent is typing"))
        .id(draft.messageID)
    }
}
