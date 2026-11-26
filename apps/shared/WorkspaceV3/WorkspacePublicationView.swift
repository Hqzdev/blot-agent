import BlotDesign
import BlotWorkspace
import SwiftUI

@MainActor protocol WorkspaceCollaborationProviding {
    func collaborationClient() -> WorkspaceCollaborationClient
    func teamBotStatus() async -> String?
}
extension WorkspaceAccountApplicationService: WorkspaceCollaborationProviding {}

struct WorkspacePublishButton: View {
    let kind: String
    let title: String
    let data: Data
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: { BlotLabel(store.language == "ru" ? "Ссылка на снимок" : "Share snapshot link", symbol: "link") }
            .disabled(store.collaborationCommands == nil)
            .workspacePanelSheet(isPresented: $showing) { WorkspacePublishView(kind: kind, title: title, data: data).environment(store) }
    }
}
private struct WorkspacePublishView: View {
    let kind: String; let title: String; let data: Data
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var days = 7
    @State private var link: URL?
    @State private var publication: WorkspacePublicationLink?
    @State private var working = false
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        NavigationStack {
            WorkspacePanelForm {
                Text(title).font(.title2)
                Text(ru ? "По ссылке будет доступна текущая копия содержимого любому, у кого есть ссылка. История, чат и подключения не публикуются. Изменения исходной страницы не меняют опубликованную копию." : "Anyone with the link can read this content snapshot. History, chat and connections are excluded. Later edits do not change the published snapshot.").foregroundStyle(.secondary)
                if let link {
                    ShareLink(item: link)
                    Text(link.absoluteString).font(.caption).textSelection(.enabled)
                    if let publication { Text(publication.expiresAt).font(.caption) }
                    Button(ru ? "Отозвать ссылку" : "Revoke link", role: .destructive) { revoke() }
                } else {
                    WorkspaceChoice(title: ru ? "Срок доступа" : "Expires after", selection: $days, options: [1, 7, 30].map { .init($0, ru ? "\($0) дн." : "\($0) days") })
                    Button(ru ? "Создать ссылку" : "Create link") { publish() }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }.disabled(working)

            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: ru ? "Поделиться" : "Share") {
                    Button(store.t("Close")) { dismiss() }.disabled(working)
                }
            }.workspaceEditorChrome()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 360)
        #endif
    }
    private func publish() { perform { client in let result = try await client.publish(kind: kind, title: title, data: data, days: days); publication = result; link = try await client.link(result) } }
    private func revoke() { guard let publication else { return }; perform { try await $0.revoke(publication.id); link = nil; self.publication = nil } }
    private func perform(_ action: @escaping @MainActor (WorkspaceCollaborationClient) async throws -> Void) {
        guard !working, let commands = store.collaborationCommands else { return }; working = true; failure = nil
        _Concurrency.Task {
            defer { working = false }
            do { try await action(commands.collaborationClient()) }
            catch { failure = ru ? "Сервер не создал или не изменил публикацию. Проверьте соединение и версию облачного сервиса." : "Publication failed. Check connectivity and the cloud service version." }
        }
    }
}

struct WorkspacePublicationsButton: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var showing = false
    var body: some View {
        Button(store.language == "ru" ? "Опубликованные ссылки" : "Published links") { showing = true }
            .disabled(store.collaborationCommands == nil)
            .workspacePanelSheet(isPresented: $showing) { WorkspacePublicationsView().environment(store) }
    }
}
private struct WorkspacePublicationsView: View {
    @Environment(WorkspaceStore.self) private var store
    @WorkspacePresentationDismiss private var dismiss
    @State private var items: [WorkspacePublicationSummary] = []
    @State private var failure: String?
    @State private var working = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(items) { item in
                        WorkspaceCard {
                            Text(item.title).font(.headline); Text(item.expiresAt).font(.caption)
                            if item.revoked { Text(store.language == "ru" ? "Доступ отозван" : "Revoked").foregroundStyle(.secondary) }
                            else { Button(store.language == "ru" ? "Отозвать" : "Revoke", role: .destructive) { revoke(item) }.disabled(working) }
                        }
                    }
                    if let failure { Text(failure).foregroundStyle(.red) }
                }.padding(24)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                WorkspacePanelFormHeader(title: store.language == "ru" ? "Публикации" : "Publications") {
                    Button(store.t("Close")) { dismiss() }
                }
            }.workspaceEditorChrome()
        }.task { await reload() }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }
    private func reload() async { do { items = try await store.collaborationCommands?.collaborationClient().publications() ?? [] } catch { failure = WorkspaceFailureCopy.message(error) } }
    private func revoke(_ item: WorkspacePublicationSummary) {
        guard !working, let commands = store.collaborationCommands else { return }; working = true
        _Concurrency.Task { defer { working = false }; do { try await commands.collaborationClient().revoke(item.id); await reload() } catch { failure = WorkspaceFailureCopy.message(error) } }
    }
}
