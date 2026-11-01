import BlotDesign
import SwiftUI

/// «Settings Sidebar» from agent.pen: title, search, sections grouped as Personal / Agent / Integrations.
struct SettingsSidebar: View {
    @Environment(AppState.self) private var app
    var body: some View {
        @Bindable var settings = app.settings
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: KSpace.sm) {
                Text("Settings").font(KFont.sidebarTitle()).foregroundStyle(K.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                IconButton(icon: "x", help: "Close settings · Esc") { app.showingSettings = false }
            }
            .padding(.leading, 16).padding(.trailing, 10)
            .frame(height: K.headerHeight)
            KSearchField(placeholder: "Search settings", text: $settings.search)
                .padding(.horizontal, 12).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: K.sidebarRowSpacing) {
                    ForEach(["Personal", "Agent", "Integrations"], id: \.self) { group in
                        let sections = SettingsSection.allCases.filter {
                            $0.group == group && (settings.search.isEmpty ||
                                $0.rawValue.localizedCaseInsensitiveContains(settings.search))
                        }
                        if !sections.isEmpty {
                            SectionLabel(title: group)
                            ForEach(sections) { section in
                                SidebarItem(icon: section.icon, label: section.rawValue,
                                            active: settings.section == section) {
                                    settings.section = section
                                }
                            }
                        }
                    }
                    if !settings.search.isEmpty && !SettingsSection.allCases.contains(where: {
                        $0.rawValue.localizedCaseInsensitiveContains(settings.search)
                    }) {
                        Text("No settings match “\(settings.search)”").font(KFont.caption()).foregroundStyle(K.text3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                    }
                }.padding(.horizontal, 6).padding(.bottom, 12)
            }.scrollIndicators(.never)
            Text("Settings for this Mac")
                .font(KFont.caption()).foregroundStyle(K.text3).padding(16)
        }
        .onExitCommand { app.showingSettings = false }
    }
}

/// «04 · Settings — General» page: section title, then the section's groups.
struct SettingsView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: KSpace.section) {
                Text(app.settings.section.rawValue).font(KFont.pageTitle()).foregroundStyle(K.text)
                    .accessibilityAddTraits(.isHeader)
                page.id(app.settings.section).transition(.kAppear)
            }
            .kAnimation(value: app.settings.section)
        }
        .background(K.bg)
    }

    @ViewBuilder private var page: some View {
        switch app.settings.section {
        case .general: GeneralSettingsView(settings: app.settings)
        case .permissions: PermissionsSettingsView(settings: app.settings)
        case .models: ModelsSettingsView(settings: app.settings)
        case .appearance, .notifications, .shortcuts, .account, .billing:
            PersonalSettingsView(settings: app.settings)
        case .environments: VirtualMachineSettingsView()
        case .instructions, .skills:
            AgentSettingsView(settings: app.settings)
        case .git: ProjectAccessSettingsView()
        case .servers, .editors, .browser:
            IntegrationSettingsView(settings: app.settings)
        }
    }
}
