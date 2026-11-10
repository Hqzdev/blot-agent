import BlotDesign
import SwiftUI

struct MacTeamInspector: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        @Bindable var presentation = presentation
        VStack(spacing: 0) {
            HStack {
                WorkspaceLocalizedText(presentation.group == nil ? "Об агенте" : "О группе").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 16).frame(height: 52)
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 10) {
                        if let group = presentation.group {
                            MacTeamGroupAvatar(agents: presentation.members(of: group), size: 68)
                            Text(group.name).font(.system(size: 19, weight: .medium)).multilineTextAlignment(.center)
                            Text("Участников: \(group.agentIDs.count)").font(.system(size: 12)).foregroundStyle(
                                .secondary)
                        } else {
                            Button {
                                presentation.sheet = .editAgent
                            } label: {
                                MacTeamAvatar(agent: presentation.agent, size: 68)
                            }.buttonStyle(BlotPlainButtonStyle()).accessibilityLabel("Изменить аватар")
                            Text(presentation.agent.name).font(.system(size: 21, weight: .medium))
                            Text(presentation.agent.role).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }.padding(.top, 12)
                    MacTeamSegmentedControl(
                        title: "Раздел агента", options: ["Обзор", "Память", "Навыки"],
                        selection: $presentation.inspectorTab)
                    ZStack(alignment: .topLeading) {
                        Group {
                            switch presentation.inspectorTab {
                            case "Память": memories
                            case "Навыки": skills
                            default: overview
                            }
                        }.id(presentation.inspectorTab).transition(.opacity)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .kAnimation(KMotion.standard, value: presentation.inspectorTab)
                }.padding(18)
            }.scrollIndicators(.hidden)
        }.background(MacTeamStyle.sidebar)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let group = presentation.group {
                MacTeamParticipants(group: group)
            }
            Text("Демо-данные остаются на этом Mac. Действия в сервисах воспроизводятся локально.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Расписания").foregroundStyle(.secondary)
                    Spacer()
                    MacTeamIconButton(title: "Новое расписание", symbol: "plus") { presentation.sheet = .routine(nil) }
                }
                ForEach(
                    presentation.routines.filter {
                        $0.agentID == presentation.agent.id || presentation.group?.agentIDs.contains($0.agentID) == true
                    }
                ) { routine in
                    Button {
                        presentation.sheet = .routine(routine.id)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            BlotIcon(symbol: routine.enabled ? "clock.arrow.circlepath" : "pause.circle", size: BlotIconSize.control)
                                .foregroundStyle(WorkspaceStyle.ink)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(routine.title).font(.system(size: 12, weight: .medium))
                                WorkspaceLocalizedText(routine.enabled ? routine.schedule : "Приостановлено").font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            BlotIcon(symbol: "chevron.right", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                        }.contentShape(Rectangle())
                    }.buttonStyle(BlotPlainButtonStyle())
                }
                Button("Все расписания") { presentation.open(.library(.routines)) }.buttonStyle(BlotPlainButtonStyle()).foregroundStyle(WorkspaceStyle.ink)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Подключения").foregroundStyle(.secondary)
                ForEach(presentation.plugins.filter { !$0.accounts.isEmpty }.prefix(4)) { plugin in
                    Button {
                        presentation.sheet = .plugin(plugin)
                    } label: {
                        HStack(spacing: 9) {
                            MacTeamPluginIcon(plugin: plugin, size: 24)
                            Text(plugin.name)
                            Spacer()
                            Text("\(plugin.accounts.count)").foregroundStyle(.secondary)
                        }
                    }.buttonStyle(BlotPlainButtonStyle())
                }
                Button("Все приложения") { presentation.open(.library(.marketplace)) }.buttonStyle(BlotPlainButtonStyle())
                    .foregroundStyle(WorkspaceStyle.ink)
            }
            BlotIconButton("Файлы и документы", symbol: "folder", size: BlotIconSize.inline) { presentation.open(.library(.files)) }.buttonStyle(BlotPlainButtonStyle())
        }.font(.system(size: 12))
    }
    private var memories: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(presentation.relevantMemories) { memory in
                Button {
                    presentation.editMemory(memory.id)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(memory.text).font(.system(size: 12)).multilineTextAlignment(.leading)
                        MacTeamBadge(text: memory.agentID == nil ? "Общая память" : "Память агента")
                    }.frame(maxWidth: .infinity, alignment: .leading).teamCard(padding: 12)
                }.buttonStyle(BlotPlainButtonStyle())
            }
            BlotIconButton("Добавить воспоминание", symbol: "plus", size: BlotIconSize.inline) { presentation.editMemory() }.buttonStyle(BlotPlainButtonStyle())
            Button("Вся память") { presentation.open(.library(.memory)) }.buttonStyle(BlotPlainButtonStyle()).foregroundStyle(WorkspaceStyle.ink)
        }.font(.system(size: 12))
    }
    private var skills: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(presentation.relevantSkills) { skill in
                Button {
                    presentation.draft = "/" + skill.title
                    presentation.selectedSkill = true
                } label: {
                    HStack(spacing: 10) {
                        BlotIcon(symbol: "shippingbox", size: BlotIconSize.control).foregroundStyle(WorkspaceStyle.ink)
                        Text(skill.title).font(.system(size: 12)).multilineTextAlignment(.leading)
                        Spacer()
                        BlotIcon(symbol: "arrow.up.left", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                    }.teamCard(padding: 12)
                }.buttonStyle(BlotPlainButtonStyle())
                Button("Изменить «\(skill.title)»") { presentation.editSkill(skill.id) }.font(.system(size: 10))
                    .foregroundStyle(WorkspaceStyle.ink).buttonStyle(BlotPlainButtonStyle())
            }
            BlotIconButton("Новый навык", symbol: "plus", size: BlotIconSize.inline) { presentation.editSkill() }.buttonStyle(BlotPlainButtonStyle())
            Button("Все навыки") { presentation.open(.library(.skills)) }.buttonStyle(BlotPlainButtonStyle()).foregroundStyle(WorkspaceStyle.ink)
        }.font(.system(size: 12))
    }
}
