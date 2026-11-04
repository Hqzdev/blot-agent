import Foundation

struct WorkspacePresentationState: Codable {
    var drafts: [UUID: WorkspaceComposerForm]
    var interactions: WorkspaceChatInteractions
    var personalization: WorkspacePersonalization
    var firstName: String
    var lastName: String
    var email: String
}
