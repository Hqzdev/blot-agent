import BlotDesign
import SwiftUI

struct MacTeamPersonalSettingsContent: View {
    let pane: MacTeamSettingsPane
    @Environment(MacTeamPresentation.self) private var optionalPresentation: MacTeamPresentation?
    private var presentation: MacTeamPresentation {
        guard let optionalPresentation else { preconditionFailure("Account-specific panes require their presentation") }
        return optionalPresentation
    }
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .light
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @AppStorage(MacTeamPreferenceKey.sendOnReturn) private var sendOnReturn = true
    @AppStorage(MacTeamPreferenceKey.composerHints) private var composerHints = true
    @AppStorage(MacTeamPreferenceKey.compactMessages) private var compactMessages = false
    @AppStorage(MacTeamPreferenceKey.defaultRole) private var defaultRole = "Ассистент"
    @AppStorage(MacTeamPreferenceKey.defaultInstructions) private var defaultInstructions = ""

    @ViewBuilder var body: some View {
        switch pane {
        case .general: general
        case .notifications: notifications
        case .profile: profile
        case .appearance: appearance
        case .account: account
        case .personalization: personalization
        case .shortcuts: shortcuts
        case .usage: usage
        default: EmptyView()
        }
    }

    @ViewBuilder private var general: some View {
        @Bindable var presentation = presentation
        MacTeamSettingsSection(title: "Рабочее пространство") {
            MacTeamSettingsRow(title: "Хранение данных", detail: "Переписки, документы и настройки команды сохраняются на этом Mac.") {
                MacTeamBadge(text: "Локально")
            }
            Divider()
            MacTeamSettingsRow(title: "Режим работы", detail: "Действия в подключённых сервисах воспроизводятся на демо-данных.") {
                MacTeamBadge(text: "Демо")
            }
        }
        MacTeamSettingsSection(title: "Общие") {
            MacTeamSettingsRow(title: "Язык", detail: "Предпочтительный язык пространства и формат дат.") {
                MacTeamSelect(title: "Язык", selection: $presentation.settings.language,
                              values: ["Русский", "English"], showsTitle: false)
            }
            Divider()
            MacTeamSettingsToggle(title: "Открывать при входе в систему",
                                  detail: "В демо сохраняется как предпочтение запуска.", isOn: $presentation.settings.launchAtLogin)
        }
        MacTeamSettingsSection(title: "Сообщения") {
            MacTeamSettingsToggle(title: "Отправлять по Enter",
                                  detail: "Если выключено, Enter переносит строку. ⌘Enter всегда отправляет сообщение.", isOn: $sendOnReturn)
            Divider()
            MacTeamSettingsToggle(title: "Подсказки под полем ввода",
                                  detail: "Напоминать о навыках, файлах и расписаниях.", isOn: $composerHints)
        }
    }

    @ViewBuilder private var appearance: some View {
        MacTeamSettingsSection(title: "Тема") {
            MacTeamSettingsRow(title: "Оформление", detail: "Системная тема меняется вместе с оформлением macOS.") {
                MacTeamSelect(title: "Тема", selection: $theme,
                              options: [.init("Системная", .system), .init("Светлая", .light), .init("Тёмная", .dark)],
                              showsTitle: false)
            }
        }
        MacTeamSettingsSection(title: "Интерфейс") {
            MacTeamSettingsToggle(title: "Компактные сообщения",
                                  detail: "Меньше расстояние между сообщениями и отступы внутри пузырей.", isOn: $compactMessages)
        }
        MacTeamSettingsSection(title: "Движение") {
            MacTeamSettingsToggle(title: "Уменьшить движение",
                                  detail: "Убирает перемещения панелей и анимации сообщений. Системная настройка тоже учитывается.", isOn: $reduceMotion)
        }
    }

