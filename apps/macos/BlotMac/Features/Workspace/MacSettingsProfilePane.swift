import BlotDesign
import BlotDomain
import SwiftUI

struct MacSettingsProfilePane: View {
    @Environment(WorkspaceStore.self) private var store
    private var activity: MacSettingsActivity { MacSettingsActivity(snapshot: store.snapshot) }
    var body: some View {
        VStack(spacing: 40) {
            VStack(spacing: 14) {
                Text(initials).font(.system(size: 34, weight: .regular)).foregroundStyle(.white)
                    .frame(width: 104, height: 104).background(Color(red: 0.91, green: 0.29, blue: 0.23), in: Circle())
                Text(store.accountDisplayName).font(.system(size: 25, weight: .medium))
                Text(store.form.account.email).font(.system(size: 13)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.top, 4)
            HStack(spacing: 0) {
                metric("Токенов всего", value: activity.totalTokens)
                Divider().frame(height: 36)
                metric("За один вызов", value: activity.peakTokens)
                Divider().frame(height: 36)
                metric("Вызовов модели", value: activity.calls)
                Divider().frame(height: 36)
                metric("Активных дней", value: activity.activeDays)
            }.padding(.vertical, 16).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MacTeamSettingsStyle.edge))
            WorkspaceAccountDeletionButton()
            VStack(alignment: .leading, spacing: 16) {
                Text("Ваша команда").font(.system(size: 14, weight: .medium))
                if store.snapshot.agents.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "person.2").font(.system(size: 30)).foregroundStyle(.secondary)
                        Text("Добавьте первого специалиста в команду").foregroundStyle(.secondary)
                        Button("Создать агента") { store.settingsRoute = nil; store.navigate(.createAgent) }
                            .buttonStyle(MacSettingsActionStyle())
                    }.frame(maxWidth: .infinity).padding(.vertical, 44)
                        .background(MacTeamSettingsStyle.card, in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                            Button {
                                store.settingsRoute = nil
                                store.selectAgent(agent.metadata.id, destination: .editAgent)
                            } label: {
                                VStack(spacing: 12) {
                                    WorkspaceAvatarView(agent: agent, size: 46)
                                    Text(agent.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                }.frame(maxWidth: .infinity).padding(.vertical, 24)
                                    .background(MacTeamSettingsStyle.card, in: RoundedRectangle(cornerRadius: 16))
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            MacSettingsTokenHeatmap(dailyTokens: activity.dailyTokens)
        }
    }
    private var initials: String {
        String(store.accountDisplayName.split(separator: " ").prefix(2).compactMap(\.first))
    }
    private func metric(_ title: String, value: Int) -> some View {
        VStack(spacing: 7) {
            Text(value, format: .number.notation(.compactName)).monospacedDigit()
            WorkspaceLocalizedText(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}

struct MacSettingsTokenHeatmap: View {
    let dailyTokens: [Date: Int]
    private var firstDay: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        return calendar.date(byAdding: .weekOfYear, value: -51, to: weekStart) ?? today
    }
    var body: some View {
        let start = firstDay
        let maximum = max(1, dailyTokens.values.max() ?? 1)
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Активность токенов").font(.system(size: 14, weight: .medium))
                Spacer()
                Text("Последние 12 месяцев").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(0..<52, id: \.self) { week in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { weekday in
                            let date = Calendar.current.date(byAdding: .day, value: week * 7 + weekday, to: start) ?? start
                            let count = dailyTokens[date, default: 0]
                            RoundedRectangle(cornerRadius: 3).fill(color(count, maximum: maximum)).aspectRatio(1, contentMode: .fit)
                                .help(date.formatted(date: .abbreviated, time: .omitted) + ": \(count) токенов")
                        }
                    }
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Активность токенов за последние 12 месяцев")
            HStack {
                Text(start.formatted(.dateTime.month(.abbreviated)))
                Spacer()
                Text(Date().formatted(.dateTime.month(.abbreviated)))
            }.font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
    private func color(_ count: Int, maximum: Int) -> Color {
        guard count > 0 else { return WorkspaceStyle.ink.opacity(0.1) }
        return MacTeamSettingsStyle.accent.opacity(0.28 + 0.72 * Double(count) / Double(maximum))
    }
}
