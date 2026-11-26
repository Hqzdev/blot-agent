import BlotAppleIntegrations
import BlotDesign
import SwiftUI

struct WorkspaceBrowserAgentPointer: View {
    let pointer: BrowserAgentPointer?
    @State private var visible = false
    @State private var position: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            if let pointer, let position, visible {
                BlotIcon(symbol: pointer.operation == "browser_type" ? "text.cursor" : "cursorarrow")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 1)
                    .padding(9).background(.purple.opacity(0.85), in: Circle())
                    .overlay { Circle().strokeBorder(.white, lineWidth: pointer.activated ? 2 : 0) }
                    .scaleEffect(pointer.activated && !systemReduceMotion && !reduceMotion ? 0.82 : 1)
                    .animation(systemReduceMotion || reduceMotion ? nil : KMotion.quick, value: pointer.activated)
                    .position(x: geometry.size.width * position.x, y: geometry.size.height * position.y)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: pointer?.id) {
            guard let pointer else { visible = false; return }
            let target = CGPoint(x: pointer.x, y: pointer.y)
            if systemReduceMotion || reduceMotion {
                position = target
                visible = true
            } else {
                if position == nil { position = CGPoint(x: max(0, pointer.x - 0.07), y: pointer.y) }
                visible = true
                await _Concurrency.Task.yield()
                guard !_Concurrency.Task.isCancelled else { return }
                withAnimation(KMotion.quick) { position = target }
            }
            do { try await _Concurrency.Task.sleep(for: .seconds(1.4)); visible = false } catch {}
        }
    }
}
