import AppKit
import BlotDesign
import SwiftUI

struct MacTeamSwipeToReply: ViewModifier {
    let onReply: () -> Void
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var swipe = MacTeamReplySwipeState()
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        content
            .offset(x: reduceMotion || systemReduceMotion ? 0 : swipe.offset)
            .background(alignment: .trailing) {
                BlotIcon(.reply, size: BlotIconSize.control)
                    .foregroundStyle(WorkspaceStyle.ink)
                    .frame(width: 32, height: 32)
                    .background(WorkspaceStyle.surface, in: Circle())
                    .scaleEffect(reduceMotion || systemReduceMotion ? 1 : 0.8 + swipe.progress * 0.2)
                    .opacity(swipe.progress).padding(.trailing, 8)
                    .accessibilityHidden(true)
            }
            .overlay {
                MacTeamPointerInput(onScroll: handleScroll)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .updating($dragging) { _, state, transaction in
                        state = true
                        transaction.animation = nil
                    }
                    .onChanged { update($0.translation) }
                    .onEnded {
                        update($0.translation)
                        finish(cancelled: false)
                    }
            )
            .onChange(of: dragging) { previous, current in
                if previous && !current && swipe.capturesGesture { finish(cancelled: true) }
            }
            .help("Два пальца вправо — ответить")
            .accessibilityAction(named: Text("Ответить")) { onReply() }
    }

    private func update(_ translation: CGSize) {
        if swipe.update(x: translation.width, y: translation.height) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func finish(cancelled: Bool) {
        var reply = false
        withKAnimation(reduceMotion || systemReduceMotion, .spring(response: 0.36, dampingFraction: 0.72)) {
            reply = swipe.finish(cancelled: cancelled)
        }
        if reply { onReply() }
    }

    private func handleScroll(_ input: MacTeamScrollInput) -> Bool {
        switch input {
        case .begin: swipe = MacTeamReplySwipeState()
        case .change(let translation): update(translation)
        case .end(let cancelled):
            let captured = swipe.capturesGesture
            finish(cancelled: cancelled)
            return captured
        }
        return swipe.capturesGesture
    }
}
