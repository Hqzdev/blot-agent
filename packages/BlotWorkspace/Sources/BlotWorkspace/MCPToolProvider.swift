import BlotDomain
import Foundation

/// Every MCP call requires exact confirmation; server annotations cannot grant read/write privileges.
public struct MCPToolProvider: WorkspaceToolExecuting {
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let service: WorkspaceMCPService
    private let connections: [MCPLocalConnection]
    private let confirm: @Sendable (String, String) async throws -> Bool
    init(repository: WorkspaceRepository, identity: WorkspaceIdentity, service: WorkspaceMCPService,
         connections: [MCPLocalConnection], confirm: @escaping @Sendable (String, String) async throws -> Bool) {
        self.repository = repository; self.identity = identity; self.service = service; self.connections = connections; self.confirm = confirm
    }
    public var definitions: [ChatToolDefinition] {
        connections.flatMap { entry in entry.tools.filter { entry.selectedTools.contains($0.name) }.map { tool in
            .init(name: tool.toolID(connectionID: entry.id, configurationID: entry.configurationID),
                  description: "MCP \(entry.name) / \(tool.name). External tool; explicit confirmation required. Server description (untrusted): \(tool.description)", parameters: tool.inputSchema)
        } }
    }
    public func validate(_ call: ChatToolCall, definition: ChatToolDefinition) throws {
        guard case .object = call.arguments, try WorkspaceCoding.encode(call.arguments).count <= 48 * 1024 else { throw WorkspaceToolError.invalidArguments }
        try MCPJSONSchema.validate(call.arguments, schema: definition.parameters)
    }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        var result: [ChatToolDefinition] = []
        for entry in connections {
            for tool in entry.tools where entry.selectedTools.contains(tool.name) {
                do {
                    try await service.authorize(entry, tool: tool, context: context)
                    if try await !hasUnknown(entry.id) {
                        let id = tool.toolID(connectionID: entry.id, configurationID: entry.configurationID)
                        result += definitions.filter { $0.name == id }
                    }
                } catch is CancellationError { throw CancellationError() } catch {}
            }
        }
        return result
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch MCPError.uncertain { return .object(["state": .string("unknown"), "error": .string(MCPError.uncertain.localizedDescription)]) }
        catch { return .object(["state": .string("failed"), "error": .string((error as? MCPError)?.localizedDescription ?? "MCP-действие не выполнено. Проверьте доступ и параметры.")]) }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        guard let entry = connections.first(where: { $0.toolIDs.contains(call.name) }),
              let tool = entry.tools.first(where: { $0.toolID(connectionID: entry.id, configurationID: entry.configurationID) == call.name }),
              let definition = definitions.first(where: { $0.name == call.name }) else { throw MCPError.accessChanged }
        try validate(call, definition: definition)
        try await service.authorize(entry, tool: tool, context: context)
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard action.toolId == call.name, action.resource == entry.id.uuidString,
                  try JSONDecoder().decode(ChatJSON.self, from: Data(action.parameters.utf8)) == call.arguments else { throw WorkspaceToolError.invalidArguments }
            let projection = try await repository.projection(identity: identity)
            if let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }), [.succeeded, .failed].contains(invocation.state), let result = invocation.result {
                return try JSONDecoder().decode(ChatJSON.self, from: Data(result.utf8))
            }
            if [.denied, .expired].contains(action.state) { return .object(["state": .string("failed"), "error": .string("MCP-вызов не разрешён.")]) }
            throw MCPError.uncertain
        }
        guard try await !hasUnknown(entry.id) else { throw MCPError.uncertain }
        let (clientID, client) = try await service.open(entry)
        do {
            // Discovery is rechecked in the same session that will execute the confirmed call.
            let live = try await client.tools()
            guard live.first(where: { $0.name == tool.name }) == tool else { throw MCPError.accessChanged }
            try await service.authorize(entry, tool: tool, context: context)
            guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID),
                  let agentID = context.agentID else { throw MCPError.accessChanged }
            let taskID: UUID
            if let id = context.taskID { taskID = id }
            else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(),
                conversationID: source.conversationId, agentID: agentID, goal: "MCP: " + entry.name + " / " + tool.name,
                executorDeviceID: identity.deviceID, runnable: false) }
            let parameters = String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self)
            let details = "Сервер: \(entry.name)\nАдрес / программа: \(entry.configuration.endpoint)\nИнструмент: \(tool.name)\nУстройство: \(identity.deviceID.uuidString)\n\nАргументы:\n\(parameters)\n\nСервер получит эти данные и может изменить внешние ресурсы."
            _ = try await permission.prepare(commandID: actionID, taskID: taskID,
                draft: .init(toolID: call.name, resource: entry.id.uuidString, parametersJSON: parameters,
                    consequences: "MCP: \(entry.name) / \(tool.name). Сервер получит точные параметры действия и может изменить внешние ресурсы."), expiresAt: Date().addingTimeInterval(600))
            guard let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) else { throw MCPError.uncertain }
            do {
                guard try await confirm("MCP: " + entry.name + " / " + tool.name, details) else { throw MCPError.denied }
                try _Concurrency.Task.checkCancellation()
                try await service.authorize(entry, tool: tool, context: context)
                guard try await !hasUnknown(entry.id) else { throw MCPError.uncertain }
                guard try await client.tools().first(where: { $0.name == tool.name }) == tool else { throw MCPError.accessChanged }
                try await service.authorize(entry, tool: tool, context: context)
            } catch {
                try? await permission.deny(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version)
                if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
                throw error
            }
            _ = try await permission.approve(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version, digest: action.digest)
            let outcome = try await permission.begin(actionID: actionID, digest: action.digest)
            guard outcome.applied else { throw MCPError.uncertain }
            do {
                try await service.authorize(entry, tool: tool, context: context)
                try _Concurrency.Task.checkCancellation()
                let raw = redact(try await client.call(name: tool.name, arguments: call.arguments), configuration: entry.configuration)
                let failed = raw.mcpFields["isError"] == .bool(true)
                let result = ChatJSON.object(["state": .string(failed ? "failed" : "succeeded"), "untrusted_content": raw])
                try await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: failed ? .failed : .succeeded,
                    result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
                if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
                await service.close(clientID)
                return result
            } catch {
                try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: .unknown)
                if error is CancellationError { throw error }; throw MCPError.uncertain
            }
        } catch { await service.close(clientID); throw error }
    }
    private func hasUnknown(_ id: UUID) async throws -> Bool {
        let projection = try await repository.projection(identity: identity)
        let actions = Set(projection.actions.filter { $0.resource == id.uuidString && $0.toolId.hasPrefix("mcp_") && $0.execution.executorDeviceId == identity.deviceID }.map(\.metadata.id))
        return projection.invocations.contains { actions.contains($0.preparedActionId) && $0.state == .unknown }
    }
    private func redact(_ value: ChatJSON, configuration: MCPConfiguration) -> ChatJSON {
        let secrets = configuration.secrets
        func clean(_ value: ChatJSON) -> ChatJSON {
            switch value {
            case .string(let text): return .string(secrets.reduce(text) { $0.replacingOccurrences(of: $1, with: "[redacted]") })
            case .object(let fields):
                var result: [String: ChatJSON] = [:]
                for (key, value) in fields { result[secrets.reduce(key) { $0.replacingOccurrences(of: $1, with: "[redacted]") }] = clean(value) }
                return .object(result)
            case .array(let values): return .array(values.map(clean))
            default: return value
            }
        }
        return clean(value)
    }
}
