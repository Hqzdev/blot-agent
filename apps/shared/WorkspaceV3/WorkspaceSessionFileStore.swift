import Foundation

@MainActor
extension WorkspaceStore {
    var sessionFileService: LocalWorkspaceService? { serviceForBrowser as? LocalWorkspaceService }
}
