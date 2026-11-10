import BlotWorkspace
import Foundation

@MainActor protocol WorkspaceDeviceCommands: WorkspaceObservationService {
    func createDeviceInvite() async throws -> String
    func claimDevice(_ token: String) async throws -> WorkspacePairingClaim
    func inspectDeviceClaim(_ token: String) async throws -> WorkspacePairingClaim
    func approveDevice(_ token: String, code: String) async throws -> String
    func finishDevicePairing(_ token: String) async throws
    func revokePairedDevice(_ id: UUID) async throws
    func delegateTask(conversationID: UUID, agentID: UUID, deviceID: UUID, goal: String) async throws -> UUID
}
@MainActor protocol WorkspaceDeviceProviding { var workspaceDevices: (any WorkspaceDeviceCommands)? { get } }
@MainActor protocol WorkspaceAccountDeleting {
    func requestAccountDeletion() async throws
    func confirmAccountDeletion(code: String) async throws
}

enum WorkspaceAccountDeletionFailure: Error { case localCleanupIncomplete }
