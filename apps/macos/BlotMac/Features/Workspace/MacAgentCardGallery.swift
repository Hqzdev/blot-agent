import BlotDesign
import BlotDomain
import BlotWorkspace
import SwiftUI

/// A separate, in-memory chat using the production card views and no account services.
struct MacAgentCardGallery: View {
    @State private var store: WorkspaceStore?
    @State private var failure: String?
    var body: some View {
        Group {
            if let store {
                MacLiveTeamWorkspace().environment(store)
                    .environment(\.workspaceCardDemonstration, true)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Text("Демочат · 14 видов карточек. Кнопки примеров отключены; рабочие чаты и подключения не используются.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(12).background(WorkspaceStyle.surface)
                    }
            } else if let failure { Text(failure).padding(24) }
            else { ProgressView() }
        }
        .blotTheme(.light).environment(\.colorScheme, .light)
        .frame(minWidth: 800, minHeight: 600)
        .task {
            guard store == nil else { return }
            do { store = try MacAgentCardGalleryData.makeStore() }
            catch { failure = "Не удалось открыть примеры карточек." }
        }
    }
}

@MainActor
private enum MacAgentCardGalleryData {
    static func makeStore() throws -> WorkspaceStore {
        let base = WorkspaceStore(mode: .preview, route: .chat)
        guard let original = base.snapshot.agents.first, let originalChat = base.snapshot.conversations.first else {
            throw WorkspaceStorageError.missingRecord
        }
        let owner = original.metadata.ownerId, workspace = original.metadata.workspaceId
        let device = UUID(), connection = UUID(), now = Date()
        func metadata(_ id: UUID, offset: TimeInterval = 0) throws -> BlotV3.RecordMetadata {
            try .init(id: id, ownerId: owner, workspaceId: workspace, version: 1,
                createdAt: now.addingTimeInterval(offset), updatedAt: now.addingTimeInterval(offset))
        }
        let agent = try BlotV3.AgentProfile(metadata: metadata(original.metadata.id), name: "Все карточки агента",
            roleId: "custom", avatarShape: original.avatarShape, avatarColor: original.avatarColor,
            instructions: "Демонстрация интерфейса", modelId: original.modelId, accessMode: original.accessMode)
        let chat = try BlotV3.Conversation(metadata: metadata(originalChat.metadata.id), agentId: agent.metadata.id,
            title: "Демо — карточки агента", mobileOwned: false, pinned: true, archived: false, kind: .direct)
        let draft = WorkspaceCardContent.MailDraft(sender: "demo@example.com", recipient: "team@example.com",
            subject: "Встреча по проекту Орион", body: "Коллеги, предлагаю обсудить результаты завтра в 14:00. Подтвердите, пожалуйста, удобное время.")
        guard let checkout = URL(string: "https://example.com/demo-checkout"), let pullRequest = URL(string: "https://example.com/demo-pull-request") else {
            throw WorkspaceStorageError.invalidParameters
        }
        let samples: [(String, WorkspaceCardContent)] = [
            ("1. Уточняющий вопрос: выбор варианта или свой ответ.", .question(.init(prompt: "С чего начать работу?", choices: ["Подготовить отчёт", "Разобрать задачи", "Проверить календарь"]))),
            ("2. Подключение приложения: агент ждёт вашего решения.", .connectionRequest(.init(pluginID: "drive", name: "Google Drive", reason: "Сохранить отчёт в выбранную вами папку.", agentID: agent.metadata.id))),
            ("3. Статус установленного плагина и его возможностей.", .plugin(.init(name: "Notion", detail: "Страницы и базы данных. Демонстрация статуса подключения.", connectionID: connection))),
            ("4. Защищённый ввод ключа сервиса, без отправки ключа в чат.", .credential(.init(name: "Тестовый сервис", purpose: "Введите API-ключ в защищённом поле.", reference: "demo:service"))),
            ("5. Черновик письма: просмотр, редактирование, подтверждение отправки.", .email(draft)),
            ("6. Неопределённый результат отправки письма: требуется сверка.", .mailFailure(.init(draft: draft, detail: "Сервис не подтвердил отправку. Проверьте папку «Отправленные» перед повтором.", outcomeUnknown: true))),
            ("7. Черновик сообщения в Slack.", .slack(.init(workspace: "Демо-команда", channel: "#проект-орион", thread: nil, body: "Дизайн готов. Разработка идёт по плану; проверку начинаем завтра."))),
            ("8. Разрешение на команду: один раз, правило или отказ.", .command(.init(title: "Запустить проверку проекта", details: "Агент предлагает выполнить тесты в выбранном проекте.", command: "swift test", ruleScope: "Демо-проект"))),
            ("9. Передача управления браузером пользователю.", .takeover(.init(reason: "Завершите вход на сайте, затем верните управление агенту.", tabID: device))),
            ("10. Перенос браузерной сессии: выбор доменов.", .cookies(.init(sourceProfileID: owner, destinationProfileID: device, domains: ["example.com", "example.org"]))),
            ("11. Покупка агентом: позиции, сумма и переход к оплате.", .purchase(.init(merchant: "Демо-магазин", checkoutURL: checkout, currency: "RUB", items: [.init(title: "Блокнот", quantity: 2, unitAmountMinor: 45000)], taxMinor: 0, deliveryMinor: 20000, totalMinor: 110000))),
            ("12. Подписка Ori и выбор тарифа.", .subscription(.init(checkoutURL: checkout))),
            ("13. Созданная страница или документ.", .page(.init(id: UUID(), title: "Итоги проекта Орион"))),
            ("14. Результат задачи: файлы, изменения, ветка и ссылка.", .task(.init(title: "Проверка интерфейса завершена", branch: "mac/demo-interface", files: ["ChatView.swift", "ChatViewTests.swift"], pullRequestURL: pullRequest, additions: 48, deletions: 12)))
        ]
        var snapshot = WorkspaceSnapshot()
        snapshot.ownerID = owner; snapshot.localDeviceID = device
        snapshot.agents = [agent]; snapshot.conversations = [chat]
        snapshot.mcpConnections = [try .init(metadata: metadata(connection), name: "Notion", transport: "STREAMABLE_HTTP",
            endpoint: "device:demonstration", toolIds: [], state: .disconnected)]
        let intro = UUID()
        snapshot.messages = [try .init(metadata: metadata(intro), conversationId: chat.metadata.id, role: .user,
            content: "Покажи все виды окон и карточек, которые агент может отправить в чат.", delivery: .completed, commandId: intro, artifactIds: [])]
        snapshot.cards = []
        for (index, sample) in samples.enumerated() {
            let id = UUID(), operation = UUID()
            snapshot.messages.append(try .init(metadata: metadata(id, offset: Double(index + 1)), conversationId: chat.metadata.id,
                role: .assistant, content: sample.0, delivery: .completed, commandId: intro, artifactIds: [], authorAgentId: agent.metadata.id))
            snapshot.cards?.append(try .init(metadata: metadata(UUID(), offset: Double(index + 1)), messageId: id,
                operationId: operation, executorDeviceId: device, kind: sample.1.kind, state: "pending",
                expiresAt: nil, payloadJSON: String(decoding: JSONEncoder().encode(sample.1), as: UTF8.self),
                responseJSON: nil, updatedByDeviceId: device))
        }
        let store = WorkspaceStore(mode: .preview, route: .chat, previewSnapshot: snapshot)
        store.language = "ru"; store.selectedConversationID = chat.metadata.id; store.selectedAgentID = agent.metadata.id
        return store
    }
}
