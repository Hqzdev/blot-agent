import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneAgentRow: View {
    let agent: BlotV3.AgentProfile
    var secondaryLines = 1
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            WorkspaceAvatarView(agent: agent, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.t(agent.name)).font(.body.weight(.medium))
                Text(store.t(agent.instructions)).font(.subheadline)
                    .foregroundStyle(WorkspaceStyle.secondary).lineLimit(secondaryLines)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, minHeight: 76, alignment: .leading).contentShape(Rectangle())
    }
}
