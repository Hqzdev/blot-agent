import BlotDesign
import SwiftUI

#if os(macOS)
struct WorkspaceSettingsPanel: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var entries: [MacSettingsCatalog.Entry] {
        MacSettingsCatalog.entries.filter { $0.matches(query, translate: store.t) }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BlotIcon(.settings, size: 16)
                    Text(store.t("Settings")).font(.system(size: 14, weight: .semibold))
                }.padding(.horizontal, 4)
                searchField
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(entries) { item in
                            Button { select(item.route) } label: {
                                HStack(spacing: 9) {
                                    BlotIcon(item.glyph, size: 15).frame(width: 17)
                                    Text(store.t(item.route.title)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.frame(minHeight: 32).padding(.horizontal, 8)
                                    .background(route == item.route ? BlotColor.selected : .clear, in: RoundedRectangle(cornerRadius: BlotRadius.control))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).help(store.t(item.route.title))
                                .accessibilityAddTraits(route == item.route ? .isSelected : [])
                        }
                        if entries.isEmpty {
                            BlotLabel(store.t("No results"), symbol: "magnifyingglass", size: 15)
                                .font(MacWorkspaceStyle.caption).foregroundStyle(WorkspaceStyle.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 20)
                        }
                    }
                }.scrollIndicators(.hidden)
            }.padding(14).frame(width: 200).background(MacWorkspaceStyle.sidebar)
            VStack(alignment: .trailing, spacing: 0) {
                Button {
                    if store.settingsRoute != nil { store.settingsRoute = nil }
                    else { store.navigate(.chat) }
                } label: { BlotIcon(.close, size: 14).frame(width: 32, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel(store.t("Close"))
                ScrollView { WorkspaceSettingsView(route: route).padding(24) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.font(MacWorkspaceStyle.body).background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
            .clipShape(RoundedRectangle(cornerRadius: BlotRadius.panel, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Button { searchFocused = true } label: { BlotIcon(.search, size: 13) }
                .buttonStyle(.plain).keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel(store.t("Search settings"))
            TextField(store.t("Search settings"), text: $query)
                .textFieldStyle(.plain).focused($searchFocused)
                .foregroundStyle(WorkspaceStyle.ink)
                .accessibilityLabel(store.t("Search settings"))
                .onSubmit { if let first = entries.first { select(first.route) } }
                .onExitCommand { query = ""; searchFocused = false }
            if !query.isEmpty {
                Button { query = ""; searchFocused = true } label: { BlotIcon(.closeCircle, size: 13) }
                    .buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
            }
        }.foregroundStyle(WorkspaceStyle.secondary)
            .padding(.horizontal, 8).frame(height: 30)
            .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: BlotRadius.control))
            .overlay(RoundedRectangle(cornerRadius: BlotRadius.control).strokeBorder(MacWorkspaceStyle.edge))
    }

    private func select(_ destination: WorkspaceRoute) {
        query = ""; searchFocused = false
        if store.settingsRoute != nil { store.settingsRoute = destination }
        else { store.route = destination }
    }
}
#endif
