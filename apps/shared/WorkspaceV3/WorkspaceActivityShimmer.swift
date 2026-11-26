import BlotDesign
import SwiftUI

/// Only the active action owns a repeating animation; completed history stays static.
struct WorkspaceActivityShimmer: ViewModifier {
    let active: Bool
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    @ViewBuilder func body(content: Content) -> some View {
        if active && !reduceMotion && !systemReduceMotion {
            content.phaseAnimator([false, true]) { label, phase in
                label.overlay {
                    GeometryReader { geometry in
                        LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: max(28, geometry.size.width * 0.45))
                            .offset(x: phase ? geometry.size.width : -max(28, geometry.size.width * 0.45))
                    }.mask(content).allowsHitTesting(false).accessibilityHidden(true)
                }
            } animation: { _ in .linear(duration: 1.4) }
        } else { content }
    }
}
