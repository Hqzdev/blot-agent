import BlotDesign
import Foundation

nonisolated struct ProfileDetails: Codable, Equatable, Sendable {
    var name: String
    var username: String
    var bio: String = ""

    var initials: String {
        let words = name.split(separator: " ")
        if words.count > 1 { return String(words.prefix(2).compactMap(\.first)).uppercased() }
        return String((name.isEmpty ? username : name).prefix(2)).uppercased()
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !username.isEmpty && username.count <= 32 &&
        username.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func account(_ user: AuthUser?) -> ProfileDetails {
        let name = user?.name ?? "Blot"
        let localName = user?.email.split(separator: "@").first.map(String.init) ?? "blot"
        let username = localName.map { character -> Character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_") ? character : "_"
        }
        return ProfileDetails(name: name, username: String(username.prefix(32)))
    }
}

nonisolated struct ProfileStatistics: Codable, Equatable, Sendable {
    var lifetimeTokens: Int64?
    var peakTokens: Int64?
    var longestTaskSeconds: Int?
    var longestStreakDays: Int?
    var currentStreakDays: Int?
}

extension AppState {
    var profileDetails: ProfileDetails {
        workspaceLibrary.profileDetails ?? .account(currentUser)
    }

    var featuredSites: [SavedSite] {
        workspaceLibrary.sites.filter { workspaceLibrary.featuredSiteIDs.contains($0.id) }
    }

    var profileSummary: String {
        let details = profileDetails
        return ([details.name, "@" + details.username, details.bio] +
                featuredSites.map { "\($0.name): \($0.url.absoluteString)" })
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func openProfile() {
        profileVisible = true
        activeTool = nil
        showingSettings = false
        paletteVisible = false
        reviewVisible = false
        inspectorVisible = false
        shell.previewSource = nil
    }
}
