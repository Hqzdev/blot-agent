import Foundation

@MainActor
protocol WorkspaceAccountPasswordChanging {
    func requestPasswordChangeCode() async throws
    func changePassword(code: String, password: String) async throws
}

@MainActor
protocol WorkspaceLocalAccountDeleting {
    func deleteLocalAccountData() async throws
}
