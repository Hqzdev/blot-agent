import BlotDesign
import SwiftUI

struct PhoneSettingsMenuView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    private var entries: [PhoneSettingsCatalog.Item] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhoneSettingsCatalog.items.filter {
            query.isEmpty || (store.settingsText($0.title) + " " + store.settingsText($0.detail)).localizedStandardContains(query)
        }
    }
    var body: some View {
        PhoneSettingsPage {
            PhonePageSearchField(placeholder: store.settingsText("Search settings"), text: $query)
                .accessibilityIdentifier("workspace.settings.search")
            if !store.unresolvedConflicts.isEmpty {
                Button { store.conflictsVisible = true } label: {
                    PhoneSettingsRow(title: "Review conflicting changes", symbol: "arrow.triangle.branch")
                }.buttonStyle(.plain)
            }
            ForEach(PhoneSettingsCatalog.groups, id: \.self) { group in
                let items = entries.filter { $0.group == group }
                if !items.isEmpty {
                    PhoneSettingsGroup(title: group) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { PhoneSettingsDivider() }
                            Button { store.navigate(item.route) } label: {
                                PhoneSettingsRow(title: item.title, symbol: item.symbol)
                            }.buttonStyle(.plain).accessibilityIdentifier("workspace.settings.\(item.route.rawValue)")
                        }
                    }
                }
            }
            if entries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.settingsText("Nothing found")).font(.headline)
                    Text(store.settingsText("Try another setting name.")).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Text("Blot · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"))
                .font(.footnote).foregroundStyle(WorkspaceStyle.secondary).frame(maxWidth: .infinity)
        }
        .scrollPosition(store.navigation.position(for: .settings))
        .onAppear { store.navigation.restorePosition(for: .settings) }
        .onScrollGeometryChange(for: CGFloat.self) { max(0, $0.contentOffset.y + $0.contentInsets.top) } action: { old, new in
            if abs(old - new) > 0.5 { store.navigation.recordOffset(new, for: .settings) }
        }
        .accessibilityLabel(store.t("Settings"))
    }
}
