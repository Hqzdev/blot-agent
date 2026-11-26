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
                  Self.originalArguments(try JSONDecoder().decode(ChatJSON.self, from: Data(action.parameters.utf8))) == call.arguments else { throw WorkspaceToolError.invalidArguments }
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
            var invocationArguments = call.arguments
            let parameters = String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self)
            let details = "Сервер: \(entry.name)\nАдрес / программа: \(entry.configuration.endpoint)\nИнструмент: \(tool.name)\nУстройство: \(identity.deviceID.uuidString)\n\nАргументы:\n\(parameters)\n\nСервер получит эти данные и может изменить внешние ресурсы."
            _ = try await permission.prepare(commandID: actionID, taskID: taskID,
                draft: .init(toolID: call.name, resource: entry.id.uuidString, parametersJSON: parameters,
                    consequences: "MCP: \(entry.name) / \(tool.name). Сервер получит точные параметры действия и может изменить внешние ресурсы."), expiresAt: Date().addingTimeInterval(600))
            guard var action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) else { throw MCPError.uncertain }
            do {
                let needsReview = try await WorkspaceRuleService(repository: repository, identity: identity).requiresReview(toolID: call.name,
                    resource: entry.id.uuidString, agentID: context.agentID, default: true)
                if needsReview, context.inlineCards, let draft = Self.slackDraft(entry: entry, tool: tool, arguments: call.arguments) {
                    let response = try await WorkspaceConversationCardService(repository: repository, identity: identity).review(action: action, context: context, content: .slack(draft))
                    guard response.action == "send", let body = response.value, case .object(var fields) = call.arguments else { throw MCPError.denied }
                    fields["text"] = .string(body); invocationArguments = .object(fields)
                    try validate(.init(id: call.id, name: call.name, arguments: invocationArguments), definition: definition)
                    if invocationArguments != call.arguments {
                        let reviewed = ChatJSON.object(["arguments": call.arguments, "review": invocationArguments])
                        _ = try await permission.prepare(commandID: UUID(), taskID: taskID, actionID: actionID, expectedVersion: action.metadata.version,
                            draft: .init(toolID: call.name, resource: action.resource, parametersJSON: String(decoding: WorkspaceCoding.encode(reviewed), as: UTF8.self),
                                consequences: action.consequences), expiresAt: action.expiresAt)
                        guard let revised = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) else { throw MCPError.uncertain }
                        action = revised
                    }
                } else if needsReview {
                    let accepted = context.inlineCards
                        ? try await WorkspaceConversationCardService(repository: repository, identity: identity).review(action: action, context: context, title: entry.name + " / " + tool.name, details: details)
                        : try await confirm("MCP: " + entry.name + " / " + tool.name, details)
                    guard accepted else { throw MCPError.denied }
                }
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
                let resultValue = try await client.call(name: tool.name, arguments: invocationArguments)
                let current = try await service.currentConfiguration(entry.id)
                let raw = redact(redact(resultValue, configuration: current), configuration: entry.configuration)
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
    private static func originalArguments(_ saved: ChatJSON) -> ChatJSON {
        if case .object(let values) = saved, let arguments = values["arguments"], values["review"] != nil { return arguments }; return saved
    }
    private static func slackDraft(entry: MCPLocalConnection, tool: MCPTool, arguments: ChatJSON) -> WorkspaceCardContent.SlackDraft? {
        let names = ["slack_post_message", "slack_send_message", "chat_postMessage", "chat.postMessage"]
        guard entry.name.caseInsensitiveCompare("Slack") == .orderedSame, names.contains(tool.name),
              case .object(let values) = arguments, values["blocks"] == nil, values["attachments"] == nil,
              case .string(let channel) = values["channel"], case .string(let body) = values["text"] else { return nil }
        let thread: String?
        if case .string(let value) = values["thread_ts"] { thread = value } else { thread = nil }
        return .init(workspace: entry.name, channel: channel, thread: thread, body: body)
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
