import BlotDesign
import SwiftUI

struct MacTeamMarketplace: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        MacTeamMarketplaceContent(plugins: presentation.plugins,
            selectPlugin: { presentation.sheet = .plugin($0) },
            selectTemplate: { presentation.sheet = .template($0.id) },
            addPlugin: { presentation.sheet = .addPlugin })
    }
}

/// Catalog presentation is shared; account and demo actions remain separate.
struct MacTeamMarketplaceContent: View {
    let plugins: [MacTeamPlugin]
    let selectPlugin: (MacTeamPlugin) -> Void
    let selectTemplate: (MacDemoTemplate) -> Void
    var addPlugin: (() -> Void)?
    var topInset: CGFloat = 64
    var pluginActionTitle = "Подключить"
    var subtitle = "Подключите ваши приложения или пригласите готового специалиста."
    @State private var search = ""
    @State private var category = "Все"
    private var filteredPlugins: [MacTeamPlugin] {
        plugins.filter {
            (category == "Все" || $0.category == category)
                && (search.isEmpty || ($0.name + $0.summary).localizedCaseInsensitiveContains(search))
        }
    }
    private var templates: [MacDemoTemplate] {
        MacDemoTemplates.all.filter {
            search.isEmpty || ($0.name + $0.role + $0.summary).localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    MacTeamSectionHeading(
                        title: "Больше возможностей для команды",
                        subtitle: subtitle)
                    if let addPlugin {
                        Button(action: addPlugin) {
                            BlotLabel("Добавить плагин", symbol: "plus", size: BlotIconSize.control)
                        }.buttonStyle(WorkspaceButtonStyle()).fixedSize()
                    }
                }
                HStack(spacing: 9) {
                    BlotIcon(symbol: "magnifyingglass", size: BlotIconSize.control).foregroundStyle(.secondary)
                    TextField("Поиск приложений и шаблонов", text: $search).textFieldStyle(.plain)
                }
                .padding(12).background(WorkspaceStyle.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                if !templates.isEmpty {
                    Text("Готовые специалисты").font(.system(size: 15, weight: .semibold))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                        ForEach(templates) { item in template(item) }
                    }
                }
                HStack {
                    Text("Приложения").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("\(filteredPlugins.count)").foregroundStyle(.tertiary)
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(
                            ["Все", "Приложения Apple", "Работа", "Общение", "Финансы", "Пароли", "MCP", "Разработка", "Контент"],
                            id: \.self
                        ) { item in
                            Button {
                                category = item
                            } label: {
                                Text(item).font(.system(size: 11, weight: category == item ? .medium : .regular))
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .foregroundStyle(category == item ? BlotColor.onInverse : WorkspaceStyle.ink)
                                    .background(
                                        category == item ? BlotColor.inverse : WorkspaceStyle.surface, in: Capsule())
                            }.buttonStyle(BlotPlainButtonStyle())
                        }
                    }
                }.scrollIndicators(.hidden)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                    ForEach(filteredPlugins) { plugin in
                        Button {
                            selectPlugin(plugin)
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                MacTeamPluginIcon(plugin: plugin)
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(plugin.name).font(.system(size: 13, weight: .semibold))
                                    Text(plugin.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(
                                        2
                                    ).frame(height: 30, alignment: .top)
                                    if let status = plugin.connectionStatus {
                                        Text(status).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                                    } else if !plugin.accounts.isEmpty {
                                        BlotLabel("Аккаунтов: \(plugin.accounts.count)", symbol: "checkmark", size: BlotIconSize.inline)
                                            .foregroundStyle(.teal).font(.system(size: 10))
                                    } else {
                                        Text(pluginActionTitle).font(.system(size: 10, weight: .medium)).foregroundStyle(WorkspaceStyle.ink)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                BlotIcon(symbol: "chevron.right", size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                                    .padding(.top, 3)
                            }.teamCard().frame(maxWidth: .infinity)
                        }.buttonStyle(BlotPlainButtonStyle())
                    }
                }
                if filteredPlugins.isEmpty && templates.isEmpty {
                    ContentUnavailableView {
                        BlotLabel("Ничего не найдено", symbol: "magnifyingglass", size: BlotIconSize.illustration)
                    } description: { Text("Попробуйте другое название приложения или шаблона.") }.frame(maxWidth: .infinity)
                }
            }.kAnimation(KMotion.standard, value: category)
                .kAnimation(KMotion.standard, value: filteredPlugins.map(\.id))
                .padding(32).frame(maxWidth: 1040).frame(maxWidth: .infinity)
        }.contentMargins(.top, topInset, for: .scrollContent)
    }
    private func template(_ template: MacDemoTemplate) -> some View {
        Button {
            selectTemplate(template)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                WorkspaceAvatar(
                    shape: WorkspaceAvatar.ShapeKind(rawValue: template.shape) ?? .round,
                    color: WorkspaceAvatarView.color(template.color), size: 46)
                Text(template.name).font(.system(size: 14, weight: .medium))
                Text(template.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                BlotLabel("Посмотреть шаблон", symbol: "arrow.up.right", size: BlotIconSize.inline).font(.system(size: 10)).foregroundStyle(WorkspaceStyle.ink)
            }.frame(maxWidth: .infinity, alignment: .leading).teamCard(padding: 18)
        }.buttonStyle(BlotPlainButtonStyle())
    }
}

