import BlotDesign
import SwiftUI

struct MacTeamPluginPicker: View {
    @Environment(MacTeamPresentation.self) private var presentation
    @State private var search = ""
    @State private var selectedPlugin: MacTeamPlugin?

    private var plugins: [MacTeamPlugin] {
        presentation.plugins.filter {
            search.isEmpty || ($0.name + " " + $0.summary).localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        Group {
            if let selectedPlugin {
                MacTeamPluginConnection(plugin: selectedPlugin)
            } else {
                picker
            }
        }.kAnimation(KMotion.standard, value: selectedPlugin?.id)
    }

    private var picker: some View {
        VStack(spacing: 0) {
            MacTeamSheetHeader(title: "Добавить плагин")
            Divider()
            VStack(alignment: .leading, spacing: 16) {
                Text("Выберите приложение для подключения.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                TextField("Поиск плагинов", text: $search).accessibilityLabel("Поиск плагинов")
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(plugins) { plugin in
                            MacTeamNavigationButton {
                                selectedPlugin = plugin
                            } label: {
                                HStack(spacing: 12) {
                                    MacTeamPluginIcon(plugin: plugin, size: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(plugin.name).font(.system(size: 13, weight: .medium))
                                        Text(plugin.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    BlotIcon(.plus, size: BlotIconSize.control)
                                }
                            }
                        }
                        if plugins.isEmpty {
                            ContentUnavailableView {
                                BlotLabel("Ничего не найдено", symbol: "magnifyingglass", size: BlotIconSize.illustration)
                            } description: { Text("Попробуйте другое название плагина.") }
                        }
                    }
                }
            }.padding(20)
        }.frame(width: 520, height: 560)
    }
}
