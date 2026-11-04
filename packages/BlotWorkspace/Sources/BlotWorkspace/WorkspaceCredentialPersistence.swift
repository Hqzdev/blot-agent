import Foundation

/// Actor reentrancy must not let an older suspended write finish after a successful removal.
actor WorkspaceCredentialPersistence {
    private let store: any WorkspaceCredentialStore
    private let name: String
    private var pending: Task<Void, Error>?
    init(store: any WorkspaceCredentialStore, name: String) { self.store = store; self.name = name }
    func replace(with data: Data?) async throws {
        let previous = pending
        let store = self.store, name = self.name
        let worker = Task {
            if let previous { _ = try? await previous.value }
            if let data { try await store.write(data, name: name) }
            else { try await store.remove(name) }
        }
        pending = worker
        try await worker.value
    }
}
