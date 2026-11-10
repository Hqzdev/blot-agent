import BlotWorkspace
import Foundation

/// Uses the production presentation state, writer and SQLite repository without an app or account session.
@main struct VerifyProfilePersistence {
    @MainActor static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("first.sqlite")
        let repository = try WorkspaceRepository(url: url)
        _ = try await repository.localIdentity()
        var profile = WorkspaceUserProfile(nickname: "Saved profile")
        profile.setCustomAvatar(Data([0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]))
        precondition(!profile.acceptsProviderAvatar)
        var state = WorkspacePresentationState(drafts: [:], interactions: .init(), personalization: .init(), firstName: "Name", lastName: "", email: "person@example.org", profile: profile)
        let writer = WorkspacePresentationWriter()
        writer.schedule(state, immediately: true) { data in try await repository.savePresentationState(data) }
        try await writer.flushReportingFailure()
        try await repository.close()
        let reopened = try WorkspaceRepository(url: url)
        let data = try await reopened.presentationState()!
        let restored = try JSONDecoder().decode(WorkspacePresentationState.self, from: data)
        precondition(restored.profile == profile)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "profile")
        let oldState = try JSONDecoder().decode(WorkspacePresentationState.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldState.profile == nil && oldState.email == state.email)
        var oldPhoto = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        oldPhoto.removeValue(forKey: "avatarSource")
        let migrated = try JSONDecoder().decode(WorkspaceUserProfile.self, from: JSONSerialization.data(withJSONObject: oldPhoto))
        precondition(migrated.avatar == profile.avatar && !migrated.acceptsProviderAvatar)
        let second = try WorkspaceRepository(url: directory.appendingPathComponent("second.sqlite"))
        _ = try await second.localIdentity()
        let secondState = try await second.presentationState()
        precondition(secondState == nil)
        try await second.close()
        // Editing another setting retains the saved profile on either Apple client.
        state = restored; state.firstName = "Changed"
        let edited = try JSONDecoder().decode(WorkspacePresentationState.self, from: JSONEncoder().encode(state))
        precondition(edited.profile == profile)
        profile.setCustomAvatar(nil)
        let removed = try JSONDecoder().decode(WorkspaceUserProfile.self, from: JSONEncoder().encode(profile))
        precondition(removed.avatar == nil && removed.avatarSource == .removed && !removed.acceptsProviderAvatar)
        precondition(WorkspaceUserProfile().acceptsProviderAvatar)
        enum WriteFailure: Error { case unavailable }
        writer.schedule(state, immediately: true) { _ in throw WriteFailure.unavailable }
        do { try await writer.flushReportingFailure(); preconditionFailure("Save errors must reach the editor") }
        catch WriteFailure.unavailable { }
        state.profile = removed
        writer.schedule(state, immediately: true) { data in try await reopened.savePresentationState(data) }
        try await writer.flushReportingFailure()
        let final = try JSONDecoder().decode(WorkspacePresentationState.self, from: await reopened.presentationState()!)
        precondition(final.profile == removed)
        try await reopened.close()
        print("PASS: profile survives SQLite reopen, legacy state loads, accounts stay isolated, removals persist, save errors propagate and retry succeeds")
    }
}
