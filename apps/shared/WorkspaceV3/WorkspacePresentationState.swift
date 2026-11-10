import Foundation

nonisolated struct WorkspacePresentationState: Codable, Sendable {
    var drafts: [UUID: WorkspaceComposerForm]
    var interactions: WorkspaceChatInteractions
    var personalization: WorkspacePersonalization
    var firstName: String
    var lastName: String
    var email: String
    var profile: WorkspaceUserProfile? = nil
}
