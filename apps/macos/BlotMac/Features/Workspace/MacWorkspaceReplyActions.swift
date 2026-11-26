import BlotDesign
import BlotDomain
import SwiftUI

struct MacWorkspaceReplyActions: View {
    let message: BlotV3.Message
    let isHovered: Bool
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var copied = false
    @FocusState private var focusedAction: String?

    private var ru: Bool { store.language == "ru" }
    private var visible: Bool { isHovered || focusedAction != nil }
    private var animate: Bool { !systemReduceMotion && !reduceMotion }

    var body: some View {
        HStack(spacing: 0) {
            action(ru ? "Копировать ответ" : "Copy response", symbol: copied ? "checkmark" : "doc.on.doc") {
                WorkspaceClipboard.copy(message.content); copied = true
            }
            action(ru ? "Нравится" : "Like", symbol: "hand.thumbsup", selected: reaction == "👍") { store.toggleReaction("👍", to: message.metadata.id) }
            action(ru ? "Не нравится" : "Dislike", symbol: "hand.thumbsdown", selected: reaction == "👎") { store.toggleReaction("👎", to: message.metadata.id) }
            action("Branch in new agent", symbol: "arrow.triangle.branch") { store.pendingBranchMessageID = message.metadata.id }
        }
        .padding(.leading, 12)
        .allowsHitTesting(visible)
        .accessibilityIdentifier("workspace.chat.reply-actions.\(message.metadata.id)")
        .task(id: copied) {
            guard copied else { return }
            do { try await _Concurrency.Task.sleep(for: .seconds(2)); copied = false } catch { }
        }
    }
    private var reaction: String? { store.chatInteractions.messages[message.metadata.id]?.reaction }
    private func action(_ title: String, symbol: String, selected: Bool = false, perform: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        return Button(action: perform) {
            BlotIcon(symbol: symbol, size: BlotIconSize.navigation)
                .foregroundStyle(selected ? WorkspaceStyle.ink : WorkspaceStyle.secondary)
                .frame(width: 34, height: 34)
                .background(selected ? WorkspaceStyle.ink.opacity(0.06) : .clear, in: shape)
                .opacity(visible ? 1 : 0)
                .offset(y: animate && !visible ? 2 : 0)
                .animation(animate ? .easeInOut(duration: 0.18) : nil, value: visible)
                .blotHitArea()
        }.buttonStyle(BlotPlainButtonStyle(hoverIn: shape)).help(title).accessibilityLabel(title)
            .focused($focusedAction, equals: title)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
