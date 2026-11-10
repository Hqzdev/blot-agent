import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneGroupAvatar: View {
    let agents: [BlotV3.AgentProfile]
    let size: CGFloat
    var body: some View {
        ZStack {
            if agents.isEmpty {
                BlotIcon(.people, size: size * 0.55).foregroundStyle(WorkspaceStyle.secondary)
                    .frame(width: size, height: size).background(WorkspaceStyle.surface, in: Circle())
            } else if agents.count == 1, let agent = agents.first {
                WorkspaceAvatarView(agent: agent, size: size * 0.8).offset(x: -size * 0.08, y: -size * 0.08)
                BlotIcon(.people, size: size * 0.24).padding(size * 0.06)
                    .background(WorkspaceStyle.canvas, in: Circle()).offset(x: size * 0.28, y: size * 0.28)
            } else {
                let visible = Array(agents.prefix(agents.count > 4 ? 3 : 4))
                ForEach(Array(visible.enumerated()), id: \.element.metadata.id) { index, agent in
                    WorkspaceAvatarView(agent: agent, size: size * (agents.count == 2 ? 0.64 : 0.48))
                        .offset(offset(index))
                }
                if agents.count > 4 {
                    Text("+\(agents.count - 3)").font(.system(size: size * 0.18, weight: .semibold))
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .frame(width: size * 0.48, height: size * 0.48)
                        .background(WorkspaceStyle.surface, in: Circle()).offset(offset(3))
                }
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
    private func offset(_ index: Int) -> CGSize {
        if agents.count == 2 { return .init(width: size * (index == 0 ? -0.16 : 0.16), height: size * (index == 0 ? -0.16 : 0.16)) }
        if agents.count == 3 {
            return .init(width: index == 0 ? 0 : size * (index == 1 ? -0.24 : 0.24), height: size * (index == 0 ? -0.24 : 0.24))
        }
        return .init(width: size * (index % 2 == 0 ? -0.24 : 0.24), height: size * (index < 2 ? -0.24 : 0.24))
    }
}
