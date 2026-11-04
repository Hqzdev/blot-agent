import BlotDomain
import Foundation
import Testing
@testable import BlotWorkspace

@Test func changedPreparationInvalidatesGrantAndOnlyOneInvocationMayExecute() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
        draft: .init(name: "Mail", instructions: "Prepare messages for approval", toolIDs: ["gmail.send"]))
    let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Mail", agentID: agent)
    let task = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
        agentID: agent, goal: "Prepare mail", executorDeviceID: identity.deviceID)
    let permissions = WorkspacePermissionService(repository: repository, identity: identity)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let id = try await permissions.prepare(commandID: UUID(), taskID: task,
        draft: .init(toolID: "gmail.send", resource: "test-account", parametersJSON: #"{"to":["first@example.org"],"body":"Original"}"#,
                     consequences: "Send the reviewed message"), expiresAt: now.addingTimeInterval(600), now: now)
    let original = try #require(try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID))
    _ = try await permissions.approve(commandID: UUID(), actionID: id, expectedVersion: 1, digest: original.digest, now: now)
    _ = try await permissions.prepare(commandID: UUID(), taskID: task, actionID: id, expectedVersion: 2,
        draft: .init(toolID: "gmail.send", resource: "test-account", parametersJSON: #"{"to":["second@example.org"],"body":"Changed"}"#,
                     consequences: "Send the reviewed message"), expiresAt: now.addingTimeInterval(600), now: now)
    let changed = try #require(try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID))
    #expect(changed.digest != original.digest)
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await permissions.begin(actionID: id, digest: original.digest, now: now) }
    await #expect(throws: WorkspaceStorageError.permissionDenied) { _ = try await permissions.begin(actionID: id, digest: changed.digest, now: now) }
    _ = try await permissions.approve(commandID: UUID(), actionID: id, expectedVersion: changed.metadata.version, digest: changed.digest, now: now)
    async let first = permissions.begin(actionID: id, digest: changed.digest, now: now)
    async let second = permissions.begin(actionID: id, digest: changed.digest, now: now)
    let outcomes = try await [first, second]
    #expect(outcomes.filter(\.applied).count == 1)
    #expect(outcomes[0].resultID == outcomes[1].resultID)
    let reopened = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let recovered = WorkspacePermissionService(repository: reopened, identity: identity)
    try await recovered.recoverUncertainInvocations(now: now)
    let projection = try await reopened.projection(identity: identity)
    #expect(projection.invocations.count == 1 && projection.invocations[0].state == .unknown)
    #expect(projection.actions[0].state == .unknown)
    #expect(projection.grants.allSatisfy { $0.revoked })
    #expect(try await recovered.begin(actionID: id, digest: changed.digest, now: now).applied == false)
    try await recovered.finish(commandID: UUID(), invocationID: outcomes[0].resultID, state: .succeeded, externalID: "external-test-id", now: now)
    await #expect(throws: WorkspaceStorageError.commandConflict) {
        try await recovered.finish(commandID: UUID(), invocationID: outcomes[0].resultID, state: .failed, now: now)
    }
}

@Test func mixedPreparedFieldsCannotReuseAnOldApprovalDigest() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { cleanupWorkspaceTestStorage(directory) }
    let repository = try await workspaceTestRepository(url: directory.appendingPathComponent("workspace.sqlite"))
    let identity = try await repository.localIdentity()
    let agent = try await WorkspaceAgentService(repository: repository, identity: identity).save(commandID: UUID(),
        draft: .init(name: "Calendar", instructions: "Prepare reviewed events", toolIDs: ["calendar.create"]))
    let conversation = try await WorkspaceChatService(repository: repository, identity: identity).createConversation(commandID: UUID(), title: "Calendar", agentID: agent)
    let task = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: conversation,
        agentID: agent, goal: "Prepare event", executorDeviceID: identity.deviceID)
    let permissions = WorkspacePermissionService(repository: repository, identity: identity)
    let id = try await permissions.prepare(commandID: UUID(), taskID: task,
        draft: .init(toolID: "calendar.create", resource: "test-calendar", parametersJSON: #"{"start":"2026-11-10T10:00:00Z"}"#,
                     consequences: "Create the reviewed event"), expiresAt: Date().addingTimeInterval(600))
    let action = try #require(try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID))
    _ = try await repository.execute(commandID: UUID(), command: Data("simulate-merged-field".utf8), identity: identity) { tx in
        let changed = try BlotV3.PreparedAction(metadata: tx.metadata(id: id, now: Date(), replacing: action.metadata), execution: action.execution,
            toolId: action.toolId, resource: action.resource, parameters: #"{"start":"2026-11-10T11:00:00Z"}"#, digest: action.digest,
            consequences: action.consequences, expiresAt: action.expiresAt, state: action.state, preparationId: action.preparationId)
        try tx.put(changed, expectedVersion: 1)
        return id
    }
    await #expect(throws: WorkspaceStorageError.permissionDenied) {
        _ = try await permissions.approve(commandID: UUID(), actionID: id, expectedVersion: 2, digest: action.digest)
    }
}
