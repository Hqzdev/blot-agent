import BlotDesign
import SwiftUI

/// Sending starts at the actual composer; receiving unfolds from the lower leading edge.
nonisolated enum MacTeamMessageMotion {
    static let coordinateSpace = "team-message-conversation"
    static let send = Animation.spring(response: 0.38, dampingFraction: 0.86)
    static let receive = Animation.smooth(duration: 0.32)
    static let sendLead: Duration = .milliseconds(300)
    static let replySpacing: Duration = .milliseconds(180)
}

struct MacTeamMessageEntrance: ViewModifier {
    let outgoing: Bool
    let inputFrame: CGRect?
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var progress: CGFloat

    init(animated: Bool, outgoing: Bool, inputFrame: CGRect? = nil) {
        self.outgoing = outgoing
        self.inputFrame = inputFrame
        _progress = State(initialValue: animated ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .visualEffect { [inputFrame, outgoing, progress, reduceMotion] content, geometry in
                let target = geometry.frame(in: .named(MacTeamMessageMotion.coordinateSpace))
                let source = inputFrame ?? target
                let remaining = reduceMotion ? 0 : 1 - progress
                let x = outgoing ? source.minX + min(source.width, target.width) / 2 - target.midX : 0
                let y = outgoing ? source.midY - target.midY : 12
                return content
                    .scaleEffect(x: 1 - remaining * 0.06, y: 1 - remaining * 0.14,
                                 anchor: outgoing ? .bottomTrailing : .bottomLeading)
                    .offset(x: x * remaining, y: y * remaining)
                    .opacity(1 - Double(remaining) * (outgoing ? 0.35 : 1))
            }
            .onAppear {
                guard progress == 0 else { return }
                withKAnimation(reduceMotion, outgoing ? MacTeamMessageMotion.send : MacTeamMessageMotion.receive) {
                    progress = 1
                }
            }
    }
}
