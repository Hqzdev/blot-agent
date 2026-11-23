import BlotDesign
import SwiftUI

/// Sweep inside the glyphs, leaving layout, hit testing and the accessible label stable.
struct MacChatActivityLabel: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .overlay {
                if !reduceMotion && !systemReduceMotion && scenePhase == .active {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { tick in
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            let band = max(20, width * 0.45)
                            let phase = tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.5)
                            LinearGradient(colors: [.clear, .primary.opacity(0.85), .clear],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: band)
                                .offset(x: width - (width + band) * min(phase, 1))
                        }
                    }
                    .mask { Text(title) }
                    .accessibilityHidden(true).allowsHitTesting(false)
                }
            }
    }
}
