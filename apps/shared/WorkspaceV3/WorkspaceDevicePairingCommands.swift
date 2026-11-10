import BlotWorkspace
import Foundation

@MainActor
protocol WorkspaceDevicePairingCommands: WorkspaceObservationService {
    func createDeviceInvite() async throws -> String
    func claimDevice(_ token: String) async throws -> WorkspacePairingClaim
    func inspectDeviceClaim(_ token: String) async throws -> WorkspacePairingClaim
    func approveDevice(_ token: String, code: String) async throws -> String
    func finishDevicePairing(_ token: String) async throws
    func revokePairedDevice(_ id: UUID) async throws
}

@MainActor
protocol WorkspaceDevicePairingProviding {
    var workspacePairing: (any WorkspaceDevicePairingCommands)? { get }
}
