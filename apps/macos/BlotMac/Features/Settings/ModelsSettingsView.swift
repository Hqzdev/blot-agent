import BlotDesign
import SwiftUI
import BlotAPI

struct ModelsSettingsView: View {
    @Environment(AppState.self) private var app
    @Bindable var settings: SettingsState
    @State private var key = ""
    @State private var models: [String] = []
    @State private var contextTokens = "32768"
    @State private var outputTokens = "4096"
    @State private var budget = "1000000"
    @State private var version: Int64?
    @State private var error: String?
    @State private var busy = false
    @State private var savingOptions = false
    @State private var providerManaged: Bool?
    @State private var usage = "No usage recorded"
    private nonisolated struct Options: Codable, Sendable {
        let model: String
        let contextTokens: Int
        let outputTokens: Int
        let runTokenBudget: Int64
    }
    private nonisolated struct Budget: Codable, Sendable { let limit: Int64; let reserved: Int64; let spent: Int64; let usageUnknown: Bool }
    var body: some View {
        SettingsGroup(title: "GigaChat", detail: providerManaged == true ? "Model access is provided by Blot." : nil) {
            if providerManaged == true {
                SettingsRow(title: settings.model.isEmpty ? "Default model" : settings.model,
                            detail: "You can start conversations without an API key.") {
                    StatusBadge("Connected", tone: .success)
                }
            } else if providerManaged == false {
                SettingsRow(title: "Personal API key", detail: "Stored on this Mac and used for every model request.") {
                    HStack(spacing: KSpace.sm) {
                        KTextField(text: $key, placeholder: "Paste key", secure: true, mono: true) { if !key.isEmpty { saveKey() } }
                            .frame(width: 200)
                        KButton(title: "Save key", kind: .primary, loading: busy && !key.isEmpty) { saveKey() }
                            .disabled(busy || key.isEmpty)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Model", detail: models.isEmpty ? "Save a key to load the models available to it." : "Used for new runs and conversations.") {
                    HStack(spacing: KSpace.sm) {
                        ChoiceMenu(selection: $settings.model, options: models.map { ChoiceOption(id: $0, title: $0) },
                                   placeholder: "Choose model",
                                   accessibilityTitle: "Model")
                            .disabled(models.isEmpty)
                        IconButton(icon: "rotate-ccw", help: "Reload models") { Task { await loadModels() } }
                            .disabled(busy)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "Context limit", detail: "Use the limit documented for the selected model.") {
                    KTextField(text: $contextTokens, mono: true).frame(width: 120).accessibilityLabel("Verified context limit")
                }
                SettingsDivider()
                SettingsRow(title: "Maximum response", detail: "Tokens per model response.") {
                    KTextField(text: $outputTokens, mono: true).frame(width: 120).accessibilityLabel("Maximum response tokens")
                }
                SettingsDivider()
                SettingsRow(title: "Run token budget", detail: "Default limit for a new run. A personal key has one generation queue.") {
                    KTextField(text: $budget, mono: true).frame(width: 120).accessibilityLabel("Run token budget")
                }
                SettingsDivider()
                HStack {
                    Spacer()
                    KButton(title: "Save model settings", kind: .primary, loading: savingOptions) { saveOptions() }
                        .disabled(busy || settings.model.isEmpty)
                }
                .padding(KSpace.lg)
            } else if error == nil {
                LoadingState(label: "Checking model access…")
            }
            if let error {
                GroupContent { InlineFeedback(text: error, tone: .error) }
            }
        }
        if providerManaged == false { ProviderCertificateSettingsView() }
        SettingsGroup(title: "Usage") {
            SettingsRow(title: "Recorded by the backend", detail: usage) {
                IconButton(icon: "rotate-ccw", help: "Refresh usage") { Task { await load() } }
            }
        }
        .task { await load() }
    }
    private func saveKey() {
        busy = true; error = nil
        Task {
            do {
                let client = BackendRuntime.shared.client
                try await client.put("v2/provider/key", body: ["key": key])
                key = ""
                models = try await client.get("v2/provider/models", as: [String].self)
                if !models.contains(settings.model) { settings.model = models.first ?? "" }
                app.toasts.show("Key saved · \(models.count) models available")
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
    private func loadModels() async {
        busy = true; error = nil
        defer { busy = false }
        do { models = try await BackendRuntime.shared.client.get("v2/provider/models", as: [String].self) }
        catch { self.error = error.localizedDescription }
    }
    private func saveOptions() {
        guard let context = Int(contextTokens), let output = Int(outputTokens), let tokens = Int64(budget) else {
            error = "Enter numeric token limits"; return
        }
        busy = true; savingOptions = true; error = nil
        Task {
            defer { savingOptions = false }
            do {
                let result = try await BackendRuntime.shared.client.command("provider.settings", payload: Options(model: settings.model, contextTokens: context, outputTokens: output, runTokenBudget: tokens), expectedVersion: version)
                version = try result.result.decode(BackendEntity<Options>.self).version
            } catch { self.error = error.localizedDescription }
            busy = false
            if error == nil { app.toasts.show("Model settings saved") }
        }
    }
    private func load() async {
        error = nil
        do {
            let client = BackendRuntime.shared.client
            let setup = try await client.get("v2/setup/status", as: InstallationSetup.self)
            providerManaged = setup.providerManaged
            if let options = setup.modelSettings {
                settings.model = options.model
                contextTokens = String(options.contextTokens)
                outputTokens = String(options.outputTokens)
                budget = String(options.runTokenBudget)
                models = [options.model]
            }
            if providerManaged == false {
                let saved = try await client.get("v2/records/PROVIDER_SETTINGS", as: [BackendEntity<Options>].self)
                if let row = saved.first { settings.model = row.data.model; version = row.version; contextTokens = String(row.data.contextTokens); outputTokens = String(row.data.outputTokens); budget = String(row.data.runTokenBudget); models = [row.data.model] }
            }
            let budgets = try await client.get("v2/records/BUDGET", as: [BackendEntity<Budget>].self)
            if let total = budgets.first(where: { $0.parentId == nil }) { usage = "Spent: \(total.data.spent) · reserved: \(total.data.reserved) · limit: \(total.data.limit)" + (total.data.usageUnknown ? " · some usage is unknown" : "") }
        } catch { self.error = error.localizedDescription }
    }
}
