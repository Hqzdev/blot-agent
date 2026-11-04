import BlotDesign
import SwiftUI

private enum MacTeamChatAction: CaseIterable {
    case open, profile, group, memory, skills, routine, files, notifications, unread

    var symbol: String {
        switch self {
        case .open: "bubble.left"
        case .profile: "slider.horizontal.3"
        case .group: "person.3"
        case .memory: "brain"
        case .skills: "shippingbox"
        case .routine: "clock.arrow.circlepath"
        case .files: "folder"
        case .notifications: "bell"
        case .unread: "envelope"
        }
    }

    @MainActor func title(for selection: MacTeamSelection, in presentation: MacTeamPresentation) -> String {
        switch self {
        case .open: return "Открыть чат"
        case .profile:
            if case .group = selection { return "Настроить группу" }
            return "Профиль агента"
        case .group: return "Добавить в группу"
        case .memory: return "Память"
        case .skills: return "Навыки"
        case .routine: return "Новое расписание"
        case .files: return "Файлы и документы"
        case .notifications:
            if case .agent(let id) = selection, presentation.agent(for: id).notifications { return "Выключить уведомления" }
            return "Включить уведомления"
        case .unread:
            if case .agent(let id) = selection, presentation.agent(for: id).unread { return "Отметить прочитанным" }
            return "Отметить непрочитанным"
        }
    }

    @MainActor func perform(for selection: MacTeamSelection, in presentation: MacTeamPresentation) {
        if self == .notifications || self == .unread {
            guard case .agent(let id) = selection else { return }
            var agent = presentation.agent(for: id)
            if self == .notifications { agent.notifications.toggle() } else { agent.unread.toggle() }
            presentation.demo.saveAgent(agent)
            return
        }
        presentation.open(selection)
        switch self {
        case .open: break
        case .profile:
            if case .group(let id) = selection { presentation.sheet = .group(id) }
            else { presentation.sheet = .editAgent }
        case .group: presentation.sheet = .group(nil)
        case .memory: presentation.inspectorTab = "Память"; presentation.inspectorVisible = true
        case .skills: presentation.inspectorTab = "Навыки"; presentation.inspectorVisible = true
        case .routine: presentation.sheet = .routine(nil)
        case .files: presentation.open(.library(.files))
        case .notifications, .unread: break
        }
    }

    static func available(for selection: MacTeamSelection) -> [Self] {
        if case .group = selection { return allCases.filter { ![.group, .notifications, .unread].contains($0) } }
        return allCases
    }
}

struct MacTeamChatMenu: View {
    let selection: MacTeamSelection
    let close: () -> Void
    @Environment(MacTeamPresentation.self) private var presentation

    var body: some View {
        ForEach(MacTeamChatAction.available(for: selection), id: \.self) { action in
            MacTeamNavigationButton {
                close()
                action.perform(for: selection, in: presentation)
            } label: {
                BlotLabel(action.title(for: selection, in: presentation), symbol: action.symbol, size: BlotIconSize.control)
                    .font(.system(size: 12))
            }
        }
    }
}

struct MacTeamChatContextActions: View {
    let selection: MacTeamSelection
    @Environment(MacTeamPresentation.self) private var presentation

    var body: some View {
        ForEach(MacTeamChatAction.available(for: selection), id: \.self) { action in
            Button(action.title(for: selection, in: presentation)) {
                action.perform(for: selection, in: presentation)
            }
        }
    }
}
