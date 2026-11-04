import BlotDesign
import SwiftUI

struct WorkspaceReplyBubble: View {
    let draft: WorkspaceChatActivity.Draft
    var compact = false
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceTypingIndicator(size: compact ? 6 : 8, highlighted: true)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Color(white: 0.15), in: Capsule())
            Spacer(minLength: compact ? 54 : 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(store.t("Agent is thinking"))
        .id("thinking-" + draft.messageID.uuidString)
    }
}