    @ViewBuilder private var notifications: some View {
        @Bindable var presentation = presentation
        MacTeamSettingsSection(title: "События команды") {
            MacTeamSettingsToggle(title: "Работа готова или требуется решение",
                                  detail: "Общее предпочтение уведомлений для пространства.", isOn: $presentation.settings.notifications)
        }
        MacTeamSettingsSection(title: "Агенты") {
            ForEach(presentation.agents) { agent in
                MacTeamSettingsRow(title: agent.name, detail: agent.role) {
                    Toggle("Уведомления: " + agent.name, isOn: Binding(
                        get: { agent.notifications },
                        set: { value in
                            var updated = presentation.agent(for: agent.id)
                            updated.notifications = value
                            presentation.demo.saveAgent(updated)
                        }))
                        .toggleStyle(MacTeamSwitchStyle(showsLabel: false))
                        .accessibilityLabel("Уведомления: " + agent.name)
                }
                if agent.id != presentation.agents.last?.id { Divider() }
            }
        }.disabled(!presentation.settings.notifications)
        Text("Демо сохраняет предпочтения уведомлений. Системные разрешения macOS не меняются.")
            .font(.system(size: 12)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var profile: some View {
        @Bindable var presentation = presentation
        MacTeamSettingsSection(title: "Личный профиль") {
            MacTeamSettingsRow(title: "Ваше имя", detail: "Отображается в нижней части панели команды.") {
                TextField("Имя", text: $presentation.settings.profileName).frame(width: 220).accessibilityLabel("Ваше имя")
            }
            Divider()
            MacTeamSettingsRow(title: "Пространство", detail: "Профиль принадлежит текущему локальному пространству.") {
                Text("Личное пространство").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var account: some View {
        MacTeamSettingsSection(title: "Пространство") {
            MacTeamSettingsRow(title: "Владелец") { Text(presentation.settings.profileName).foregroundStyle(.secondary) }
            Divider()
            MacTeamSettingsRow(title: "Команда") {
                Text("\(presentation.agents.count) агентов · \(presentation.demo.state.groups.count) групп").foregroundStyle(.secondary)
            }
            Divider()
            MacTeamSettingsRow(title: "Подключённые аккаунты") {
                Text("\(presentation.demo.state.connections.count)").foregroundStyle(.secondary)
            }
        }
        MacTeamSettingsSection(title: "Подписка") {
            MacTeamSettingsLink(title: "Blot " + presentation.settings.plan,
                               detail: "Текущий демонстрационный план пространства.", actionTitle: "Управлять") {
                presentation.sheet = .billing
            }
        }
    }

    @ViewBuilder private var personalization: some View {
        MacTeamSettingsSection(title: "Новые агенты") {
            MacTeamSettingsRow(title: "Роль по умолчанию", detail: "Подставляется при создании нового агента.") {
                TextField("Ассистент", text: $defaultRole).frame(width: 220).accessibilityLabel("Роль по умолчанию")
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("Инструкции по умолчанию").fontWeight(.medium)
                Text("Добавляются в профиль нового агента. Затем их можно изменить под конкретную задачу.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $defaultInstructions).font(.system(size: 13)).scrollContentBackground(.hidden)
                    .frame(height: 130).padding(10)
                    .background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: BlotRadius.control))
                    .accessibilityLabel("Инструкции по умолчанию")
            }.padding(.vertical, 16)
        }
        Text("Существующие агенты сохраняют свои инструкции.").font(.system(size: 12)).foregroundStyle(.secondary)
    }

    private var shortcuts: some View {
        MacTeamSettingsSection(title: "Клавиатура") {
            shortcut("Создать агента", keys: "⌘ N")
            Divider()
            shortcut("Открыть настройки", keys: "⌘ ,")
            Divider()
            shortcut("Поиск в настройках", keys: "⌘ K")
            Divider()
            shortcut("Вернуться из настроек", keys: "⌘ [")
            Divider()
            shortcut("Отправить сообщение", keys: "⌘ ↵")
            Divider()
            shortcut("Закрыть меню или вернуться из настроек", keys: "Esc")
        }
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        MacTeamSettingsRow(title: title) {
            Text(keys).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(MacTeamStyle.field, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder private var usage: some View {
        @Bindable var presentation = presentation
        MacTeamSettingsSection(title: "Недельный лимит") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(presentation.usageFraction * 100))%").font(.system(size: 32, weight: .semibold))
                        .contentTransition(.numericText())
                    Spacer()
                    Text("\(presentation.settings.usedActions) из \(presentation.settings.weeklyLimit) действий").foregroundStyle(.secondary)
                }
                ProgressView(value: presentation.usageFraction).tint(WorkspaceStyle.ink)
                Text("Обновление лимита: " + presentation.dateLabel(presentation.settings.usageResetAt))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.vertical, 20).kAnimation(KMotion.standard, value: presentation.usageFraction)
        }
        MacTeamSettingsSection(title: "Дополнительное использование") {
            MacTeamSettingsRow(title: "Месячный предел", detail: "Демонстрационный предел дополнительных действий. Списаний нет.") {
                MacTeamSelect(title: "Месячный предел", selection: $presentation.settings.usageLimit,
                              values: ["Отключено", "$10", "$25", "$50"], showsTitle: false)
            }
            Divider()
            MacTeamSettingsLink(title: "Подписка", detail: "Blot " + presentation.settings.plan, actionTitle: "Управлять") {
                presentation.sheet = .billing
            }
        }
        MacTeamSettingsSection(title: "Ответы агентов") {
            ForEach(presentation.agents) { agent in
                let count = presentation.demo.state.threads.values.flatMap { $0 }.filter { !$0.isUser && $0.authorID == agent.id }.count
                MacTeamSettingsRow(title: agent.name, detail: agent.role) {
                    Text("\(count) ответов").monospacedDigit().foregroundStyle(.secondary)
                }
                if agent.id != presentation.agents.last?.id { Divider() }
            }
        }
    }
}
