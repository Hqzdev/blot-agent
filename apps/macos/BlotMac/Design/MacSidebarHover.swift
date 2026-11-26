import BlotDesign
import SwiftUI

extension EnvironmentValues {
    @Entry var macSidebarTracksHover = false
}

extension View {
    func macSidebarHoverTarget() -> some View {
        anchorPreference(key: SidebarHoverBounds.self, value: .bounds) { [$0] }
    }

    func macSidebarHoverSection(radius: CGFloat) -> some View {
        modifier(SidebarHoverSection(radius: radius))
    }
}

private struct SidebarHoverBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct SidebarHoverSection: ViewModifier {
    let radius: CGFloat
    @State private var pointer: CGPoint?
    @Environment(\.controlActiveState) private var windowState

    func body(content: Content) -> some View {
        content
            .environment(\.macSidebarTracksHover, true)
            .overlayPreferenceValue(SidebarHoverBounds.self) { anchors in
                GeometryReader { geometry in
                    SidebarHoverHighlight(target: pointer.flatMap { point in
                        anchors.lazy.map { geometry[$0] }.first { $0.insetBy(dx: -1, dy: -1).contains(point) }
                    }, radius: radius)
                }.clipped().allowsHitTesting(false).accessibilityHidden(true)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: pointer = nil
                }
            }
            .onChange(of: windowState) { _, state in
                if state == .inactive { pointer = nil }
            }
            .transformPreference(SidebarHoverBounds.self) { $0.removeAll() }
    }
}

private struct SidebarHoverHighlight: View {
    let target: CGRect?
    let radius: CGFloat
    @Environment(\.blotReduceMotion) private var preference
    @Environment(\.accessibilityReduceMotion) private var system
    @State private var frame = CGRect.zero
    @State private var visible = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(BlotColor.hover)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(visible ? 1 : 0)
            .onChange(of: target, initial: true) { previous, next in
                let reduced = preference || system
                if let next {
                    let movement: Animation? = !reduced && previous != nil
                        ? .timingCurve(0.2, 0, 0, 1, duration: 0.07) : nil
                    withAnimation(movement) { frame = next }
                }
                withAnimation(reduced ? nil : .linear(duration: 0.04)) { visible = next != nil }
            }
    }
}
