import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func sharedWebChatsInstallOnAppleReplicasAndReplyRoundTrips() async throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let bytes = try Data(contentsOf: root.appendingPathComponent("apps/web/packages/chat-sync/fixtures/web-snapshot.json"))
    let snapshot = try WorkspaceCoding.decode(WorkspaceReplicaSnapshot.self, from: bytes)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("blot-web-chat-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let mac = try WorkspaceRepository(url: folder.appendingPathComponent("mac.sqlite"))
    let phone = try WorkspaceRepository(url: folder.appendingPathComponent("phone.sqlite"))
    do {
        let macID = try await mac.accountIdentity(ownerID: snapshot.ownerID, workspaceID: snapshot.workspaceID)
        let phoneID = try await phone.accountIdentity(ownerID: snapshot.ownerID, workspaceID: snapshot.workspaceID)
        try await mac.installReplicaSnapshot(snapshot, identity: macID)
        try await phone.installReplicaSnapshot(snapshot, identity: phoneID)
        let initial = try await phone.projection(identity: phoneID)
        let direct = WorkspaceDirectConversations(initial.conversations)
        #expect(direct.conversations.count == 2)
        #expect(initial.messages.count == 2)
        #expect(initial.messages.contains { $0.role == .assistant && $0.content == "Web assistant answer" })
        let conversationID = try #require(UUID(uuidString: "33333333-3333-4333-a333-333333333333"))
        let commandID = UUID()
        _ = try await WorkspaceChatService(repository: phone, identity: phoneID).sendMessage(
            commandID: commandID, conversationID: conversationID, content: "Reply from iPhone")
        let response = try await phone.replicaSnapshot(identity: phoneID)
        try await mac.installReplicaSnapshot(response, identity: macID)
        let received = try await mac.projection(identity: macID)
        #expect(received.messages.contains { $0.metadata.id == commandID && $0.content == "Reply from iPhone" })
        try await mac.installReplicaSnapshot(response, identity: macID)
        #expect(try await mac.projection(identity: macID).messages.count == 3)
        if let output = ProcessInfo.processInfo.environment["BLOT_WRITE_NATIVE_CHAT_FIXTURE"] {
            try WorkspaceCoding.encode(response).write(to: URL(fileURLWithPath: output), options: .atomic)
        }
        try await mac.close()
        try await phone.close()
    } catch {
        try? await mac.close()
        try? await phone.close()
        throw error
    }
}
