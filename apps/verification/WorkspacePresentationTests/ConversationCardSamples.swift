import BlotDomain
import BlotWorkspace
import Foundation

/// Isolated UI samples. They never connect to the owner's account or execute external actions.
@MainActor
enum ConversationCardSamples {
    struct Sample {
        let reference: String
        let content: WorkspaceCardContent
        var name: String { content.kind }
    }
    static let owner = UUID(uuidString: "63000000-0000-4000-8000-000000000001")!
    static let device = UUID(uuidString: "63000000-0000-4000-8000-000000000002")!
    static let connection = UUID(uuidString: "63000000-0000-4000-8000-000000000003")!
    static let draft = WorkspaceCardContent.MailDraft(sender: "peng@example.org", recipient: "sarah@example.org",
        subject: "Moving Friday’s design review to 2 PM",
        body: "Hi Sarah,\n\nCould we move Friday’s design review from 11 AM to 2 PM? A client call came up and I don’t want to rush our discussion.\n\nThanks,\nPeng")

    static func samples() throws -> [Sample] {
        guard let checkout = URL(string: "https://blot-agent.vercel.app/app/pricing"), let pullRequest = URL(string: "https://example.org/pull/42") else { throw WorkspaceStorageError.invalidParameters }
        return [
            .init(reference: "blot-purchase", content: .purchase(.init(merchant: "Fixture shop", checkoutURL: checkout, currency: "RUB", items: [.init(title: "Book", quantity: 2, unitAmountMinor: 125000)], taxMinor: 0, deliveryMinor: 30000, totalMinor: 280000))),
            .init(reference: "blot-page", content: .page(.init(id: owner, title: "Weekly project report"))),
            .init(reference: "09-widget-01", content: .email(draft)),
            .init(reference: "09-widget-02", content: .question(.init(prompt: "What do you want me handling first?", choices: ["Work", "Life / admin", "A specific project"]))),
            .init(reference: "09-widget-03", content: .subscription(.init(checkoutURL: checkout))),
            .init(reference: "09-widget-04", content: .command(.init(title: "Run a command", details: "Run the project's test suite on this Mac.", command: "/usr/bin/make test", ruleScope: "Design review"))),
            .init(reference: "09-widget-05", content: .takeover(.init(reason: "Open the billing dashboard and export last month’s invoices.", tabID: device))),
            .init(reference: "09-widget-06", content: .task(.init(title: "Refactor the auth flow to use the new token exchange and update tests.", branch: "jan-refactor-auth-token-exchange", files: ["AuthService.swift", "AuthView.swift", "AuthTests.swift"], pullRequestURL: pullRequest, additions: 128, deletions: 14))),
            .init(reference: "09-widget-07", content: .slack(.init(workspace: "Acme Design", channel: "#design-team", thread: "New message", body: "Hey team 👋\n\nCould we move Friday’s design review from 11 AM to 2 PM? A client call came up and I don’t want to rush our discussion."))),
            .init(reference: "09-widget-08", content: .plugin(.init(name: "Notion", detail: "Read and write pages and databases", connectionID: connection))),
            .init(reference: "09-widget-09", content: .credential(.init(name: "API key", purpose: "Add the service token to continue.", reference: "card:fixture"))),
            .init(reference: "09-widget-10", content: .cookies(.init(sourceProfileID: owner, destinationProfileID: device, domains: ["example.org", "example.com"]))),
            .init(reference: "09-widget-11", content: .mailFailure(.init(draft: draft, detail: "Mail didn't confirm sending. Your draft is saved.", outcomeUnknown: true))),
        ]
    }
    static func card(_ sample: Sample, index: Int, state: String = "pending", response: WorkspaceCardResponse? = nil) throws -> BlotV3.ConversationCard {
        let id = UUID(uuidString: String(format: "63000000-0000-4000-8000-%012d", 100 + index))!
        let now = Date()
        return try .init(metadata: metadata(id: id), messageId: id, operationId: id, executorDeviceId: device,
            kind: sample.name, state: state, expiresAt: now.addingTimeInterval(3600),
            payloadJSON: String(decoding: JSONEncoder().encode(sample.content), as: UTF8.self),
            responseJSON: try response.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) }, updatedByDeviceId: device)
    }
    static func store() throws -> WorkspaceStore {
        var snapshot = WorkspaceSnapshot()
        snapshot.ownerID = owner; snapshot.localDeviceID = device
        snapshot.mcpConnections = [try .init(metadata: metadata(id: connection), name: "Notion", transport: "STREAMABLE_HTTP", endpoint: "device:fixture", toolIds: [], state: .disconnected)]
        let failure = try card(samples()[10], index: 10)
        snapshot.preparedActions = [try .init(metadata: metadata(id: failure.operationId),
            execution: .init(executorDeviceId: device, originDeviceId: device, taskId: owner, revision: 1),
            toolId: "apple_mail_send", resource: "fixture", parameters: "{}", digest: String(repeating: "0", count: 64),
            consequences: "Render an unknown Mail result", expiresAt: Date().addingTimeInterval(3600), state: .unknown)]
        let store = WorkspaceStore(mode: .preview, route: .chat, previewSnapshot: snapshot)
        store.language = "en"
        return store
    }
    private static func metadata(id: UUID) throws -> BlotV3.RecordMetadata {
        try .init(id: id, ownerId: owner, workspaceId: owner, version: 1, createdAt: Date(), updatedAt: Date())
    }
}
