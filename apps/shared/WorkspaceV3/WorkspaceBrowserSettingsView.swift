import BlotDomain
import BlotAppleIntegrations
import BlotWorkspace
import SwiftUI

struct WorkspaceBrowserSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var origins = ""
    @State private var agents: Set<UUID> = []
    @State private var busy = false
    @State private var error: String?
    @State private var saved = false
    @State private var resolving: UUID?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        if store.browserCommands?.automaticBrowserAccess == true {
            VStack(alignment: .leading, spacing: 16) {
                Text(ru ? "Браузер Blot" : "Blot browser").font(.title2.bold())
                Text(ru ? "Агенты могут сразу открывать сайты и читать открытые вами вкладки. Настраивать доступ для каждого сайта не нужно." : "Agents can open websites and read your open tabs immediately. No per-site access setup is needed.")
                Text(ru ? "Пароли, коды входа и платёжные поля вводите вручную. Нажатия и ввод агента подтверждаются отдельно." : "Enter passwords, sign-in codes and payment details manually. Agent clicks and typing require separate confirmation.").foregroundStyle(.secondary)
                Button(ru ? "Открыть браузер" : "Open browser") { store.showBrowser() }
                automaticRecovery
            }
        } else { configuredSettings }
    }
    private var automaticRecovery: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(unknownInvocations, id: \.metadata.id) { invocation in
                Text(ru ? "Исход действия неизвестен. Проверьте сайт перед продолжением." : "Action outcome unknown. Check the website before continuing.")
                Button(ru ? "Я проверил результат…" : "I verified the result…") { resolving = invocation.metadata.id }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .confirmationDialog(ru ? "Подтвердите проверенный результат" : "Confirm the verified outcome", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
            Button(ru ? "Выполнено" : "Completed") { resolve(true) }
            Button(ru ? "Не выполнено" : "Not completed") { resolve(false) }
        }
    }
    private var configuredSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(ru ? "Браузер Blot" : "Blot browser").font(.title2.bold())
            Text(ru ? "Сайты открываются внутри приложения. Разрешения ниже действуют только для агентов на этом устройстве. Нажатия и ввод подтверждаются отдельно." : "Websites open inside the app. These agent permissions apply only on this device. Clicks and typing require separate confirmation.").foregroundStyle(.secondary)
            Button(ru ? "Открыть браузер" : "Open browser") { store.showBrowser() }.disabled(store.browserCommands == nil)
            Text(ru ? "Разрешённые сайты — по одному HTTPS-адресу на строку" : "Allowed sites — one HTTPS address per line").font(.headline)
            TextEditor(text: $origins).font(.body.monospaced()).frame(minHeight: 90, maxHeight: 180).border(.secondary.opacity(0.3))
            Text("https://example.com").font(.caption).foregroundStyle(.secondary)
            if let url = store.browser?.selectedTab?.url, let origin = try? WorkspaceBrowserURL.origin(url) {
                Button(ru ? "Добавить текущий сайт и агентов чата" : "Add current site and chat agents") {
                    var values = Set(origins.split(whereSeparator: \.isNewline).map(String.init)); values.insert(origin)
                    origins = values.sorted().joined(separator: "\n")
                    if let chat = store.currentConversation {
                        if chat.kind == .group {
                            agents.formUnion((store.snapshot.participants ?? []).filter { $0.conversationId == chat.metadata.id && !$0.removed && $0.kind == .agent }.map(\.participantId))
                        } else if let id = chat.agentId { agents.insert(id) }
                    }
                    saved = false
                }
                Text(ru ? "После выбора нажмите «Сохранить доступ». Агент сможет прочитать выбранную вкладку этого сайта; значения полей не передаются." : "Then choose Save access. The agent can read the selected tab on this site; field values are excluded.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(store.snapshot.agents, id: \.metadata.id) { agent in
                Toggle(agent.name, isOn: Binding(get: { agents.contains(agent.metadata.id) }, set: { if $0 { agents.insert(agent.metadata.id) } else { agents.remove(agent.metadata.id) } }))
            }
            HStack {
                Button(ru ? "Сохранить доступ" : "Save access") { save(revoke: false) }
                Button(ru ? "Отозвать весь доступ" : "Revoke all access", role: .destructive) { save(revoke: true) }
            }.disabled(busy || store.browserCommands == nil)
            if saved { Text(ru ? "Сохранено на этом устройстве" : "Saved on this device").font(.caption).foregroundStyle(.secondary) }
            if let error { Text(error).foregroundStyle(.red) }
            ForEach(unknownInvocations, id: \.metadata.id) { invocation in
                VStack(alignment: .leading, spacing: 8) {
                    Text(ru ? "Исход действия неизвестен" : "Action outcome unknown").font(.headline)
                    Text(ru ? "Сначала проверьте сайт. Подтверждение ниже фиксирует результат без повторного действия." : "Check the website first. This records your verified result without repeating the action.").font(.caption)
                    Button(ru ? "Я проверил результат…" : "I verified the result…") { resolving = invocation.metadata.id }
                }
            }
            Text(ru ? "Cookies не передаются модели или другим устройствам. На Mac активны не более двух WebView, на iPhone — одного. Несохранённые формы не выгружаются молча." : "Cookies are not shared with the model or other devices. Up to two WebViews on Mac and one on iPhone stay live. Unsaved forms are not silently unloaded.").font(.caption).foregroundStyle(.secondary)
        }
        .task {
            do {
                guard let commands = store.browserCommands else { return }
                let value = try await commands.browserService().settings(); agents = value.agents; origins = value.origins.sorted().joined(separator: "\n")
            } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog(ru ? "Подтвердите проверенный результат" : "Confirm the verified outcome", isPresented: Binding(get: { resolving != nil }, set: { if !$0 { resolving = nil } }), titleVisibility: .visible) {
            Button(ru ? "Выполнено" : "Completed") { resolve(true) }
            Button(ru ? "Не выполнено" : "Not completed") { resolve(false) }
        }
    }
    private var unknownInvocations: [BlotV3.ToolInvocation] {
        let actions = Set((store.snapshot.preparedActions ?? []).filter { $0.toolId.hasPrefix("browser_") }.map(\.metadata.id))
        return (store.snapshot.toolInvocations ?? []).filter { $0.state == .unknown && $0.execution.executorDeviceId == store.snapshot.localDeviceID && actions.contains($0.preparedActionId) }
    }
    private func resolve(_ succeeded: Bool) {
        guard let id = resolving, let commands = store.browserCommands else { return }; resolving = nil
        _Concurrency.Task {
            do { try await commands.browserService().resolve(invocationID: id, succeeded: succeeded); try await store.refreshMCP() }
            catch { self.error = error.localizedDescription }
        }
    }
    private func save(revoke: Bool) {
        guard let commands = store.browserCommands else { return }; busy = true; saved = false; error = nil
        _Concurrency.Task {
            defer { busy = false }
            do {
                let values = Set(origins.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
                try await commands.browserService().configure(agents: revoke ? [] : agents, origins: revoke ? [] : values)
                if revoke { agents = []; origins = "" }
                try await store.refreshMCP(); saved = true
            } catch { self.error = error.localizedDescription }
        }
    }
}
