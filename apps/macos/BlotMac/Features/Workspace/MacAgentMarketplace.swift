import BlotDesign
import SwiftUI

struct MacAgentMarketplaceLink: View {
    let open: () -> Void

    var body: some View {
        MacWorkspacePillButton(action: open) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    ForEach(MacDemoTemplates.all.prefix(4)) { template in
                        MacCatalogAvatar(template: template, size: 16)
                    }
                }
                Text("Marketplace")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .macSidebarHoverSection(radius: 19)
        .accessibilityIdentifier("workspace.agent-marketplace.open")
    }
}

struct MacAgentMarketplace: View {
    let selectTemplate: (MacDemoTemplate) -> Void
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @State private var category: MacAgentMarketplaceCatalog.Category?
    private var russian: Bool { store.language == "ru" }

    var body: some View {
        let templates = MacAgentMarketplaceCatalog.matching(query, category: category, language: store.language)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MacCatalogSearchField(prompt: russian ? "Поиск агентов" : "Search agents", query: $query)
                    .accessibilityIdentifier("workspace.agent-marketplace.search")
                MacCatalogCategories(items: [nil] + MacAgentMarketplaceCatalog.Category.allCases.map(Optional.some),
                    selection: $category) { item in
                    item?.title(russian: russian) ?? (russian ? "Все" : "All")
                }
                HStack {
                    Text(russian ? "Готовые специалисты" : "Ready-made specialists")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(templates.count.formatted()).foregroundStyle(.tertiary).monospacedDigit()
                }
                if templates.isEmpty {
                    ContentUnavailableView {
                        BlotLabel(russian ? "Агенты не найдены" : "No agents found",
                            symbol: "magnifyingglass", size: BlotIconSize.illustration)
                    } description: {
                        Text(russian ? "Попробуйте другое название или выберите «Все»." : "Try a different name or select All.")
                    }.frame(maxWidth: .infinity)
                } else {
                    MacCatalogTemplateGrid(templates: templates, select: selectTemplate)
                }
            }
            .kAnimation(KMotion.standard, value: category)
            .kAnimation(KMotion.standard, value: templates.map(\.id))
            .padding(32).frame(maxWidth: 1040).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("workspace.agent-marketplace")
    }
}
