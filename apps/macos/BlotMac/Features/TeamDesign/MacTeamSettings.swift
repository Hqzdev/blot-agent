import BlotDesign
import SwiftUI

/// A full workspace page. The team and conversation remain in the presentation when returning.
struct MacTeamSettings: View {
    @Environment(MacTeamPresentation.self) private var presentation
    var body: some View {
        MacTeamSettingsLayout(close: { presentation.closeSettings() },
            searchFocusRequest: presentation.settingsSearchFocusRequest, footer: "Blot · Демо на этом Mac") { pane in
            switch pane {
            case .devices:
                MacTeamSettingsSection(title: "Устройства") { Text("Войдите в аккаунт, чтобы связать iPhone и Mac и передавать задачи.").foregroundStyle(.secondary) }
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
        GeometryReader { geometry in
            let compact = geometry.size.width < 920
            HStack(spacing: 0) {
                if !compact { sidebar }
                VStack(spacing: 0) {
                    if compact { compactHeader }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 44) {
                            VStack(alignment: .leading, spacing: 8) {
                                WorkspaceLocalizedText(query.isEmpty ? pane.title : "Результаты поиска").font(.system(size: 28, weight: .medium))
                                    .accessibilityAddTraits(.isHeader)
                                if !query.isEmpty {
                                    Text("Настройки по запросу «\(query)»").font(.system(size: 13)).foregroundStyle(.secondary)
                                }
                            }
                            if query.isEmpty {
                                ZStack(alignment: .topLeading) {
                                    VStack(alignment: .leading, spacing: 42) {
                                        paneContent(pane)
                                    }.id(pane).transition(.opacity)
                                }.kAnimation(KMotion.standard, value: pane)
                            } else {
                                searchResults
                            }
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, compact ? 24 : 44).padding(.top, compact ? 24 : 34).padding(.bottom, 32)
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    .id(query.isEmpty ? pane.id : "search")
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(MacTeamSettingsStyle.canvas)
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            }
            .environment(\.macCompactSettings, geometry.size.width - (compact ? 48 : 332) < 580)
        }
        .overlay(alignment: .top) {
            Color.clear.frame(height: 24).contentShape(Rectangle())
                .gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
        }
        .font(.system(size: 13)).foregroundStyle(WorkspaceStyle.ink).teamControls()
        .onAppear { pane = initialPane }
        .onChange(of: initialPane) { _, value in pane = value; search = "" }
        .onExitCommand { close() }
        .onChange(of: searchFocusRequest) { _, _ in searchFocused = true }
    }

    private var compactHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: close) {
                    Label("К команде", systemImage: "chevron.left")
                }.buttonStyle(.plain).accessibilityLabel("Вернуться к команде")
                Spacer(minLength: 8)
                Menu {
                    ForEach(["Личное", "Пространство", "Интеграции"], id: \.self) { group in
                        Section(group) {
                            ForEach(MacTeamSettingsPane.allCases.filter { $0.group == group }) { item in
                                Button(LocalizedStringKey(item.title)) { pane = item; search = "" }
                            }
                        }
                    }
                } label: { WorkspaceLocalizedText(pane.title).lineLimit(1) }
                .accessibilityLabel("Раздел настроек")
            }.frame(height: 36).padding(.leading, 108).padding(.trailing, 24)
            searchField.padding(.horizontal, 24)
        }.padding(.top, 14).padding(.bottom, 12).background(MacTeamStyle.sidebar)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            BlotIcon(.search, size: BlotIconSize.control).foregroundStyle(.secondary)
            TextField("Поиск настроек", text: $search).textFieldStyle(.plain).focused($searchFocused)
                .accessibilityLabel("Поиск настроек")
            if !search.isEmpty {
                MacTeamIconButton(title: "Очистить поиск", symbol: "xmark") { search = "" }
            }
        }.padding(.horizontal, 10).frame(height: 36).background(MacTeamStyle.field, in: Capsule())
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Настройки").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "arrow.left").font(.system(size: 14)) }
                    .buttonStyle(.plain).help("Вернуться к команде").accessibilityLabel("Вернуться к команде")
            }.padding(.horizontal, 20).frame(height: 54)
            searchField.padding(.horizontal, 16).padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(["Личное", "Пространство", "Интеграции"], id: \.self) { group in
                        let items = results.filter { $0.group == group }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                WorkspaceLocalizedText(group).font(.system(size: 13, weight: .regular)).foregroundStyle(.secondary)
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
                WorkspaceLocalizedText(footer).font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(18)
        }.padding(.top, 44).frame(width: 250).background(MacTeamSettingsStyle.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(MacTeamSettingsStyle.edge.opacity(0.5)).frame(width: 1) }
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
                            WorkspaceLocalizedText(result.title).fontWeight(.medium)
                            WorkspaceLocalizedText(result.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        BlotIcon(.chevronRight, size: BlotIconSize.inline).foregroundStyle(WorkspaceStyle.ink)
                    }.padding(.vertical, 4)
                }
            }
        }
    }
}
