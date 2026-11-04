import BlotDesign
import SwiftUI

struct MacTeamSidebar: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    sectionTitle("Команда")
                    ForEach(presentation.agents) { agent in
                        let open = { presentation.open(.agent(agent.id)) }
                        MacTeamNavigationButton(selected: presentation.selection == .agent(agent.id), action: open) {
                            HStack(spacing: 10) {
                                MacTeamAvatar(agent: agent, size: 36)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(agent.name).font(.system(size: 13, weight: .medium))
                                    Text(agent.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if agent.unread {
                                    Circle().fill(WorkspaceStyle.ink).frame(width: 5, height: 5)
                                        .accessibilityLabel("Новое сообщение")
                                }
                            }
                        }
                        .modifier(MacTeamPressMenu(preservesTap: true) { close in MacTeamChatMenu(selection: .agent(agent.id), close: close) })
                        .contextMenu { MacTeamChatContextActions(selection: .agent(agent.id)) }
                    }
                    sectionTitle("Группы").padding(.top, 16)
                    ForEach(presentation.demo.state.groups) { group in
                        let open = { presentation.open(.group(group.id)) }
                        MacTeamNavigationButton(selected: presentation.selection == .group(group.id), action: open) {
                            HStack(spacing: 10) {
                                MacTeamGroupAvatar(agents: presentation.members(of: group))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(group.name).font(.system(size: 12, weight: .medium))
                                    Text(
                                        presentation.members(of: group).map(\.name).joined(separator: ", ")
                                    )
                                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        .modifier(MacTeamPressMenu(preservesTap: true) { close in MacTeamChatMenu(selection: .group(group.id), close: close) })
                        .contextMenu { MacTeamChatContextActions(selection: .group(group.id)) }
                    }

                }.kAnimation(KMotion.standard, value: presentation.agents.map(\.id))
                    .kAnimation(KMotion.standard, value: presentation.demo.state.groups.map(\.id))
                    .padding(.horizontal, 10).padding(.bottom, 16)
            }.scrollIndicators(.hidden)
            VStack(spacing: 6) {
                MacTeamNavigationButton(selected: presentation.selection == .library(.marketplace)) {
                    presentation.open(.library(.marketplace))
                } label: {
                    HStack(spacing: 10) {
                        BlotIcon(symbol: "square.grid.2x2", size: BlotIconSize.control).frame(width: 24)
                        Text("Приложения и шаблоны").lineLimit(1).minimumScaleFactor(0.85)
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(BlotPlainButtonStyle())
                Divider()
                MacTeamNavigationButton {
                    presentation.showSettings()
                } label: {
                    HStack(spacing: 10) {
                        Text("ЯФ").font(.system(size: 10, weight: .medium)).frame(width: 28, height: 28)
                            .background(.quaternary, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(presentation.settings.profileName).font(.system(size: 12, weight: .medium))
                            Text("Личное пространство").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(symbol: "gearshape", size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.ink)
                    }
                }
            }.font(.system(size: 12)).padding(.horizontal, 10).padding(.bottom, 12)
        }.background(MacTeamStyle.sidebar)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(WorkspaceStyle.secondary)
            .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}
