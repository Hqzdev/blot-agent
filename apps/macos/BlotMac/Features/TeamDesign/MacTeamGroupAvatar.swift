import BlotDesign
import SwiftUI

/// A group's identity comes from its members' current shapes, colors, and uploaded avatars.
struct MacTeamGroupAvatar: View {
    let agents: [MacTeamAgent]
    var size: CGFloat = 36

    private var radius: CGFloat { size * 0.27 }
    private var memberSize: CGFloat {
        guard agents.count > 1 else { return size }
        let spacing = 2 * radius * sin(.pi / Double(agents.count))
        return min(size * 0.58, spacing * 1.05)
    }

    var body: some View {
        ZStack {
            ForEach(Array(agents.enumerated()), id: \.element.id) { index, agent in
                MacTeamAvatar(agent: agent, size: memberSize)
                    .offset(position(for: index)).transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .kAnimation(KMotion.standard, value: agents.map(\.id))
        .accessibilityHidden(true)
    }

    private func position(for index: Int) -> CGSize {
        guard agents.count > 1 else { return .zero }
        let start = agents.count == 2 ? -3 * Double.pi / 4 : -Double.pi / 2
        let angle = start + 2 * .pi * Double(index) / Double(agents.count)
        return CGSize(width: radius * cos(angle), height: radius * sin(angle))
    }
}
