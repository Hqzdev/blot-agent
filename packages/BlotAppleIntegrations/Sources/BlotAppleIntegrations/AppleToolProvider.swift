import BlotDomain
import BlotWorkspace
import CryptoKit
import Foundation

/// Resolves live assignments and device permissions at every invocation, including after confirmation.
public struct AppleToolProvider: WorkspaceToolExecuting {
    private let discovery = AppleToolDiscovery()
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let controller: any AppleIntegrationExecuting
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity, controller: any AppleIntegrationExecuting) {
        self.repository = repository; self.identity = identity; self.controller = controller
    }
    public var definitions: [ChatToolDefinition] { AppleToolCatalog.all.map(\.definition) }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        let projection = try await repository.projection(identity: identity)
        guard let agentID = context.agentID else { return [] }
        var available: [ChatToolDefinition] = []
        for connection in projection.connections where connection.deviceId == identity.deviceID && connection.state == .connected && (connection.agentIds ?? []).contains(agentID) {
            guard let id = connection.pluginId.flatMap(ApplePluginID.init(rawValue:)),
                  await controller.accessible(id, resources: connection.resourceIds ?? []) else { continue }
            let expanded = await discovery.contains(id)
            let uncertain = !AppleInvocationRecovery.pending(plugin: id, deviceID: identity.deviceID, actions: projection.actions, invocations: projection.invocations).isEmpty
            available += AppleToolCatalog.tools(for: id).filter { ($0.operation == "resources" || expanded) && (!uncertain || !$0.writes) }
                .map(\.definition).filter { context.allowedToolIDs.contains($0.name) }
        }
        return available
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch let error as AppleIntegrationError {
            let state: String
            switch error { case .uncertainResult: state = "unknown"; case .canceled: state = "canceled"; default: state = "failed" }
            return appleObject(["state": state, "error": error.localizedDescription])
        }
        catch { return appleObject(["state": "failed", "error": "Действие не завершено. Проверьте доступ и состояние приложения."]) }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard let tool = AppleToolCatalog.all.first(where: { $0.definition.name == call.name }) else { throw AppleIntegrationError.unavailable }
        let a = try AppleArguments(call.arguments)
        let connection = try await authorize(tool, arguments: a, context: context)
        if tool.operation == "resources" {
            await discovery.expand(tool.plugin)
            let resources = try await controller.resources(tool.plugin, selected: connection.resourceIds ?? [])
            guard !resources.isEmpty else { throw AppleIntegrationError.missingResource }
            return .array(resources.map { appleObject(["id": $0.id, "name": $0.name]) })
        }
        if !tool.writes { return try await controller.execute(tool, arguments: call.arguments) }
        guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
              source.metadata.ownerId == identity.ownerID, let agentID = context.agentID else { throw AppleIntegrationError.permissionDenied }
        let actionID = stableID(source: context.sourceMessageID, callID: call.id)
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard action.toolId == call.name, action.resource == connection.metadata.id.uuidString + "/" + (a["resource_id"] ?? ""),
                  let saved = action.parameters.data(using: .utf8), try JSONDecoder().decode(ChatJSON.self, from: saved) == call.arguments else { throw AppleIntegrationError.invalidArguments }
            let projection = try await repository.projection(identity: identity)
            if let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }), invocation.state == .succeeded,
               let result = invocation.result, let data = result.data(using: .utf8) { return try JSONDecoder().decode(ChatJSON.self, from: data) }
            if action.state == .denied { throw AppleIntegrationError.canceled }
            if action.state == .failed { return appleObject(["state": "failed", "error": "Этот вызов уже завершён без выполнения. Для нового действия нужен новый запрос."]) }
            throw AppleIntegrationError.uncertainResult
        }
        let taskID: UUID
        if let existing = context.taskID { taskID = existing }
        else {
            taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(),
                conversationID: source.conversationId, agentID: agentID, goal: tool.definition.description,
                executorDeviceID: identity.deviceID)
        }
        let preview = try await controller.preview(tool, arguments: call.arguments)
        let parameters = String(decoding: try JSONEncoder().encode(call.arguments), as: UTF8.self)
        let resourceName: String
        if tool.needsConfirmation {
            resourceName = try await controller.resources(tool.plugin, selected: [a.required("resource_id")]).first?.name ?? tool.plugin.name
        } else { resourceName = tool.plugin.name }
        let mailNotice = tool.plugin == .mail && tool.operation == "send" ? "Проверьте вложения в открытом черновике в Почте: API не предоставляет их полный просмотр.\n\n" : ""
        let details = mailNotice + AppleActionReview.details(arguments: call.arguments, preview: preview, resourceName: resourceName)
        let id = try await permission.prepare(commandID: actionID, taskID: taskID,
            draft: .init(toolID: call.name, resource: connection.metadata.id.uuidString + "/" + (a["resource_id"] ?? ""),
                parametersJSON: parameters, consequences: String(decoding: (AppleActionReview.title(tool) + "\n" + details).utf8.prefix(3500), as: UTF8.self)),
            expiresAt: Date().addingTimeInterval(600))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID) else { throw AppleIntegrationError.uncertainResult }
        if tool.needsConfirmation {
            do {
                let accepted = try await controller.interactions.confirm(title: AppleActionReview.title(tool), details: details)
                guard accepted else { throw AppleIntegrationError.canceled }
            } catch {
                try? await permission.deny(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version)
                if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
                throw error
            }
        }
        _ = try await authorize(tool, arguments: a, context: context)
        if let preview, try await controller.preview(tool, arguments: call.arguments) != preview { throw AppleIntegrationError.system("Объект изменился после подготовки. Подготовьте действие заново.") }
        _ = try await permission.approve(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version, digest: action.digest)
        let outcome = try await permission.begin(actionID: id, digest: action.digest)
        guard outcome.applied else { throw AppleIntegrationError.uncertainResult }
        do {
            _ = try await authorize(tool, arguments: a, context: context)
            try _Concurrency.Task.checkCancellation()
            let result = try await controller.execute(tool, arguments: call.arguments)
            let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
            try await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: .succeeded, result: encoded)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch {
            try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: .unknown)
            if error is CancellationError { throw error }
            throw AppleIntegrationError.uncertainResult
        }
    }
    private func authorize(_ tool: AppleTool, arguments a: AppleArguments, context: WorkspaceToolContext) async throws -> BlotV3.Connection {
        let projection = try await repository.projection(identity: identity)
        guard let source = projection.messages.first(where: { $0.metadata.id == context.sourceMessageID }), source.metadata.ownerId == identity.ownerID,
              let agentID = context.agentID,
              let configuration = try WorkspaceAgentConfigurationResolver().resolve(agentID: agentID, projection: projection),
              configuration.toolIds.contains(tool.definition.name), context.allowedToolIDs.contains(tool.definition.name),
              let connection = projection.connections.first(where: {
                  $0.pluginId == tool.plugin.rawValue && $0.deviceId == identity.deviceID && $0.state == .connected &&
                  ($0.agentIds ?? []).contains(agentID) && (context.connectionID == nil || $0.metadata.id == context.connectionID)
              }), await controller.accessible(tool.plugin, resources: connection.resourceIds ?? []) else { throw AppleIntegrationError.permissionDenied }
        if tool.writes, !AppleInvocationRecovery.pending(plugin: tool.plugin, deviceID: identity.deviceID, actions: projection.actions, invocations: projection.invocations).isEmpty {
            throw AppleIntegrationError.uncertainResult
        }
        if tool.operation != "resources", !(connection.resourceIds ?? []).contains(try a.required("resource_id")) { throw AppleIntegrationError.permissionDenied }
        guard !projection.conflicts.contains(where: { !$0.resolved && ($0.recordId == connection.metadata.id || $0.recordId == agentID) }),
              projection.grants.contains(where: { $0.kind == .rule && !$0.revoked && $0.resource == connection.metadata.id.uuidString && $0.scope == tool.plugin.rawValue && $0.operationClass == "apple.resource.write" }) else { throw AppleIntegrationError.permissionDenied }
        if !tool.needsConfirmation {
            let operation = ["list", "read", "search", "resources"].contains(tool.operation) ? "read" : tool.operation == "reply" ? "create" : tool.operation
            guard (connection.allowedOperations ?? []).contains(operation) else { throw AppleIntegrationError.permissionDenied }
        }
        return connection
    }
    private func stableID(source: UUID, callID: String) -> UUID {
        var b = Array(SHA256.hash(data: Data((identity.workspaceID.uuidString + ":" + source.uuidString + ":" + callID).utf8)).prefix(16))
        b[6] = (b[6] & 15) | 0x80; b[8] = (b[8] & 63) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

/// Resource discovery enables only the needed plugin schemas for the following model turn.
private actor AppleToolDiscovery {
    private var expanded: Set<ApplePluginID> = []
    func contains(_ plugin: ApplePluginID) -> Bool { expanded.contains(plugin) }
    func expand(_ plugin: ApplePluginID) { expanded.insert(plugin) }
}
