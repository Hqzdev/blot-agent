import BlotDesign
import SwiftUI

/// A full workspace page. The team and conversation remain in the presentation when returning.
struct MacTeamSettings: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        MacTeamSettingsLayout(close: { presentation.closeSettings() },
            searchFocusRequest: presentation.settingsSearchFocusRequest, footer: "Blot · Демо на этом Mac") { pane in
            switch pane {
            case .memory, .storage, .privacy: MacTeamWorkspaceSettingsContent(pane: pane)
            case .connections, .mcp, .updates: MacTeamIntegrationSettingsContent(pane: pane)
            default: MacTeamPersonalSettingsContent(pane: pane)
            }
        }
    }
}

/// Original settings chrome shared by preview and authenticated account content.
struct MacTeamSettingsLayout<PaneContent: View>: View {
    let close: () -> Void
    var searchFocusRequest = 0
    var footer = "Blot"
    var initialPane: MacTeamSettingsPane = .general
    @ViewBuilder let paneContent: (MacTeamSettingsPane) -> PaneContent
    @State private var pane: MacTeamSettingsPane = .general
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var results: [MacTeamSettingsPane] {
        MacTeamSettingsPane.allCases.filter { query.isEmpty || $0.matches(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(query.isEmpty ? pane.title : "Результаты поиска").font(.system(size: 27, weight: .semibold))
                        Text(query.isEmpty ? pane.detail : "Настройки по запросу «\(query)»")
                            .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                    }
                    if query.isEmpty {
                        ZStack(alignment: .topLeading) {
                            VStack(alignment: .leading, spacing: 28) {
                                paneContent(pane)
                            }.id(pane).transition(.opacity)
                        }.kAnimation(KMotion.standard, value: pane)
                    } else {
                        searchResults
                    }
                }
                .frame(maxWidth: 850, alignment: .leading)
                .padding(.horizontal, 44).padding(.top, 34).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .id(query.isEmpty ? pane.id : "search")
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(MacTeamSettingsStyle.canvas)
        }
        .overlay(alignment: .top) {
            Color.clear.frame(height: 24).contentShape(Rectangle())
                .gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
        }
        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.ink).teamControls()
        .onAppear { pane = initialPane }
        .onExitCommand { close() }
        .onChange(of: searchFocusRequest) { _, _ in searchFocused = true }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            MacTeamNavigationButton { close() } label: {
                HStack(spacing: 10) {
                    BlotIcon(.chevronLeft, size: BlotIconSize.control).frame(width: 28, height: 28)
                    Text("Настройки").font(.system(size: 15, weight: .semibold))
                    Spacer()
                }
            }
            .help("Вернуться к команде").accessibilityLabel("Вернуться к команде")
            .padding(.horizontal, 2).frame(height: 56)
            HStack(spacing: 8) {
                BlotIcon(.search, size: BlotIconSize.control).foregroundStyle(.secondary)
                TextField("Поиск настроек", text: $search).textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityLabel("Поиск настроек")
                if !search.isEmpty {
                    MacTeamIconButton(title: "Очистить поиск", symbol: "xmark") { search = "" }
                }
            }.padding(.horizontal, 10).frame(height: 34)
                .background(MacTeamStyle.field, in: Capsule()).padding(.horizontal, 12).padding(.bottom, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(["Личное", "Пространство", "Интеграции"], id: \.self) { group in
                        let items = results.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 10).padding(.bottom, 5)
                                ForEach(items) { item in
                                    MacTeamSettingsNavigationRow(pane: item, selected: query.isEmpty && pane == item) {
                                        pane = item
                                        search = ""
                                    }
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 12).padding(.bottom, 16)
            }.scrollIndicators(.hidden)
            HStack(spacing: 7) {
                Circle().fill(WorkspaceStyle.secondary.opacity(0.6)).frame(width: 5, height: 5)
                Text(footer).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(18)
        }.padding(.top, 44).frame(width: 244).background(MacTeamStyle.sidebar)
    }

    private var searchResults: some View {
        VStack(spacing: 12) {
            if results.isEmpty {
                ContentUnavailableView {
                    BlotLabel("Ничего не найдено", symbol: "magnifyingglass", size: BlotIconSize.illustration)
                } description: { Text("Попробуйте «тема», «Enter» или название приложения.") }
            }
            ForEach(results) { result in
                MacTeamNavigationButton {
                    pane = result
                    search = ""
                } label: {
                    HStack(spacing: 14) {
                        BlotIcon(result.glyph, size: BlotIconSize.navigation)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.title).fontWeight(.medium)
                            Text(result.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(.chevronRight, size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}
