import BlotWidgetSupport
import SwiftUI
import WidgetKit

struct BlotWidgetView: View {
    let kind: BlotWidgetKind
    let entry: BlotWidgetEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }
    var body: some View {
        Group {
            if entry.unavailable {
                BlotWidgetEmpty(title: snapshot.text("Не удалось обновить", "Update unavailable"),
                    detail: snapshot.text("Откройте Blot, чтобы загрузить данные.", "Open Blot to load your workspace."), symbol: "arrow.clockwise")
            } else if !snapshot.isSignedIn {
                BlotWidgetEmpty(title: snapshot.text("Твоя команда рядом", "Your team, at hand"),
                    detail: snapshot.text("Откройте Blot и войдите в аккаунт.", "Open Blot and sign in."), symbol: "person.crop.circle")
            } else {
                content
            }
        }
        .widgetURL(destination.url)
        .privacySensitive()
        .environment(\.locale, Locale(identifier: snapshot.language))
        .accessibilityElement(children: .contain)
    }
    private var destination: WidgetDestination {
        switch kind {
        case .compose: .compose
        case .decisions: entry.decisions.first.map { .conversation($0.conversationID) } ?? .overview
        case .currentTask: currentConversation.map { .conversation($0.id) } ?? .compose
        case .team: .agents
        case .schedules: .schedules
        case .overview: .overview
        }
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case .compose: compose
        case .decisions: decisions
        case .currentTask: currentTask
        case .team: team
        case .schedules: schedules
        case .overview: overview
        }
    }
    private var compose: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) { BlotWidgetAvatar(); Text("Blot").font(.subheadline.weight(.semibold)) }
            Spacer(minLength: 0)
            Text(snapshot.text("Новое\nпоручение", "New\nrequest")).font(.headline).lineLimit(2)
            Label(snapshot.text("Открыть чат", "Open chat"), systemImage: "arrow.up.right")
                .font(.caption).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var decisions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(entry.decisions.count, format: .number).font(.largeTitle.weight(.medium)).monospacedDigit().widgetAccentable()
                Spacer(minLength: 0)
                Image(systemName: "checkmark.shield").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Spacer(minLength: 0)
            Text(entry.decisions.isEmpty ? snapshot.text("Всё решено", "All clear") : snapshot.text("Нужно твоё решение", "Your decision needed"))
                .font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(entry.decisions.first?.title ?? snapshot.text("Новых запросов нет", "No pending requests"))
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
    }
    @ViewBuilder private var currentTask: some View {
        if let chat = currentConversation {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    BlotWidgetAvatar(agent: agent(chat.agentID), size: 24)
                    Text(agent(chat.agentID)?.name ?? "Blot").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    BlotWidgetState(state: chat.state, snapshot: snapshot)
                }
                Spacer(minLength: 0)
                Text(chat.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                freshness
            }
        } else {
            BlotWidgetEmpty(title: snapshot.text("Начнём с поручения", "Start a conversation"),
                detail: snapshot.text("Нажмите, чтобы открыть новый чат.", "Tap to open a new chat."), symbol: "bubble.left")
        }
    }
    private var team: some View {
        VStack(alignment: .leading, spacing: 10) {
            BlotWidgetHeading(title: snapshot.text("Твоя команда", "Your team"),
                detail: nil)
            Spacer(minLength: 0)
            if snapshot.agents.isEmpty {
                Text(snapshot.text("Добавьте первого агента в Blot.", "Add your first agent in Blot."))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(snapshot.agents.prefix(4)) { agent in
                        Link(destination: WidgetDestination.agent(agent.id).url) {
                            VStack(spacing: 5) {
                                BlotWidgetAvatar(agent: agent, size: 32)
                                Text(agent.name).font(.caption2.weight(.medium)).lineLimit(1)
                                BlotWidgetState(state: agent.state, snapshot: snapshot).labelStyle(.titleOnly)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }
            }
            freshness
        }
    }
    private var schedules: some View {
        VStack(alignment: .leading, spacing: 8) {
            BlotWidgetHeading(title: snapshot.text("Ближайшие запуски", "Upcoming runs"))
            if entry.schedules.isEmpty {
                Spacer(minLength: 0)
                Text(snapshot.text("Запусков пока нет", "No upcoming runs")).font(.subheadline.weight(.medium))
                Text(snapshot.text("Создайте расписание в Blot.", "Create a schedule in Blot."))
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(entry.schedules.prefix(2)) { schedule in
                    HStack(spacing: 8) {
                        Text(schedule.nextRun, format: .dateTime.hour().minute()).font(.subheadline.weight(.medium)).monospacedDigit()
                        BlotWidgetAvatar(agent: agent(schedule.agentID), size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.title).font(.caption.weight(.medium)).lineLimit(1)
                            Text(schedule.nextRun, format: .dateTime.day().month()).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
            freshness
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                BlotWidgetAvatar(size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.text("Твоё рабочее пространство", "Your workspace")).font(.subheadline.weight(.semibold)).lineLimit(1)
                    freshness
                }
            }
            HStack(spacing: 12) {
                metric(snapshot.runningCount, snapshot.text("В работе", "Working"))
                metric(entry.decisions.count, snapshot.text("Ждут тебя", "Need you"))
                metric(snapshot.completedCount, snapshot.text("Готово", "Done"))
            }.padding(.vertical, 4)
            Divider()
            ForEach(snapshot.conversations.prefix(3)) { chat in
                Link(destination: WidgetDestination.conversation(chat.id).url) {
                    HStack(spacing: 8) {
                        BlotWidgetAvatar(agent: agent(chat.agentID), size: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(chat.title).font(.caption.weight(.medium)).lineLimit(1)
                            BlotWidgetState(state: chat.state, snapshot: snapshot)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                    }
                }.buttonStyle(.plain)
            }
            if snapshot.conversations.isEmpty {
                Text(snapshot.text("Новые поручения появятся здесь.", "Your conversations will appear here."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Label(snapshot.text("Открыть Blot", "Open Blot"), systemImage: "arrow.up.right")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func metric(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(count, format: .number).font(.title.weight(.medium)).monospacedDigit().widgetAccentable()
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var freshness: some View {
        HStack(spacing: 3) {
            if entry.isStale { Image(systemName: "arrow.clockwise") }
            Text(snapshot.text("Данные на", "Updated"))
            Text(snapshot.updatedAt, style: .time)
        }.font(.caption2).foregroundStyle(.secondary).lineLimit(1)
    }
    private var currentConversation: WidgetConversation? {
        snapshot.conversations.first { $0.state == .running } ?? snapshot.conversations.first
    }
    private func agent(_ id: UUID?) -> WidgetAgent? { snapshot.agents.first { $0.id == id } }
}
