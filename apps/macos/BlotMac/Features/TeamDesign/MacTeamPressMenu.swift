import AppKit
import BlotDesign
import SwiftUI

/// One menu surface for holding a message or chat row, with optional secondary-click support.
struct MacTeamPressMenu<Actions: View>: ViewModifier {
    enum Surface { case message, sidebar }

    var secondaryClick = false
    var preservesTap = false
    var surface: Surface = .message
    let actions: (@escaping () -> Void) -> Actions
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.locale) private var locale
    @GestureState private var pressing = false
    @State private var expanded = false
    @State private var pressState = MacTeamPressState()

    func body(content: Content) -> some View {
        interactive(content)
            .environment(\.macTeamPressState, pressState)
            .scaleEffect(reduceMotion || systemReduceMotion ? 1 : expanded ? 1.01 : pressing ? 0.985 : 1)
            .animation(reduceMotion || systemReduceMotion ? nil : BlotInterfaceMotion.standard, value: pressing)
            .animation(reduceMotion || systemReduceMotion ? nil : BlotInterfaceMotion.standard, value: expanded)
            .accessibilityAction(named: Text(locale.language.languageCode?.identifier == "ru" ? "Открыть действия" : "Open actions")) { open() }
            .overlay {
                if secondaryClick {
                    MacTeamPointerInput(onSecondaryClick: open, restrictSecondaryClickToConversation: surface == .message)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).allowsHitTesting(false)
                }
            }
            .popover(isPresented: $expanded, arrowEdge: .bottom) {
                MacActionMenuPanel {
                    actions { expanded = false }
                }
                .environment(\.macTeamPressState, nil)
                .onExitCommand { expanded = false }
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
