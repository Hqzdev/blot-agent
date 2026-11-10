import Foundation

nonisolated struct WorkspaceUserProfile: Codable, Equatable, Sendable {
    enum AvatarSource: String, Codable, Sendable { case provider, custom, removed }
    var nickname = ""
    var contactEmail: String?
    var avatar: Data?
    var avatarSource: AvatarSource?
    var providerAvatarURL: URL?

    var acceptsProviderAvatar: Bool {
        avatarSource != .custom && avatarSource != .removed && (avatar == nil || avatarSource == .provider)
    }
    mutating func setCustomAvatar(_ data: Data?) {
        avatar = data; avatarSource = data == nil ? .removed : .custom; providerAvatarURL = nil
    }
}
