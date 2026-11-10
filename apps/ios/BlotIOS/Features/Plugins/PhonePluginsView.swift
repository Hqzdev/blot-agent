import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct PhonePluginsView: View {
    private enum Category: String, CaseIterable {
        case installed, featured, finance, productivity

        func title(russian: Bool) -> String {
            switch self {
            case .installed: russian ? "Установлено" : "Installed"
            case .featured: "Featured"
            case .finance: russian ? "Финансы" : "Finance"
            case .productivity: russian ? "Продуктивность" : "Productivity"
            }
        }
    }

    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var category = Category.featured
    @State private var managedPlugin: PhonePlugin?
    @FocusState private var searchFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear.frame(height: 0).id("plugins.top")
                    ForEach(plugins) { plugin in
                        PhonePluginCard(plugin: plugin, installed: isInstalled(plugin)) {
                            searchFocused = false
                            managedPlugin = plugin
                        }
                    }
                    if plugins.isEmpty { emptyState }
                    WorkspaceFeedback()
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16).padding(.bottom, 16)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: category) { proxy.scrollTo("plugins.top", anchor: .top) }
            .onChange(of: query) { proxy.scrollTo("plugins.top", anchor: .top) }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 16) {
                header
                categories
            }.padding(.top, 8).padding(.bottom, 4)
                .background(PhonePluginsStyle.canvas)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            search.padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 12)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .sheet(item: $managedPlugin) { plugin in
            PhonePluginConnectionView(plugin: plugin).environment(store)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .background(PhonePluginsStyle.canvas.ignoresSafeArea())
        .foregroundStyle(WorkspaceStyle.ink)
        .workspaceGlassContainer()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: category)
        .sensoryFeedback(.selection, trigger: category)
        .sensoryFeedback(.success, trigger: store.snapshot.connections.count) { old, new in new > old }
        .accessibilityIdentifier("workspace.plugins")
    }

    private var header: some View {
        HStack {
            PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) {
                if store.pluginCatalogVisible { store.pluginCatalogVisible = false } else { store.back() }
            }
            Spacer(minLength: 8)
            Text(store.language == "ru" ? "Плагины" : "Plugins")
                .font(.headline).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }.padding(.horizontal, 20)
    }

    private var categories: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases, id: \.self) { item in
                    Button { category = item } label: {
                        Text(item.title(russian: store.language == "ru"))
                            .font(.subheadline.weight(category == item ? .semibold : .regular))
                            .foregroundStyle(category == item ? WorkspaceStyle.ink : WorkspaceStyle.secondary)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(category == item ? PhonePluginsStyle.selection : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(category == item ? .isSelected : [])
                        .accessibilityIdentifier("workspace.plugins.category.\(item.rawValue)")
                }
            }.padding(.horizontal, 14)
        }
    }

    private var search: some View {
        HStack(spacing: 10) {
            BlotIcon(.search, size: 20).foregroundStyle(WorkspaceStyle.secondary)
            TextField(store.t("Search"), text: $query)
                .font(.body).textFieldStyle(.plain).autocorrectionDisabled()
                .textInputAutocapitalization(.never).submitLabel(.search)
                .focused($searchFocused).accessibilityLabel(store.t("Search plugins"))
                .accessibilityIdentifier("workspace.plugins.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    BlotIcon(.closeCircle, size: 18).foregroundStyle(WorkspaceStyle.secondary)
                        .frame(width: 44, height: 48)
                }.buttonStyle(.plain).accessibilityLabel(store.t("Clear search"))
            }
        }
        .padding(.leading, 16).padding(.trailing, query.isEmpty ? 16 : 2)
        .frame(minHeight: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            BlotLabel(store.t("No plugins found"), symbol: "magnifyingglass", size: 32)
        } description: {
            if category == .installed && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(store.language == "ru" ? "Подключённые приложения появятся здесь." : "Connected apps will appear here.")
            } else {
                Text(store.language == "ru" ? "Попробуйте другую категорию или измените запрос." : "Try another category or search term.")
            }
        }.padding(.vertical, 32)
    }

    private var plugins: [PhonePlugin] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return PhonePlugin.all.filter { plugin in
            let matchesCategory: Bool
            switch category {
            case .installed: matchesCategory = isInstalled(plugin)
            case .featured: matchesCategory = true
            case .finance: matchesCategory = plugin.category == "Финансы"
            case .productivity: matchesCategory = plugin.category == "Работа" || plugin.appleID != nil
            }
            return matchesCategory && (term.isEmpty || plugin.name.localizedCaseInsensitiveContains(term)
                || store.t(plugin.description).localizedCaseInsensitiveContains(term))
        }
    }

    private func isInstalled(_ plugin: PhonePlugin) -> Bool {
        store.snapshot.connections.contains {
            ($0.pluginId == plugin.id || $0.service == plugin.name) && $0.state == .connected
                && (plugin.appleID == nil || $0.deviceId == store.snapshot.localDeviceID)
        }
    }
}

private struct PhonePluginCard: View {
    let plugin: PhonePlugin
    let installed: Bool
    let manage: () -> Void
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            HStack(spacing: 10) {
                Image(plugin.asset).resizable().scaledToFit().frame(width: 44, height: 44)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    WorkspaceLocalizedText(plugin.name).font(.body.weight(.semibold))
                    Text(store.t(plugin.description)).font(.subheadline)
                        .foregroundStyle(WorkspaceStyle.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: manage) {
                Group {
                    if let apple = plugin.appleID { ApplePluginStatusText(plugin: apple) }
                    else {
                        Text(installed ? store.t("Connected") : store.language == "ru" ? "Установить" : "Install")
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(PhonePluginsStyle.action, in: Capsule())
                    }
                }
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: 44)
                .contentShape(Capsule())
            }.buttonStyle(.plain).disabled(store.busy)
                .accessibilityLabel(store.t("Manage connection") + " " + plugin.name)
                .accessibilityIdentifier("workspace.plugins.manage.\(plugin.id)")
        }
        .padding(16).frame(minHeight: 80)
        .background(PhonePluginsStyle.card, in: RoundedRectangle(cornerRadius: 28))
        .accessibilityElement(children: .contain)
    }
}

private enum PhonePluginsStyle {
    static var canvas: Color { BlotColor.dynamic(.init(light: 0xF5F5F5FF, dark: 0x111111FF)) }
    static var card: Color { BlotColor.dynamic(.init(light: 0xFFFFFFFF, dark: 0x1B1B1BFF)) }
    static var action: Color { BlotColor.dynamic(.init(light: 0xF7F7F7FF, dark: 0x292929FF)) }
    static var selection: Color { BlotColor.dynamic(.init(light: 0xECECECFF, dark: 0x2B2B2BFF)) }
}
