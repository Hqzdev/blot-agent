import BlotDesign
import SwiftUI

struct MacTeamParticipants: View {
    let group: MacDemoGroup
    @Environment(MacTeamPresentation.self) private var presentation
    private var members: [MacTeamAgent] { presentation.members(of: group) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Участники")
                Spacer()
                Text("\(members.count)").monospacedDigit()
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            VStack(spacing: 2) {
                ForEach(members) { agent in
                    MacTeamNavigationButton {
                        presentation.sheet = .agentProfile(agent.id)
                    } label: {
                        HStack(spacing: 10) {
                            MacTeamAvatar(agent: agent, size: 32)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(agent.name).font(.system(size: 12, weight: .medium))
                                Text(agent.role).font(.system(size: 11)).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            BlotIcon(.chevronRight, size: BlotIconSize.inline)
                        }
                    }.help("Профиль участника")
                        .accessibilityLabel("Профиль участника: \(agent.name), \(agent.role)")
                }
                if members.isEmpty {
                    Text("В группе пока нет участников.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(12)
                }
            }.teamCard(padding: 4)
        }
    }
}
