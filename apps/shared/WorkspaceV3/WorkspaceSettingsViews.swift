import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceSettingsView: View {
    let route: WorkspaceRoute
    var embedded = false
    @State private var keyProvider: String?
    @State private var editingMemoryID: UUID?
    #if os(macOS)
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .light
    #else
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system
    #endif
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            #if os(macOS)
            if !embedded {
                HStack(spacing: 10) {
                    BlotIcon(MacSettingsCatalog.glyph(for: route), size: 22)
                    Text(store.t(route.title)).font(.system(size: 24, weight: .semibold)).accessibilityAddTraits(.isHeader)
                }
            }
            #endif
            if !store.unresolvedConflicts.isEmpty {
                Button { store.conflictsVisible = true } label: {
                    BlotLabel(store.t("Review conflicting changes"), symbol: "arrow.triangle.branch")
                }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
            content
            WorkspaceFeedback()
        }
    }
    @ViewBuilder private var content: some View {
        switch route {
        #if os(macOS)
        case .settingsProfile: MacSettingsProfilePane()
        case .settingsStorage: MacSettingsStoragePane()
        case .settingsUpdates: WorkspaceUpdatesView()
        case .usage: MacSettingsUsagePane()
        case .personalization: MacSettingsPersonalizationPane()
        #endif
        case .account: account
        case .models: models
        case .permissions: permissions
        case .connections: connections
        case .devices:
            if store.mode == .live { WorkspacePairedDevicesView() } else { devices }
        case .pair:
            if store.mode == .live { WorkspaceDevicePairingView() } else { pair }
        case .memory: memory
        case .mcp: mcp
        case .browserSettings: browserSettings
        case .permissionRules: rules
        case .appearance: appearance
        case .language: language
        case .notifications: notifications
        default: general
        }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceTeamBotsButton()
            #if os(iOS)
            WorkspaceLink(title: "Account", route: .account, symbol: "person.crop.circle")
            WorkspaceCard {
                WorkspaceLink(title: "Computers", route: .devices, symbol: "laptopcomputer")
                WorkspaceLink(title: "Connections", route: .connections, symbol: "powerplug")
                WorkspaceLink(title: "AI models", route: .models, symbol: "cpu")
                WorkspaceLink(title: "Access and permissions", route: .permissions, symbol: "checkmark.shield")
            }
            WorkspaceCard { WorkspaceLink(title: "Notifications", route: .notifications, symbol: "bell")
                WorkspaceLink(title: "Appearance", route: .appearance, symbol: "sun.max")
                WorkspaceLink(title: "Language", route: .language, symbol: "character.bubble") }
            #else
            settingRow("Language") { language }
            settingRow("Show Ori in the menu bar") { WorkspaceV3ActionButton(title: "Configure", action: .saveSetting, kind: .secondary) }
            Divider()
            settingRow("Default model") { WorkspaceLocalizedText(store.mode == .live ? "Compatible API" : "GigaChat") }
            settingRow("Run tasks on") { Text(store.t("This computer")) }
            settingRow("Ask before significant actions") { BlotIcon(symbol: "checkmark.shield") }
            settingRow("Keep working after closing the window") { WorkspaceV3ActionButton(title: "Configure", action: .saveSetting, kind: .secondary) }
            #endif
            Text(store.t("Ori · Version 3 preview")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
        }
    }
    private var account: some View {
        #if os(iOS)
        PhoneSettingsProfileView()
        #else
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Account", subtitle: "Profile and security")
            settingRow("Name") { Text(store.isPreview ? "Yaroslav" : store.t("Not signed in")) }
            settingRow("Email") { WorkspaceLocalizedText(store.isPreview ? "preview@blot.local" : "—") }
            settingRow("Sign-in method") { WorkspaceLocalizedText(store.isPreview ? "Google" : "—") }
            Button(store.t("Sign out")) { store.signOut() }.buttonStyle(WorkspaceButtonStyle(.secondary))
            WorkspaceV3ActionButton(title: "Delete account", action: .saveSetting, kind: .destructive)
        }
        #endif
    }
    private var models: some View {
        VStack(alignment: .leading, spacing: 24) {
            if !embedded { WorkspaceHeading(title: "Choose a model", subtitle: "Default model for new chats.") }
            #if os(macOS)
            MacTeamSettingsSection(title: "Default model for the composer") {
                MacTeamSettingsRow(title: "Model", detail: "Select a Ori model or use the model assigned to the agent.") {
                    MacComposerModelMenu()
                }
            }
            WorkspaceLocalizedText("Optional API key").font(.headline)
            #else
            WorkspaceCard {
                BlotLabel("Ori", symbol: "bubble.left").font(.headline)
                Text(store.t(store.isPreview ? "Trial access is set up. You can start without your own key." : "GigaChat connects directly from this device. The key is managed by this personal build.")).foregroundStyle(WorkspaceStyle.secondary)
            }
            Text(store.t("YOUR API KEY")).font(.caption.monospaced()).foregroundStyle(WorkspaceStyle.secondary)
            #endif
            ForEach(store.mode == .live ? ["Compatible API"] : ["OpenAI", "Anthropic", "Gemini", "xAI", "Compatible API"], id: \.self) { name in
                settingRow(name) { Button(store.t("Add key")) { keyProvider = name }.buttonStyle(WorkspaceButtonStyle(.secondary)) }
            }
            if let keyProvider {
                @Bindable var store = store
                WorkspaceCard {
                    Text(keyProvider).font(.headline)
                    if store.mode == .live {
                        WorkspaceField(title: "Chat Completions URL", text: $store.form.model.endpoint)
                        WorkspaceField(title: "Model ID", text: $store.form.model.model)
                    }
                    WorkspaceField(title: "API key", text: $store.form.model.secret, secure: true)
                    WorkspaceV3ActionButton(title: store.mode == .live ? "Save" : "Check and save", action: .saveModelKey)
                    Button(store.t("Cancel")) { self.keyProvider = nil; store.form.model.secret = "" }.buttonStyle(WorkspaceRowButtonStyle())
                }
            }
            #if os(iOS)
            Text(store.t("Existing chats keep their model. Agent settings take priority.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            #endif
        }
    }
    private var permissions: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Permissions", subtitle: "New agents start in Ask first mode.")
            WorkspaceCard {
                Text(store.t("Default mode")).font(.headline)
                WorkspaceChoice(title: store.t("Access mode"), selection: $store.form.preferences.accessMode,
                    options: [.init(.observe, store.t("Observe")), .init(.ask_first, store.t("Ask first")), .init(.trusted_scope, store.t("Trusted scope"))])
                #if os(iOS)
                WorkspaceV3ActionButton(title: "Save", action: .saveSetting, kind: .quiet)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                #else
                WorkspaceV3ActionButton(title: "Save", action: .saveSetting, kind: .secondary)
                #endif
                Text(store.t("Ori shows changes and asks before anything significant."))
            }
            WorkspaceSessionDirectoriesView()
            settingRow("Send, publish and delete") { Text(store.t("Required")) }
            WorkspaceLink(title: "Permission rules", route: .permissionRules)
                #if os(iOS)
                .background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                #endif
        }
    }
    private var connections: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Your tools", subtitle: "Give agents access to the services they need.")
            ForEach(store.snapshot.connections, id: \.metadata.id) { connection in
                HStack(spacing: 16) { BlotIcon(symbol: "powerplug").font(.title2)
                    VStack(alignment: .leading, spacing: 7) { Text(connection.service).font(.headline); Text(connection.accountName).font(.caption).foregroundStyle(WorkspaceStyle.secondary) }
                    Spacer(); BlotIcon(symbol: "checkmark.circle").accessibilityLabel(store.t("Connected")) }
            }
            ForEach(PluginCatalog.external) { plugin in
                settingRow(plugin.name) { WorkspaceV3ActionButton(title: "Connect", action: .connect, kind: .secondary) }
            }
            WorkspaceLink(title: "MCP server", route: .mcp)
            WorkspaceCard { Text(store.t("You control access")).font(.headline)
                Text(store.t("Signing in to Ori grants no service access. Each connection’s permissions can be changed or revoked.")).foregroundStyle(WorkspaceStyle.secondary) }
        }
    }
    private var visibleDevices: [BlotV3.Device] {
        #if os(macOS)
        store.snapshot.devices
        #else
        store.snapshot.devices.filter { $0.kind == .desktop }
        #endif
    }
    private var devices: some View {
        VStack(alignment: .leading, spacing: 22) {
            WorkspaceHeading(title: "Work runs on your computer", subtitle: "Choose where agents run tasks.")
            ForEach(Array(visibleDevices.enumerated()), id: \.element.metadata.id) { i, device in
                WorkspaceCard {
                    BlotLabel(device.name, symbol: "laptopcomputer").font(.headline)
                    Text(device.platform + " · " + store.t(i == 0 ? "Online" : "Offline")).foregroundStyle(WorkspaceStyle.secondary)
                    Text(store.t("Switching applies to new tasks. Running work stays on the current computer.")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                    Button(store.t("Revoke")) { store.selectedRecordID = device.metadata.id; _Concurrency.Task { await store.perform(.revokeDevice) } }
                        .buttonStyle(WorkspaceButtonStyle(.destructive)).disabled(store.busy)
                }
            }
            if store.snapshot.devices.isEmpty { WorkspaceDataState(state: .empty) }
            #if os(macOS)
            if store.isPreview {
                WorkspaceCard {
                    HStack(spacing: 22) {
                        BlotIcon(symbol: "qrcode", size: 70).font(.system(size: 70))
                        VStack(alignment: .leading, spacing: 14) {
                            Text(store.t("Pair a new device")).font(.headline)
                            Text("482 917").font(.system(.title2, design: .monospaced))
                            Text(store.t("Compare this code on both devices.")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                        }
                    }
                    HStack { WorkspaceV3ActionButton(title: "Allow", action: .connect); WorkspaceV3ActionButton(title: "Decline", action: .deny, kind: .secondary) }
                }
            }
            #endif
            #if os(iOS)
            Button { store.navigate(.pair) } label: {
                HStack {
                    Text(store.t("Connect computer"))
                    Spacer()
                    BlotIcon(.plus)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
            Button { store.navigate(.offline) } label: {
                HStack {
                    Text(store.t("Computer offline"))
                    Spacer()
                    BlotIcon(.chevronRight, size: 14)
                }.frame(maxWidth: .infinity)
            }.buttonStyle(WorkspaceButtonStyle(.secondary))
            #else
            WorkspaceLink(title: "Connect computer", route: .pair, symbol: "plus")
            WorkspaceLink(title: "Computer offline", route: .offline)
            #endif
        }
    }
    private var pair: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Link your devices", subtitle: "Open Ori on your computer: Settings → Devices → Add iPhone.")
            ZStack { RoundedRectangle(cornerRadius: 24).fill(BlotColor.inverse); BlotIcon(symbol: "viewfinder", size: 90).font(.system(size: 90)).foregroundStyle(BlotColor.onInverse) }.frame(height: 250)
            WorkspaceCard { BlotLabel(store.t("Confirm on your computer"), symbol: "checkmark.shield")
                Text(store.t("After scanning, compare the code on both devices and allow the connection in Ori on your computer.")).foregroundStyle(WorkspaceStyle.secondary) }
            WorkspaceField(title: "Connection code", text: $store.form.pair.code)
            WorkspaceV3ActionButton(title: "Connect", action: .connect)
        }
    }
    private var memory: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 22) {
            WorkspaceMemoryImportButton()
            ForEach(store.snapshot.memories, id: \.metadata.id) { item in
                WorkspaceCard { Text(store.t(item.content)); Text(store.t("Source: conversation")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                    WorkspaceMemoryReview(memory: item)
                    Button(store.t("Edit")) { editingMemoryID = item.metadata.id; store.selectedRecordID = item.metadata.id; store.form.memory.content = item.content }.buttonStyle(WorkspaceButtonStyle(.secondary))
                    if store.mode == .live {
                        Button(store.t("Delete"), role: .destructive) { store.deleteMemory(item.metadata.id) }
                    }
                    if editingMemoryID == item.metadata.id {
                        WorkspaceField(title: "Memory text", text: $store.form.memory.content, multiline: true)
                        WorkspaceV3ActionButton(title: "Save", action: .saveMemory)
                    }
                }
            }
            if store.snapshot.memories.isEmpty { WorkspaceDataState(state: .empty) }
            WorkspaceV3ActionButton(title: "Never remembered", action: .saveSetting, kind: .secondary)
        }
    }
    private var mcp: some View { WorkspaceMCPSettingsView() }
    private var browserSettings: some View { WorkspaceBrowserSettingsView() }
    private var rules: some View {
        WorkspaceRulesView()
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceChoice(title: store.t("Theme"), selection: $theme, options: [.init(.system, store.t("System")), .init(.light, store.t("Light")), .init(.dark, store.t("Dark"))])
            Toggle(store.t("Reduce Motion"), isOn: $reduceMotion)
        }
    }
    private var language: some View {
        @Bindable var store = store
        return WorkspaceChoice(title: store.t("Language"), selection: $store.languageSelection, options: [.init("system", store.t("System default")), .init("ru", "Русский"), .init("en", "English")])
    }
    private var notifications: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("Notifications need system permission. Phone reminders will work without a running computer."))
            WorkspaceV3ActionButton(title: "Configure notifications", action: .saveSetting)
        }
    }
    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                #if os(macOS)
                HStack(spacing: 9) { BlotIcon(MacSettingsCatalog.glyph(forSetting: title), size: 15); Text(store.t(title)) }
                #else
                Text(store.t(title))
                #endif
                Spacer()
                content()
            }
            Divider()
        }
    }
}
