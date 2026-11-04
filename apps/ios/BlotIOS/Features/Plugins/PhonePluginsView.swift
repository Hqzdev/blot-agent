import BlotDesign
import BlotDomain
import SwiftUI

struct PhonePluginsView: View {
    private enum Filter: String, CaseIterable { case all = "All plugins", added = "Added", available = "Available" }
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @State private var filter = Filter.all
    @State private var section: PhonePlugin.Section?
    @State private var managedPlugin: PhonePlugin?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                search
                ForEach(PhonePlugin.Section.allCases, id: \.self) { group in
                    if section == nil || section == group {
                        VStack(spacing: 20) {
                            HStack {
                                Text(store.t(group.rawValue)).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                                Spacer()
                                Button(store.t(section == group ? "Show all" : "View all")) { section = section == group ? nil : group }
                                    .font(.caption).foregroundStyle(WorkspaceStyle.secondary).buttonStyle(.plain)
                            }
                            ForEach(plugins(in: group)) { plugin in row(plugin) }
                        }
                    }
                }
                if PhonePlugin.Section.allCases.allSatisfy({ plugins(in: $0).isEmpty }) {
                    Text(store.t("No plugins found")).font(.subheadline).foregroundStyle(WorkspaceStyle.secondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
                WorkspaceFeedback()
            }.padding(.horizontal, 24).padding(.top, 78).padding(.bottom, 28)
        }
        .sheet(item: $managedPlugin) { plugin in
            PhonePluginConnectionView(plugin: plugin).environment(store)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .top) {
            HStack(spacing: 12) {
                PhoneGlassCircleButton(symbol: "chevron.left", title: store.t("Back")) {
                    if store.pluginCatalogVisible { store.pluginCatalogVisible = false } else { store.back() }
                }
                Text(store.t("Plugins")).font(.headline)
                Spacer()
            }.padding(.horizontal, 18).padding(.top, 16)
        }
        .background(WorkspaceStyle.canvas.ignoresSafeArea())
        .workspaceGlassContainer()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: filter)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: section)
        .sensoryFeedback(.selection, trigger: filter)
        .sensoryFeedback(.success, trigger: store.snapshot.connections.count) { old, new in new > old }
    }

    private var search: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                BlotIcon(symbol: "magnifyingglass").foregroundStyle(WorkspaceStyle.secondary)
                TextField(store.t("Search plugins"), text: $query).font(.subheadline).textFieldStyle(.plain)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel(store.t("Search plugins"))
            }.padding(.horizontal, 14).frame(minHeight: 40).glassEffect(.regular.interactive(), in: .capsule)
            Menu {
                Picker(store.t("Filter"), selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text(store.t($0.rawValue)).tag($0) }
                }
            } label: {
                BlotIcon(symbol: "line.3.horizontal.decrease").font(.body)
                    .frame(width: 40, height: 40).glassEffect(.regular.interactive(), in: .circle)
            }.accessibilityLabel(store.t("Filter"))
        }
    }

    private func plugins(in section: PhonePlugin.Section) -> [PhonePlugin] {
        PhonePlugin.all.filter { plugin in
            let matchesQuery = query.isEmpty || plugin.name.localizedCaseInsensitiveContains(query) || store.t(plugin.description).localizedCaseInsensitiveContains(query)
            let matchesFilter = filter == .all || (filter == .added ? isAdded(plugin) : !isAdded(plugin))
            return plugin.section == section && matchesQuery && matchesFilter
        }
    }

    private func isAdded(_ plugin: PhonePlugin) -> Bool {
        store.snapshot.connections.contains { $0.service == plugin.name && $0.state == .connected }
    }

    private func row(_ plugin: PhonePlugin) -> some View {
        HStack(spacing: 12) {
            Image(plugin.asset).resizable().scaledToFit().frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.name).font(.subheadline.weight(.medium))
                Text(store.t(plugin.description)).font(.caption).foregroundStyle(WorkspaceStyle.secondary).lineLimit(3)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                _Concurrency.Task {
                    if store.snapshot.connections.contains(where: { $0.service == plugin.name }) {
                        managedPlugin = plugin
                    } else {
                        store.form.connection = .init(service: plugin.name, scopes: plugin.scopes)
                        await store.perform(.addConnection)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    if isAdded(plugin) { BlotIcon(symbol: "checkmark", size: 12) }
                    Text(store.t(isAdded(plugin) ? "Added" : "Add"))
                }.font(.caption2.weight(.medium))
                    .foregroundStyle(isAdded(plugin) ? Color(red: 0.21, green: 0.66, blue: 0.49) : WorkspaceStyle.ink)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isAdded(plugin) ? Color.green.opacity(0.09) : WorkspaceStyle.surface, in: Capsule())
                    .frame(minHeight: 44)
            }.buttonStyle(.plain).disabled(store.busy)
                .accessibilityLabel(store.t(isAdded(plugin) ? "Manage connection" : "Add") + " " + plugin.name)
        }.frame(minHeight: 56)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isAdded(plugin))
    }
}
