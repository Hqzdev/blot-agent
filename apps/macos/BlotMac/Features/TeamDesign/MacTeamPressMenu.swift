import AppKit
import BlotDesign
import SwiftUI

/// One menu surface for holding a message or chat row, with optional secondary-click support.
struct MacTeamPressMenu<Actions: View>: ViewModifier {
    var secondaryClick = false
    var preservesTap = false
    let actions: (@escaping () -> Void) -> Actions
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @GestureState private var pressing = false
    @State private var expanded = false
    @State private var pressState = MacTeamPressState()

    func body(content: Content) -> some View {
        interactive(content)
            .environment(\.macTeamPressState, pressState)
            .scaleEffect(reduceMotion || systemReduceMotion ? 1 : expanded ? 1.025 : pressing ? 0.965 : 1)
            .animation(reduceMotion || systemReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.56), value: pressing)
            .animation(reduceMotion || systemReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.56), value: expanded)
            .accessibilityAction(named: Text("Открыть действия")) { open() }
            .overlay {
                if secondaryClick {
                    MacTeamPointerInput(onSecondaryClick: open)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
            }
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    actions { expanded = false }
                }
                .padding(6).frame(width: 264)
                .environment(\.macTeamPressState, nil)
                .foregroundStyle(WorkspaceStyle.ink)
                .teamControls()
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                .presentationBackground(.clear)
            }
            .onChange(of: expanded) { _, value in
                if !value { pressState.endMenu() }
            }
    }

    private var press: some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .updating($pressing) { value, state, _ in state = value }
    }

    @ViewBuilder private func interactive(_ content: Content) -> some View {
        if preservesTap {
            content.simultaneousGesture(press.onEnded { _ in open() })
        } else {
            content.highPriorityGesture(press.onEnded { _ in open() })
        }
    }

    private func open() {
        guard !expanded else { return }
        pressState.beginMenu()
        expanded = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
