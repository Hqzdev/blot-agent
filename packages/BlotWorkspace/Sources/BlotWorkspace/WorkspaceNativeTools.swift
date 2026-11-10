import BlotDomain
import Foundation

public struct WorkspaceNativeTools: WorkspaceToolExecuting {
    private let service: WorkspaceNativeService
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    private let confirm: @Sendable (String, String) async throws -> Bool
    public init(service: WorkspaceNativeService, repository: WorkspaceRepository, identity: WorkspaceIdentity,
                confirm: @escaping @Sendable (String, String) async throws -> Bool) {
        self.service = service; self.repository = repository; self.identity = identity; self.confirm = confirm
    }
    public var definitions: [ChatToolDefinition] { WorkspaceNativeCatalog.definitions }
    public func availableDefinitions(context: WorkspaceToolContext) async throws -> [ChatToolDefinition] {
        var result: [ChatToolDefinition] = []
        for definition in definitions {
            do { _ = try await service.authorize(definition.name, context: context); result.append(definition) }
            catch is CancellationError { throw CancellationError() } catch {}
        }
        return result
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch NativeExecutionError.unknown { return .object(["state": .string("unknown"), "error": .string(NativeExecutionError.unknown.localizedDescription)]) }
        catch NativeExecutionError.gitFailed { return .object(["state": .string("failed"), "error": .string("Git не завершил операцию. Проверьте репозиторий, имя/email автора и доступ к remote.")]) }
        catch { return .object(["state": .string("failed"), "error": .string((error as? NativeExecutionError)?.localizedDescription ?? "Действие проекта не выполнено. Проверьте доступ, состояние файлов и параметры.")]) }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        let project = try await service.authorize(call.name, context: context)
        let operation = try WorkspaceNativeCatalog.operation(call.name)
        if operation == .status || operation == .stop {
            guard let raw = call.arguments.mcpFields["process_id"]?.mcpString, let id = UUID(uuidString: raw) else { throw NativeExecutionError.invalidRequest }
            return try await service.process(id, context: context, stop: operation == .stop)
        }
        var parameters: [String: String] = [:]
        for (key, value) in call.arguments.mcpFields {
            if let text = value.mcpString { parameters[key] = text }
            else if key == "paths", case .array = value { parameters[key] = String(decoding: try WorkspaceCoding.encode(value), as: UTF8.self) }
        }
        let processID = WorkspaceLogicalID.make(kind: "NativeProcess", workspaceID: identity.workspaceID, parts: [context.sourceMessageID.uuidString, call.id])
        let command = try await service.command(project: project, arguments: operation == .start ? call.arguments : .object([:]), id: processID, git: call.name.hasPrefix("git_"))
        if !WorkspaceNativeCatalog.writes(call.name) {
            let result = try await service.perform(.init(operation, command: command, parameters: parameters))
            if operation == .gitPrepareCommit || operation == .gitPreparePush { await service.rememberPreparation(result, project: project.id, source: context.sourceMessageID) }
            return await service.redact(result, project: project)
        }
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
        if let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) {
            guard action.toolId == call.name, action.resource == "project:" + project.id.uuidString,
                  try WorkspaceCoding.decode(ChatJSON.self, from: Data(action.parameters.utf8)) == call.arguments else { throw NativeExecutionError.changed }
            let projection = try await repository.projection(identity: identity)
            if let invocation = projection.invocations.first(where: { $0.preparedActionId == actionID }) {
                if [.succeeded, .failed].contains(invocation.state), let raw = invocation.result { return try WorkspaceCoding.decode(ChatJSON.self, from: Data(raw.utf8)) }
                if operation == .start, invocation.state == .running { return try await service.process(processID, context: context, stop: false) }
                throw NativeExecutionError.unknown
            }
            if [.denied, .expired].contains(action.state) { return .object(["state": .string("failed"), "error": .string("Действие не разрешено.")]) }
            throw NativeExecutionError.changed
        }
        var preview = ""
        var binding: ChatJSON = .object([:])
        if operation == .gitCommit || operation == .gitPush {
            guard let id = parameters["preparation_id"] else { throw NativeExecutionError.invalidRequest }
            let prepared = try await service.preparation(id, project: project.id, source: context.sourceMessageID)
            preview = String(decoding: try WorkspaceCoding.encode(prepared), as: UTF8.self)
            binding = await service.redact(.object(prepared.mcpFields.filter { $0.key != "diff" }), project: project)
        }
        guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID), let agent = context.agentID else { throw NativeExecutionError.accessDenied }
        let taskID: UUID
        if let existing = context.taskID { taskID = existing }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: source.conversationId,
            agentID: agent, goal: call.name + " · " + project.name, executorDeviceID: identity.deviceID, projectID: project.id, runnable: false) }
        let parametersJSON = String(decoding: try WorkspaceCoding.encode(call.arguments), as: UTF8.self)
        let details = "Проект: \(project.name)\nУстройство: \(identity.deviceID.uuidString)\nДействие: \(call.name)\n\n\(parametersJSON)\n\n\(preview)" +
            (operation == .start ? "\nКоманда выполняется на Mac с доступом пользователя. Скрипты проекта не изолированы внутри его папки." : "")
        let consequences = String(decoding: try WorkspaceCoding.encode(ChatJSON.object(["operation": .string(call.name), "project": .string(project.name), "binding": binding])), as: UTF8.self)
        _ = try await permission.prepare(commandID: actionID, taskID: taskID, draft: .init(toolID: call.name, resource: "project:" + project.id.uuidString,
            parametersJSON: parametersJSON, consequences: consequences), expiresAt: Date().addingTimeInterval(600))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: actionID, workspaceID: identity.workspaceID) else { throw NativeExecutionError.unknown }
        let agentProfile = try await repository.record(BlotV3.AgentProfile.self, id: agent, workspaceID: identity.workspaceID)
        let trusted = operation != .gitPush && agentProfile?.accessMode == .trusted_scope && project.trustedClasses.contains(WorkspaceNativeCatalog.operationClass(call.name))
        do {
            if !trusted { guard try await confirm("\(project.name) · \(call.name)", details) else { throw NativeExecutionError.accessDenied } }
            let current = try await service.authorize(call.name, context: context)
            guard current.id == project.id, current.revision == project.revision else { throw NativeExecutionError.changed }
            try _Concurrency.Task.checkCancellation()
        } catch {
            try? await permission.deny(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
            throw error
        }
        _ = try await permission.approve(commandID: UUID(), actionID: actionID, expectedVersion: action.metadata.version, digest: action.digest)
        let outcome = try await permission.begin(actionID: actionID, digest: action.digest)
        guard outcome.applied else { throw NativeExecutionError.unknown }
        do {
            _ = try await service.authorize(call.name, context: context)
            let raw = try await service.perform(.init(operation, command: command, parameters: parameters))
            if operation == .start {
                await service.register(command: command, context: context, taskID: taskID, invocationID: outcome.resultID, project: project)
                return .object(["process_id": .string(command.id.uuidString), "state": .string("running"), "instruction": .string("Poll process_status until terminal. Starting a process is not successful completion.")])
            }
            let result = await service.redact(raw, project: project)
            let unknown = result.mcpFields["state"] == .string("unknown")
            try await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: unknown ? .unknown : .succeeded,
                result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch {
            let known = [NativeExecutionError.changed, .accessDenied, .busy, .invalidRequest, .programUnavailable].contains { error as? NativeExecutionError == $0 }
            let result = await service.redact(ChatJSON.object(["state": .string(known ? "failed" : "unknown"), "error": .string((error as? NativeExecutionError)?.localizedDescription ?? "Исход нативного действия неизвестен.")]), project: project)
            try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: known ? .failed : .unknown,
                result: String(decoding: try WorkspaceCoding.encode(result), as: UTF8.self))
            if error is CancellationError { throw error }
            return result
        }
    }
}
