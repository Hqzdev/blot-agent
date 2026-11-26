import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceRuleProviding { func ruleService() async throws -> WorkspaceRuleService }
extension LocalWorkspaceService: WorkspaceRuleProviding {
    func ruleService() async throws -> WorkspaceRuleService { .init(repository: repository, identity: try await context()) }
}
extension WorkspaceAccountApplicationService: WorkspaceRuleProviding {
    func ruleService() async throws -> WorkspaceRuleService {
        guard let local = workspaceCommands as? LocalWorkspaceService else { throw WorkspaceServiceError.unavailable }
        return try await local.ruleService()
    }
}

struct WorkspaceRulesView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var rules: [WorkspaceCustomRule] = []
    @State private var editing: WorkspaceCustomRule?
    @State private var deleting: WorkspaceCustomRule?
    @State private var failure: String?
    @State private var working = false
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(ru ? "Правила действий" : "Action rules").font(.headline)
                Spacer()
                Button(ru ? "Добавить" : "Add") { editing = .init(name: "", toolID: "") }.disabled(working || store.ruleCommands == nil)
            }
            Text(ru ? "«Спрашивать» имеет приоритет над автоматическим разрешением. Правило не выдаёт агенту доступ к неподключённым инструментам. Покупка всегда требует отдельного подтверждения." : "Ask first overrides automatic approval. Rules never grant access to unconnected tools. Purchases always require separate approval.")
                .font(.caption).foregroundStyle(.secondary)
            if rules.isEmpty { Text(ru ? "Сохранённых правил пока нет." : "No saved rules yet.").foregroundStyle(.secondary) }
            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(rule.name).fontWeight(.medium)
                        Text(rule.toolID + (rule.resource.isEmpty ? "" : " · " + rule.resource)).font(.caption).foregroundStyle(.secondary)
                        Text(rule.decision == .askFirst ? (ru ? "Спрашивать" : "Ask first") : (ru ? "Разрешать автоматически" : "Allow automatically")).font(.caption)
                    }
                    Spacer()
                    Button(store.t("Edit")) { editing = rule }
                    Button(store.t("Delete"), role: .destructive) { deleting = rule }
                }.padding(12).background(WorkspaceStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }
        .disabled(working)
        .task { await refresh() }
        .workspacePanelSheet(item: $editing) { rule in
            WorkspaceRuleEditor(rule: rule) { await refresh() }.environment(store)
        }
        .workspaceConfirmationDialog(ru ? "Удалить правило?" : "Delete rule?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(store.t("Delete"), role: .destructive) {
                guard let rule = deleting else { return }
                _Concurrency.Task {
                    working = true; defer { working = false }
                    do { try await store.ruleCommands?.ruleService().delete(rule); await refresh() }
                    catch { failure = WorkspaceFailureCopy.message(error) }
                }
            }
            Button(store.t("Cancel"), role: .cancel) {}
        }
    }
    private func refresh() async {
        do { rules = try await store.ruleCommands?.ruleService().rules() ?? []; failure = nil }
        catch { failure = WorkspaceFailureCopy.message(error) }
    }
}

private struct WorkspaceRuleEditor: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State var rule: WorkspaceCustomRule
    let saved: @MainActor () async -> Void
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    private var tools: [String] { Set((store.snapshot.configurations ?? []).flatMap(\.toolIds) + [rule.toolID]).filter { !$0.isEmpty }.sorted() }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                TextField(store.t("Name"), text: $rule.name)
                WorkspaceChoice(title: ru ? "Инструмент" : "Tool", selection: $rule.toolID, options: [.init("", store.t("Not selected"))] + tools.map { .init($0, $0) })
                WorkspaceChoice(title: store.t("Agent"), selection: $rule.agentID, options: [.init(nil, ru ? "Все агенты" : "All agents")] + store.snapshot.agents.map { .init(Optional($0.metadata.id), $0.name) })
                WorkspaceChoice(title: ru ? "Решение" : "Decision", selection: $rule.decision, options: [.init(.askFirst, ru ? "Спрашивать" : "Ask first"), .init(.allowAutomatically, ru ? "Разрешать автоматически" : "Allow automatically")])
                TextField(ru ? "Сайт или ресурс (необязательно)" : "Site or resource (optional)", text: $rule.resource)
                Text(ru ? "Для браузера: https://example.com. Для MCP: ID подключения; для проекта: project:ID. Пустое поле — все разрешённые ресурсы этого инструмента." : "Browser: https://example.com. MCP: connection ID; project: project:ID. Empty means every authorized resource for this tool.").font(.caption).foregroundStyle(.secondary)
                if let failure { Text(failure).foregroundStyle(.red) }
            }

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Правило действий" : "Action rule") {
                    Button(store.t("Cancel")) { dismiss() }.disabled(working)
                    Button(store.t("Save")) {
                        guard let commands = store.ruleCommands else { return }
                        working = true
                        _Concurrency.Task {
                            defer { working = false }
                            do { try await commands.ruleService().save(rule); await saved(); dismiss() }
                            catch { failure = WorkspaceFailureCopy.message(error) }
                        }
                    }.buttonStyle(WorkspaceButtonStyle(.primary)).disabled(working || rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || rule.toolID.isEmpty)
                }
            }.workspaceEditorChrome()
        }.interactiveDismissDisabled(working)
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
}
