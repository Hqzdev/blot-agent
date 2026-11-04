import BlotDesign
import BlotDomain
import SwiftUI

struct MacSettingsUsagePane: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var tab = "Обзор"
    private var activity: MacSettingsActivity { MacSettingsActivity(snapshot: store.snapshot) }
    var body: some View {
        VStack(alignment: .leading, spacing: 42) {
            HStack(spacing: 4) {
                ForEach(["Обзор", "Аналитика"], id: \.self) { item in
                    Button { tab = item } label: {
                        Text(item).padding(.horizontal, 11).padding(.vertical, 7)
                            .foregroundStyle(tab == item ? WorkspaceStyle.ink : WorkspaceStyle.secondary)
                            .background(tab == item ? MacTeamSettingsStyle.card : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            if tab == "Обзор" {
                MacTeamSettingsSection(title: "Ваше пространство", detail: "Учёт использования моделей в этом аккаунте Blot.") {
                    MacTeamSettingsRow(title: store.accountDisplayName, detail: store.form.account.email) {
                        Text("Личное").foregroundStyle(.secondary)
                    }
                }
                MacTeamSettingsSection(title: "Использование моделей", detail: "Счётчики основаны на данных, возвращённых провайдером.") {
                    MacTeamSettingsRow(title: "Учтённые токены") { Text(activity.totalTokens, format: .number).monospacedDigit() }
                    Divider()
                    MacTeamSettingsRow(title: "Входящие", detail: "Инструкции, история и запросы к модели.") {
                        Text(activity.inputTokens, format: .number).foregroundStyle(.secondary)
                    }
                    Divider()
                    MacTeamSettingsRow(title: "Исходящие", detail: "Ответы модели.") {
                        Text(activity.outputTokens, format: .number).foregroundStyle(.secondary)
                    }
                }
                MacTeamSettingsSection(title: "Активность", detail: "Записанные обращения к модели за время работы пространства.") {
                    MacTeamSettingsRow(title: "Вызовов модели") { Text(activity.calls, format: .number).monospacedDigit() }
                    if activity.uncountedSteps > 0 {
                        Divider()
                        MacTeamSettingsRow(title: "Без данных о токенах", detail: "Точный расход для этих вызовов неизвестен.") {
                            Text(activity.uncountedSteps, format: .number).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                MacSettingsTokenHeatmap(dailyTokens: activity.dailyTokens)
                MacTeamSettingsSection(title: "По моделям") {
                    let models = Array(Set((store.snapshot.modelSteps ?? []).map(\.modelId))).sorted()
                    if models.isEmpty {
                        MacTeamSettingsRow(title: "Вызовов модели пока нет") { EmptyView() }
                    }
                    ForEach(models, id: \.self) { model in
                        let steps = (store.snapshot.modelSteps ?? []).filter { $0.modelId == model }
                        MacTeamSettingsRow(title: model, detail: "Вызовов: \(steps.count)") {
                            Text(steps.reduce(0) { $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0) }, format: .number)
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        if model != models.last { Divider() }
                    }
                }
            }
        }
    }
}
