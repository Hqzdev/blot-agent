import BlotDomain
import Foundation

public struct WorkspaceBrowserTools: WorkspaceToolExecuting {
    private let service: WorkspaceBrowserService
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let files: WorkspaceFileService
    private let confirm: @Sendable (String, String) async throws -> Bool
    public init(service: WorkspaceBrowserService, repository: WorkspaceRepository, identity: WorkspaceIdentity, files: WorkspaceFileService,
                confirm: @escaping @Sendable (String, String) async throws -> Bool) {
        self.service = service; self.repository = repository; self.identity = identity; self.files = files; self.confirm = confirm
    }
    public var definitions: [ChatToolDefinition] { WorkspaceBrowserCatalog.definitions }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        try await service.availableDefinitions(context: context)
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch { return .object(["state": .string((error as? WorkspaceBrowserError) == .unknown ? "unknown" : "failed"),
                               "error": .string((error as? WorkspaceBrowserError)?.localizedDescription ?? "Действие браузера не выполнено.")]) }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        let authorized = try await service.authorize(call.name, context: context)
        let actionID = WorkspaceLogicalID.make(kind: "BrowserAction", workspaceID: identity.workspaceID, parts: [context.sourceMessageID.uuidString, call.id])
        let command = WorkspaceBrowserCommand(id: actionID, name: call.name, arguments: call.arguments, scope: authorized.scope, origins: authorized.origins)
        if !WorkspaceBrowserCatalog.requiresConfirmation(call.name) {
            let binding = try await service.prepare(command)
            return try await result(service.perform(command, binding: binding), call: call, context: context)
        }
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard let data = action.parameters.data(using: .utf8), let saved = try? WorkspaceCoding.decode(Parameters.self, from: data),
                  saved.arguments == call.arguments, action.toolId == call.name else { throw WorkspaceBrowserError.denied }
            let projection = try await repository.projection(identity: identity)
            if let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }), invocation.state == .succeeded,
               let result = invocation.result { return try WorkspaceCoding.decode(ChatJSON.self, from: Data(result.utf8)) }
            if [.denied, .failed, .expired].contains(action.state) { throw WorkspaceBrowserError.canceled }
            throw WorkspaceBrowserError.unknown
        }
        let binding = try await service.prepare(command)
        let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID)
        guard let source else { throw WorkspaceBrowserError.denied }
        let taskID: UUID
        if let existing = context.taskID { taskID = existing }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(),
            conversationID: source.conversationId, agentID: authorized.scope.agentID, goal: "Действие во встроенном браузере", executorDeviceID: identity.deviceID, runnable: false) }
        let parameters = String(decoding: try WorkspaceCoding.encode(Parameters(arguments: call.arguments, binding: binding)), as: UTF8.self)
        let details = "Сайт: \(binding.url)\nЭлемент: \(binding.target)\n\n" + (call.name == "browser_type" ? "Ввод текста может изменить данные сайта. Проверьте текст и поле." : "Нажатие может отправить форму или изменить данные сайта.")
        let id = try await permission.prepare(commandID: actionID, taskID: taskID,
            draft: .init(toolID: call.name, resource: "browser:" + binding.tabID.uuidString,
                parametersJSON: parameters, consequences: String(details.prefix(3500))), expiresAt: Date().addingTimeInterval(300))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID) else { throw WorkspaceBrowserError.unknown }
        do {
            let input: String
            if case .object(let fields) = call.arguments, case .string(let text) = fields["text"] { input = "\n\nТекст:\n" + text } else { input = "" }
            guard try await confirm("Действие браузера", details + input) else { throw WorkspaceBrowserError.canceled }
            _ = try await service.authorize(call.name, context: context)
            guard try await service.prepare(command) == binding else { throw WorkspaceBrowserError.stalePage }
        } catch {
            try? await permission.deny(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
            throw error
        }
        _ = try await permission.approve(commandID: UUID(), actionID: id, expectedVersion: action.metadata.version, digest: action.digest)
        let outcome = try await permission.begin(actionID: id, digest: action.digest)
        guard outcome.applied else { throw WorkspaceBrowserError.unknown }
        do {
            _ = try await service.authorize(call.name, context: context)
            let value = try await result(service.perform(command, binding: binding), call: call, context: context)
            try await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: .succeeded,
                result: String(decoding: try WorkspaceCoding.encode(value), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return value
        } catch {
            let known = [WorkspaceBrowserError.stalePage, .denied].contains(error as? WorkspaceBrowserError ?? .unknown)
            try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: known ? .failed : .unknown)
            if error is CancellationError { throw error }; throw known ? error : WorkspaceBrowserError.unknown
        }
    }
    private struct Parameters: Codable { let arguments: ChatJSON; let binding: WorkspaceBrowserBinding }
    private func result(_ operation: WorkspaceBrowserResult, call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        switch operation {
        case .value(let value): return value
        case .image(let data):
            guard data.count <= 4 * 1024 * 1024 else { throw WorkspaceBrowserError.unavailable }
            let id = try await files.store(commandID: WorkspaceLogicalID.make(kind: "BrowserImage", workspaceID: identity.workspaceID, parts: [context.sourceMessageID.uuidString, call.id]),
                name: "browser.png", mediaType: "image/png", data: data, taskID: context.taskID)
            return .object(["artifact_id": .string(id.uuidString), "name": .string("browser.png")])
        }
    }
}
