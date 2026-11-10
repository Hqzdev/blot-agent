/// Account synchronization is separate from local commands and authentication.
@MainActor
protocol WorkspaceAccountSynchronizing {
    func synchronizeAccount() async throws
}
