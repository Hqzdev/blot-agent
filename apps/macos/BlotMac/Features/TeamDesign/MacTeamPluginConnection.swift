import BlotDesign
import SwiftUI

struct MacTeamPluginConnection: View {
    let plugin: MacTeamPlugin
    @Environment(MacTeamPresentation.self) private var presentation
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var connection = MacDemoConnection(
        id: UUID().uuidString, pluginID: "", label: "Рабочий аккаунт", account: "work@demo.blot")
    @State private var disconnect = false
    private var accounts: [MacDemoConnection] {
        presentation.demo.state.connections.filter { $0.pluginID == plugin.id }
    }
    private var duplicateLabel: Bool {
        accounts.contains {
            $0.id != connection.id
                && $0.label.caseInsensitiveCompare(connection.label.trimmingCharacters(in: .whitespacesAndNewlines))
                    == .orderedSame
        }
    }
    private var valid: Bool {
        !connection.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !duplicateLabel
            && (plugin.category != "MCP" || URL(string: connection.endpoint)?.host != nil)
    }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: plugin.category == "MCP" ? "Демо MCP-сервер" : "Подключение приложения")
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 15) {
                        MacTeamPluginIcon(plugin: plugin, size: 54)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plugin.name).font(.system(size: 23, weight: .medium))
                            Text(plugin.summary).foregroundStyle(.secondary)
                        }
                    }
                    Text("Демо-авторизация · настоящий вход в сервис не выполняется").font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !editing {
                        ForEach(accounts) { account in
                            HStack {
                                BlotIcon(symbol: "checkmark.circle", size: BlotIconSize.inline)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(account.label).fontWeight(.medium)
                                    Text(account.account).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Управлять") {
                                    connection = account
                                    editing = true
                                }.buttonStyle(WorkspaceButtonStyle(.secondary))
                            }.teamCard(padding: 14)
                        }
                        BlotIconButton("Добавить ещё аккаунт", symbol: "plus", size: BlotIconSize.inline) { newAccount() }.buttonStyle(
                            WorkspaceButtonStyle(.secondary))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Метка аккаунта").fontWeight(.medium)
                            TextField("Например, work", text: $connection.label).accessibilityLabel("Метка аккаунта")
                            if duplicateLabel { Text("Эта метка уже занята.").font(.system(size: 11)) }
                        }
                        MacTeamSelect(
                            title: plugin.id == "1password" ? "Хранилище" : "Демо-аккаунт",
                            selection: $connection.account,
                            values: plugin.id == "1password"
                                ? ["Хранилище команды", "Личное хранилище"]
                                : ["work@demo.blot", "personal@demo.blot", "team@demo.blot"])
                        if plugin.category == "MCP" {
                            TextField("https://demo.blot/mcp", text: $connection.endpoint).accessibilityLabel(
                                "Адрес MCP-сервера")
                            MacTeamSelect(
                                title: "Авторизация", selection: $connection.authentication,
                                values: ["OAuth", "Демо API-ключ"])
                            Text("Адрес хранится локально. Проверка сервера и сетевые запросы отключены.").font(
                                .system(size: 11)
                            ).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 15) {
                            Text("Разрешения демо-аккаунта").fontWeight(.medium)
                            Toggle("Искать и читать данные", isOn: $connection.allowRead)
                            Toggle("Готовить черновики и документы", isOn: $connection.allowDraft)
                            Toggle("Отправлять после подтверждения", isOn: $connection.allowSend)
                        }.toggleStyle(MacTeamCheckboxStyle()).teamCard()
                        if accounts.contains(where: { $0.id == connection.id }) {
                            Button("Отключить демо-аккаунт", role: .destructive) { disconnect = true }.buttonStyle(BlotPlainButtonStyle())
                        }
                    }
                }.font(.system(size: 12)).padding(24)
            }
            Divider()
            HStack {
                Button("Отмена") { dismiss() }.buttonStyle(WorkspaceButtonStyle(.secondary))
                Spacer()
                Button(editing ? "Сохранить демо-аккаунт" : "Готово") {
                    if editing { presentation.demo.saveConnection(connection) }
                    dismiss()
                }.buttonStyle(WorkspaceButtonStyle()).disabled(editing && !valid)
            }.padding(18)
        }.frame(width: 580, height: editing ? 660 : 520)
            .kAnimation(KMotion.panel, value: editing)
            .onAppear { if accounts.isEmpty { newAccount() } }
            .confirmationDialog("Отключить аккаунт в демо?", isPresented: $disconnect) {
                Button("Отключить", role: .destructive) {
                    presentation.demo.update { $0.connections.removeAll { $0.id == connection.id } }
                    if accounts.isEmpty { newAccount() } else { editing = false }
                }
            }
    }
    private func newAccount() {
        connection = .init(
            id: UUID().uuidString, pluginID: plugin.id, label: "",
            account: plugin.id == "1password" ? "Хранилище команды" : "work@demo.blot",
            endpoint: plugin.category == "MCP" ? "https://demo.blot/mcp" : "")
        editing = true
    }
}
