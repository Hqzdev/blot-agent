import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceSettingsView: View {
    let route: WorkspaceRoute
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
            HStack(spacing: 10) {
                BlotIcon(MacSettingsCatalog.glyph(for: route), size: 22)
                Text(store.t(route.title)).font(.system(size: 24, weight: .semibold)).accessibilityAddTraits(.isHeader)
            }
            #endif
            if !store.unresolvedConflicts.isEmpty {
                Button { store.conflictsVisible = true } label: {
                    Label(store.t("Review conflicting changes"), systemImage: "arrow.triangle.branch")
                }.buttonStyle(WorkspaceButtonStyle(.secondary))
            }
            content
            WorkspaceFeedback()
        }
    }
    @ViewBuilder private var content: some View {
        switch route {
        case .account: account
        case .models: models
        case .permissions: permissions
        case .connections: connections
        case .devices: devices
        case .pair: pair
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
            settingRow("Show Blot in the menu bar") { WorkspaceV3ActionButton(title: "Configure", action: .saveSetting, kind: .secondary) }
            Divider()
            settingRow("Default model") { Text(store.mode == .live ? "Compatible API" : "GigaChat") }
            settingRow("Run tasks on") { Text(store.t("This computer")) }
            settingRow("Ask before significant actions") { BlotIcon(symbol: "checkmark.shield") }
            settingRow("Keep working after closing the window") { WorkspaceV3ActionButton(title: "Configure", action: .saveSetting, kind: .secondary) }
            #endif
            Text(store.t("Blot · Version 3 preview")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
        }
    }
    private var account: some View {
        #if os(iOS)
        PhoneAccountSettingsView()
        #else
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Account", subtitle: "Profile and security")
            settingRow("Name") { Text(store.isPreview ? "Yaroslav" : store.t("Not signed in")) }
            settingRow("Email") { Text(store.isPreview ? "preview@blot.local" : "—") }
            settingRow("Sign-in method") { Text(store.isPreview ? "Google" : "—") }
            Button(store.t("Sign out")) { store.signOut() }.buttonStyle(WorkspaceButtonStyle(.secondary))
            WorkspaceV3ActionButton(title: "Delete account", action: .saveSetting, kind: .destructive)
        }
        #endif
    }
    private var models: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Choose a model", subtitle: "Default model for new chats.")
            WorkspaceCard {
                BlotLabel("GigaChat", symbol: "bubble.left").font(.headline)
                Text(store.t(store.isPreview ? "Trial access is set up. You can start without your own key." : "Public beta: add your own compatible API key below and select Compatible API in your agent settings. Personal development builds may include managed GigaChat access.")).foregroundStyle(WorkspaceStyle.secondary)
            }
            Text(store.t("YOUR API KEY")).font(.caption.monospaced()).foregroundStyle(WorkspaceStyle.secondary)
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
            Text(store.t("Existing chats keep their model. Agent settings take priority.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
        }
    }
    private var permissions: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Permissions", subtitle: "New agents start in Ask first mode.")
            WorkspaceCard {
                Text(store.t("Default mode")).font(.headline)
                Picker(store.t("Access mode"), selection: $store.form.preferences.accessMode) {
                    Text(store.t("Observe")).tag(BlotV3.AccessMode.observe)
                    Text(store.t("Ask first")).tag(BlotV3.AccessMode.ask_first)
                    Text(store.t("Trusted scope")).tag(BlotV3.AccessMode.trusted_scope)
                }.pickerStyle(.segmented)
                #if os(iOS)
                WorkspaceV3ActionButton(title: "Save", action: .saveSetting, kind: .quiet)
                    .background(WorkspaceStyle.canvas, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                #else
                WorkspaceV3ActionButton(title: "Save", action: .saveSetting, kind: .secondary)
                #endif
                Text(store.t("Blot shows changes and asks before anything significant."))
            }
            settingRow("Allowed folders") { Text("Blot Workspace") }
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
                Text(store.t("Signing in to Blot grants no service access. Each connection’s permissions can be changed or revoked.")).foregroundStyle(WorkspaceStyle.secondary) }
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
            WorkspaceHeading(title: "Link your devices", subtitle: "Open Blot on your computer: Settings → Devices → Add iPhone.")
            ZStack { RoundedRectangle(cornerRadius: 24).fill(BlotColor.inverse); BlotIcon(symbol: "viewfinder", size: 90).font(.system(size: 90)).foregroundStyle(BlotColor.onInverse) }.frame(height: 250)
            WorkspaceCard { BlotLabel(store.t("Confirm on your computer"), symbol: "checkmark.shield")
                Text(store.t("After scanning, compare the code on both devices and allow the connection in Blot on your computer.")).foregroundStyle(WorkspaceStyle.secondary) }
            WorkspaceField(title: "Connection code", text: $store.form.pair.code)
            WorkspaceV3ActionButton(title: "Connect", action: .connect)
        }
    }
    private var memory: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 22) {
            ForEach(store.snapshot.memories, id: \.metadata.id) { item in
                WorkspaceCard { Text(store.t(item.content)); Text(store.t("Source: conversation")).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
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
    private var mcp: some View {
        @Bindable var store = store
        return VStack(alignment: .leading, spacing: 22) {
            WorkspaceHeading(title: "MCP servers", subtitle: "Add a server, inspect its tools and choose allowed access.")
            ForEach(store.snapshot.mcpConnections, id: \.metadata.id) { connection in
                WorkspaceCard {
                    HStack { Text(connection.name).font(.headline); Spacer(); Text(store.t(connection.state == .connected ? "Connected" : connection.state == .error ? "Reconnect" : "Not connected")).font(.caption) }
                    Text(connection.endpoint).font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                    ForEach(connection.toolIds, id: \.self) { tool in BlotLabel(tool, symbol: "checkmark.shield") }
                }
            }
            WorkspaceField(title: "Server name", text: $store.form.mcp.name)
            WorkspaceField(title: "Server URL", text: $store.form.mcp.endpoint)
            Picker(store.t("Transport"), selection: $store.form.mcp.transport) {
                Text("Streamable HTTP").tag("STREAMABLE_HTTP")
                Text("stdio").tag("STDIO")
            }.pickerStyle(.segmented)
            Text(store.t("Transports: stdio on computer · Streamable HTTP")).foregroundStyle(WorkspaceStyle.secondary)
            Text(store.t("Secrets belong in protected settings and never in prompts.")).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            WorkspaceV3ActionButton(title: "Add server", action: .addMcp)
        }
    }
    private var browserSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Blot for Chrome", subtitle: "Connect your browser on this computer.")
            settingRow("Chrome extension") { Text(store.t(store.isPreview ? "Connected" : "Not connected")) }
            settingRow("Allowed sites") { Text("mailerlite.com\nmail.google.com") }
            settingRow("Pause on CAPTCHA, 2FA and sign-in") { Text(store.t("Always")) }
            WorkspaceV3ActionButton(title: "Stop access", action: .saveSetting, kind: .destructive)
            WorkspaceLink(title: "View browser", route: .browser)
        }
    }
    private var rules: some View {
        VStack(alignment: .leading, spacing: 24) {
            WorkspaceHeading(title: "Permission rules", subtitle: "Saved rules apply only to their exact operation and scope.")
            if store.isPreview {
                ForEach(["Create reports", "Read calendar", "Send email", "Run tests"], id: \.self) { title in
                    settingRow(title) { WorkspaceV3ActionButton(title: "Revoke", action: .saveSetting, kind: .destructive) }
                }
            } else { WorkspaceDataState(state: .empty) }
            Text(store.t("Push, delete, publish and deploy always require a separate confirmation by default.")).foregroundStyle(WorkspaceStyle.secondary)
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker(store.t("Theme"), selection: $theme) {
                Text(store.t("System")).tag(ThemePreference.system)
                Text(store.t("Light")).tag(ThemePreference.light)
                Text(store.t("Dark")).tag(ThemePreference.dark)
            }.pickerStyle(.segmented)
            Toggle(store.t("Reduce Motion"), isOn: $reduceMotion)
        }
    }
    private var language: some View {
        @Bindable var store = store
        return Picker(store.t("Language"), selection: $store.language) { Text("Русский").tag("ru"); Text("English").tag("en") }.pickerStyle(.segmented)
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
