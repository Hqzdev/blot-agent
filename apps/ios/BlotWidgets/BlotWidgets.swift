import SwiftUI
import WidgetKit

@main
struct BlotWidgets: WidgetBundle {
    var body: some Widget {
        BlotComposeWidget()
        BlotDecisionsWidget()
        BlotCurrentTaskWidget()
        BlotTeamWidget()
        BlotSchedulesWidget()
        BlotOverviewWidget()
    }
}

enum BlotWidgetKind: String {
    case compose, decisions, currentTask, team, schedules, overview
    var title: String {
        switch self {
        case .compose: "Новое поручение"
        case .decisions: "Твоё решение"
        case .currentTask: "Текущая задача"
        case .team: "Команда агентов"
        case .schedules: "Ближайшие запуски"
        case .overview: "Обзор работы"
        }
    }
    var summary: String {
        switch self {
        case .compose: "Начните новый чат с Blot одним касанием."
        case .decisions: "Задачи и действия, которым нужен ваш ответ."
        case .currentTask: "Вернитесь к текущей работе агента."
        case .team: "Ваши агенты и их последние состояния."
        case .schedules: "Следующие запуски ваших расписаний."
        case .overview: "Работа, решения и результаты в одном месте."
        }
    }
    var families: [WidgetFamily] {
        switch self {
        case .compose, .decisions: [.systemSmall]
        case .currentTask, .team, .schedules: [.systemMedium]
        case .overview: [.systemLarge]
        }
    }
}

@MainActor
private func configuration(_ kind: BlotWidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: "dev.blot.widgets." + kind.rawValue, provider: BlotWidgetProvider()) { entry in
        BlotWidgetView(kind: kind, entry: entry)
            .containerBackground(.background, for: .widget)
    }
    .configurationDisplayName(Text(kind.title))
    .description(Text(kind.summary))
    .supportedFamilies(kind.families)
}

struct BlotComposeWidget: Widget {
    var body: some WidgetConfiguration { configuration(.compose) }
}

struct BlotDecisionsWidget: Widget {
    var body: some WidgetConfiguration { configuration(.decisions) }
}

struct BlotCurrentTaskWidget: Widget {
    var body: some WidgetConfiguration { configuration(.currentTask) }
}

struct BlotTeamWidget: Widget {
    var body: some WidgetConfiguration { configuration(.team) }
}

struct BlotSchedulesWidget: Widget {
    var body: some WidgetConfiguration { configuration(.schedules) }
}

struct BlotOverviewWidget: Widget {
    var body: some WidgetConfiguration { configuration(.overview) }
}
