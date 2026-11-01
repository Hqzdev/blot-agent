import BlotDesign
import SwiftUI

struct SkeletonBlock: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var radius: CGFloat = K.rMd

    private var animated: Bool { !systemReduceMotion && !app.settings.reduceMotion && scenePhase == .active }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            GeometryReader { geometry in
                // Flat placeholder that gently pulses; no gradients.
                let phase = animated ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 : 0
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(K.text.opacity(0.05 + 0.035 * (1 - cos(phase * 2 * .pi)) / 2))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct SkeletonText: View {
    var lines = 3
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<lines, id: \.self) { index in
                    SkeletonBlock(radius: 4).frame(width: geometry.size.width * (index == lines - 1 ? 0.65 : 1), height: 12)
                }
            }
        }.frame(height: CGFloat(lines * 22 - 10))
    }
}

struct ContentSkeleton: View {
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: 28) {
                SkeletonBlock(radius: 6).frame(width: 220, height: 28)
                SkeletonText(lines: 2)
                SkeletonBlock().frame(height: 136)
                SkeletonText(lines: 4)
                SkeletonBlock().frame(height: 96)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading content")
    }
}

struct SidebarSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonBlock(radius: 6).frame(width: 120, height: 20)
                .padding(.horizontal, 16).frame(height: K.headerHeight)
            VStack(alignment: .leading, spacing: 18) {
                ForEach(0..<7) { index in
                    HStack(spacing: 10) {
                        SkeletonBlock(radius: 4).frame(width: 16, height: 16)
                        SkeletonBlock(radius: 4).frame(height: 12).padding(.trailing, index.isMultiple(of: 2) ? 24 : 54)
                    }
                }
            }.padding(16)
            Spacer()
        }.background(K.bgSidebar)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading sidebar")
    }
}

private struct LoadingTransition: ViewModifier {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let isLoading: Bool

    func body(content: Content) -> some View {
        content.animation(systemReduceMotion || app.settings.reduceMotion ? nil : KMotion.loading, value: isLoading)
    }
}

extension View {
    func loadingTransition(isLoading: Bool) -> some View {
        modifier(LoadingTransition(isLoading: isLoading))
    }
}
