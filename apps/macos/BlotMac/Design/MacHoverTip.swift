import SwiftUI

extension View {
    func macHoverTip(_ title: String) -> some View {
        modifier(MacHoverTipTarget(title: title))
    }

    func macHoverTipHost() -> some View {
        environment(\.hasMacHoverTipHost, true)
            .overlayPreferenceValue(MacHoverTipPreference.self) { tip in
                GeometryReader { geometry in
                    if let tip {
                        MacHoverTipLayout(target: geometry[tip.anchor]) {
                            Text(verbatim: tip.title)
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 11))
                                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                        }
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            .transformPreference(MacHoverTipPreference.self) { $0 = nil }
    }
}

private extension EnvironmentValues {
    @Entry var hasMacHoverTipHost = false
}

private struct MacHoverTipPreference: PreferenceKey {
    struct Tip {
        let title: String
        let anchor: Anchor<CGRect>
    }
    static var defaultValue: Tip? { nil }
    static func reduce(value: inout Tip?, nextValue: () -> Tip?) {
        if let next = nextValue() { value = next }
    }
}

private struct MacHoverTipTarget: ViewModifier {
    let title: String
    @Environment(\.hasMacHoverTipHost) private var hasHost
    @Environment(\.controlActiveState) private var windowState
    @State private var hovered = false
    @State private var ready = false

    func body(content: Content) -> some View {
        if hasHost {
            content
                .onHover { hovered = $0 }
                .onChange(of: windowState) { _, state in
                    if state == .inactive { hovered = false }
                }
                .task(id: hovered) {
                    ready = false
                    guard hovered else { return }
                    do { try await _Concurrency.Task.sleep(for: .milliseconds(420)) }
                    catch { return }
                    ready = true
                }
                .anchorPreference(key: MacHoverTipPreference.self, value: .bounds) {
                    hovered && ready ? .init(title: title, anchor: $0) : nil
                }
        } else {
            content.help(title)
        }
    }
}

/// Place the bubble above the control, flipping it below controls near the title bar.
private struct MacHoverTipLayout: Layout {
    let target: CGRect

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let bubble = subviews.first else { return }
        let margin: CGFloat = 6
        let maximum = min(320, max(1, bounds.width - 2 * margin))
        let size = bubble.sizeThatFits(ProposedViewSize(width: min(maximum, bubble.sizeThatFits(.unspecified).width), height: nil))
        let x = min(max(margin, target.midX - size.width / 2), bounds.width - margin - size.width)
        let above = target.minY - margin - size.height
        let y = above >= margin ? above : min(target.maxY + margin, bounds.height - margin - size.height)
        bubble.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + max(margin, y)),
                     anchor: .topLeading, proposal: ProposedViewSize(size))
    }
}