struct MacTeamTemplateDetail: View {
    let templateID: String
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var tab = "Инструкции"
    private var template: MacDemoTemplate {
        MacDemoTemplates.all.first { $0.id == templateID } ?? MacDemoTemplates.all[0]
    }
    var body: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Шаблон агента")
            Divider()
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 18) {
                    WorkspaceAvatar(
                        shape: WorkspaceAvatar.ShapeKind(rawValue: template.shape) ?? .round,
                        color: WorkspaceAvatarView.color(template.color), size: 64)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(template.name).font(.system(size: 23, weight: .medium))
                        Text("Коллекция Blot · " + template.role).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Text(template.summary).lineSpacing(5).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 22) {
                    VStack(spacing: 4) {
                        ForEach(["Инструкции", "Память", "Навыки", "Расписания", "Интеграции"], id: \.self) { item in
                            MacTeamNavigationButton(selected: tab == item) {
                                tab = item
                            } label: {
                                Text(item)
                            }
                        }
                    }.frame(width: 145)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(tab).fontWeight(.semibold)
                            Text(description).lineSpacing(5).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .id(tab).transition(.opacity)
                    }.kAnimation(KMotion.standard, value: tab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).teamCard()
                }.frame(height: 245)
            }.font(.system(size: 12)).padding(26)
            Divider()
            HStack {
                Text("Импортирует инструкции, память, навыки и расписания.").font(.system(size: 10)).foregroundStyle(
                    .secondary)
                Spacer()
                Button("Добавить в команду") {
                    presentation.selectedTemplateID = template.id
                    presentation.importTemplate()
                }.buttonStyle(WorkspaceButtonStyle())
            }.padding(18)
        }.frame(width: 710)
    }
    private var description: String {
        switch tab {
        case "Память":
            template.memories.isEmpty
                ? "У шаблона пока нет воспоминаний. Их можно добавить в профиле или сообщением «Запомни…»."
                : template.memories.joined(separator: "\n\n")
        case "Навыки": template.skills.joined(separator: "\n\n")
        case "Расписания":
            template.routine.map { $0 + "\n\nПосле импорта расписание приостановлено. Выберите время и включите его." }
                ?? "Готовых расписаний нет. Добавьте регулярную задачу в переписке."
        case "Интеграции":
            template.plugins.isEmpty
                ? "Для начала подключения не нужны."
                : template.plugins.map { id in
                    let plugin = presentation.plugins.first { $0.id == id }
                    return (plugin?.name ?? id)
                        + ((plugin?.accounts.isEmpty ?? true)
                            ? " · нужно демо-подключение" : " · демо-аккаунт уже доступен")
                }.joined(separator: "\n\n")
        default: template.instructions
        }
    }
}
