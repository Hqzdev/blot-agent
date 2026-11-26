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
    public func invalidArgumentsResult(for call: ChatToolCall) -> ChatJSON? {
        .object(["state": .string("failed"), "error": .string("invalid_arguments"),
                 "instruction": .string(call.name == "browser_attach"
                    ? "Call browser_attach with an empty object to request approval for the selected tab."
                    : "Check the argument schema. For element actions, get IDs from a fresh browser_snapshot.")])
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        do { return try await perform(call, context: context) }
        catch is CancellationError { throw CancellationError() }
        catch {
            let failure = error as? WorkspaceBrowserError
            return .object(["state": .string(failure == .unknown ? "unknown" : "failed"),
                            "code": .string(failure?.rawValue ?? "operationFailed"),
                            "error": .string(failure?.localizedDescription ?? "Действие браузера не выполнено.")])
        }
    }
    private func perform(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        let authorized = try await service.authorize(call.name, context: context)
        let actionID = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id, scope: .browser)
        let command = WorkspaceBrowserCommand(id: actionID, name: call.name, arguments: call.arguments, scope: authorized.scope, origins: authorized.origins, sessionKey: authorized.sessionKey)
        if call.name == "browser_profiles" {
            return .object(["profiles": .array(await service.browserProfiles().map { .object(["id": .string($0.id.uuidString), "name": .string($0.name)]) })])
        }
        if call.name == "browser_copy_cookies" { return try await copyCookies(call, context: context, command: command) }
        if call.name == "browser_request_takeover" {
            guard case .object(let arguments) = call.arguments, case .string(let reason) = arguments["reason"],
                  case .string(let rawTab) = arguments["tab_id"], let tabID = UUID(uuidString: rawTab) else { throw WorkspaceBrowserError.invalidURL }
            let snapshot = WorkspaceBrowserCommand(id: actionID, name: "browser_snapshot", arguments: .object(["tab_id": .string(rawTab)]),
                scope: authorized.scope, origins: authorized.origins, sessionKey: authorized.sessionKey)
            _ = try await service.prepare(snapshot)
            try await service.beginManual(command, tabID: tabID)
            do {
                let cards = WorkspaceConversationCardService(repository: repository, identity: identity)
                try await cards.create(id: actionID, sourceMessageID: context.sourceMessageID, operationID: actionID, agentID: context.agentID,
                    content: .takeover(.init(reason: reason, tabID: tabID)))
                let response = try await cards.waitForResponse(cardID: actionID)
                await service.endManual(command)
                return .object(["state": .string(response.action == "done" ? "manual_step_completed" : "manual_step_skipped"),
                    "instruction": .string("Read a fresh snapshot. Manual completion is not proof that the website action succeeded.")])
            } catch { await service.endManual(command); throw error }
        }
        if !WorkspaceBrowserCatalog.recordsAction(call.name) {
            let binding = try await service.prepare(command)
            let resource = (try? WorkspaceBrowserURL.origin(WorkspaceBrowserURL.validated(binding.url))) ?? ""
            if try await WorkspaceRuleService(repository: repository, identity: identity).requiresReview(toolID: call.name,
                resource: resource, agentID: context.agentID, default: false) {
                guard try await confirm(call.name, binding.url) else { throw WorkspaceBrowserError.canceled }
            }
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
        let purchase: WorkspacePurchaseOrder?
        if call.name == "browser_purchase" {
            guard case .object(let fields) = call.arguments, case .string(let raw) = fields["order_json"], raw.utf8.count <= 32_000 else { throw WorkspaceToolError.invalidArguments }
            let order = try JSONDecoder().decode(WorkspacePurchaseOrder.self, from: Data(raw.utf8))
            try order.validate()
            guard order.checkoutURL.absoluteString == binding.url else { throw WorkspaceBrowserError.stalePage }
            purchase = order
        } else { purchase = nil }
        let target = try? JSONDecoder().decode(BrowserTarget.self, from: Data(binding.target.utf8))
        let site = try WorkspaceBrowserURL.origin(WorkspaceBrowserURL.validated(binding.url))
        let title: String
        let details: String
        switch call.name {
        case "browser_attach":
            title = "Разрешить управление вкладкой"
            details = "Сайт: \(site)\nАгент получит управление этой вкладкой до завершения текущего запуска."
        case "browser_type":
            title = "Ввести текст на сайте"
            details = "Сайт: \(site)\nПоле: \(target?.displayLabel ?? "Текстовое поле")"
        default:
            title = "Подтвердить действие на сайте"
            details = "Сайт: \(site)\nЭлемент: \(target?.displayLabel ?? "Кнопка на странице")\nНажатие может отправить форму или изменить данные сайта."
        }
        let input: String
        if call.name == "browser_type", case .object(let fields) = call.arguments, case .string(let text) = fields["text"] {
            guard text.utf8.count <= 8192, !text.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) else {
                throw WorkspaceBrowserError.denied
            }
            input = text.isEmpty ? "\n\nОчистить поле" : "\n\nТекст для ввода:\n" + text
        } else { input = "" }
        let parameters = String(decoding: try WorkspaceCoding.encode(Parameters(arguments: call.arguments, binding: binding)), as: UTF8.self)
        let taskID: UUID
        if let existing = context.taskID { taskID = existing }
        else {
            guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID) else {
                throw WorkspaceBrowserError.denied
            }
            taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(),
                conversationID: source.conversationId, agentID: authorized.scope.agentID, goal: "Действие во встроенном браузере", executorDeviceID: identity.deviceID, runnable: false)
        }
        let id = try await permission.prepare(commandID: actionID, taskID: taskID,
            draft: .init(toolID: call.name, resource: "browser:" + binding.tabID.uuidString,
                parametersJSON: parameters, consequences: String(details.prefix(3500))), expiresAt: Date().addingTimeInterval(300))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: id, workspaceID: identity.workspaceID) else { throw WorkspaceBrowserError.unknown }
        do {
            let accepted: Bool
            if let purchase {
                let response = try await WorkspaceConversationCardService(repository: repository, identity: identity)
                    .review(action: action, context: context, content: .purchase(purchase))
                accepted = response.action == "allow"
            } else {
                var automatic = call.name == "browser_click" && target?.navigation == true
                #if os(macOS)
                automatic = automatic || (call.name == "browser_type" && target?.ordinaryInput == true)
                #endif
                let review = try await WorkspaceRuleService(repository: repository, identity: identity).requiresReview(toolID: call.name,
                    resource: site, agentID: context.agentID, default: false, mandatory: !automatic)
                if !review { accepted = true }
                else if context.inlineCards {
                    let card = WorkspaceCardContent.command(.init(title: title, details: details + input, command: call.name))
                    let response = try await WorkspaceConversationCardService(repository: repository, identity: identity)
                        .review(action: action, context: context, content: card)
                    accepted = response.action == "allow"
                } else { accepted = try await confirm(title, details + input) }
            }
            guard accepted else { throw WorkspaceBrowserError.canceled }
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
            let known = [WorkspaceBrowserError.stalePage, .denied, .unavailable].contains(error as? WorkspaceBrowserError ?? .unknown)
            try? await permission.finish(commandID: UUID(), invocationID: outcome.resultID, state: known ? .failed : .unknown)
            if error is CancellationError { throw error }; throw known ? error : WorkspaceBrowserError.unknown
        }
    }
    private struct BrowserTarget: Decodable {
        let label: String
        let navigation: Bool
        let ordinaryInput: Bool
        var displayLabel: String? { label.isEmpty ? nil : label }
    }
    private struct Parameters: Codable { let arguments: ChatJSON; let binding: WorkspaceBrowserBinding }
    private func copyCookies(_ call: ChatToolCall, context: WorkspaceToolContext, command: WorkspaceBrowserCommand) async throws -> ChatJSON {
        guard case .object(let arguments) = call.arguments,
              case .string(let rawSource) = arguments["source_profile_id"], let sourceID = UUID(uuidString: rawSource),
              case .string(let rawDestination) = arguments["destination_profile_id"], let destinationID = UUID(uuidString: rawDestination),
              case .array(let items) = arguments["domains"] else { throw WorkspaceBrowserError.denied }
        let domains = try items.map { item -> String in
            guard case .string(let domain) = item else { throw WorkspaceBrowserError.denied }
            let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard command.origins.contains("*") || command.origins.contains("https://" + host) else { throw WorkspaceBrowserError.denied }
            return host
        }
        let transfer = WorkspaceCardContent.CookieTransfer(sourceProfileID: sourceID, destinationProfileID: destinationID, domains: domains)
        try WorkspaceCardContent.cookies(transfer).validate()
        let profiles = await service.browserProfiles()
        guard profiles.contains(where: { $0.id == sourceID }), profiles.contains(where: { $0.id == destinationID }) else { throw WorkspaceBrowserError.denied }
        let permission = WorkspacePermissionService(repository: repository, identity: identity)
        if let old = try await repository.record(BlotV3.PreparedAction.self, id: command.id, workspaceID: identity.workspaceID) {
            guard old.toolId == call.name, try WorkspaceCoding.decode(ChatJSON.self, from: Data(old.parameters.utf8)) == call.arguments else { throw WorkspaceBrowserError.denied }
            if let invocation = try await repository.projection(identity: identity).invocations.first(where: { $0.preparedActionId == command.id }),
               invocation.state == .succeeded, let raw = invocation.result { return try WorkspaceCoding.decode(ChatJSON.self, from: Data(raw.utf8)) }
            throw WorkspaceBrowserError.unknown
        }
        guard let source = try await repository.record(BlotV3.Message.self, id: context.sourceMessageID, workspaceID: identity.workspaceID), let agentID = context.agentID else { throw WorkspaceBrowserError.denied }
        let taskID: UUID
        if let task = context.taskID { taskID = task }
        else { taskID = try await WorkspaceTaskService(repository: repository, identity: identity).create(commandID: UUID(), conversationID: source.conversationId,
            agentID: agentID, goal: "Перенос входа между профилями Ori", executorDeviceID: identity.deviceID, runnable: false) }
        _ = try await permission.prepare(commandID: command.id, taskID: taskID, draft: .init(toolID: call.name, resource: "browser-profile:" + destinationID.uuidString,
            parametersJSON: String(decoding: WorkspaceCoding.encode(call.arguments), as: UTF8.self), consequences: "Copy cookies for: " + domains.joined(separator: ", ")), expiresAt: Date().addingTimeInterval(600))
        guard let action = try await repository.record(BlotV3.PreparedAction.self, id: command.id, workspaceID: identity.workspaceID) else { throw WorkspaceBrowserError.unknown }
        var selectedTransfer = transfer
        do {
            let response = try await WorkspaceConversationCardService(repository: repository, identity: identity).review(action: action, context: context, content: .cookies(transfer))
            guard ["allow", "allow_domains"].contains(response.action) else { throw WorkspaceBrowserError.canceled }
            let selected = try WorkspaceConversationCardService.selectedCookieDomains(response, transfer: transfer)
            selectedTransfer = .init(sourceProfileID: sourceID, destinationProfileID: destinationID, domains: selected)
            _ = try await service.authorize(call.name, context: context)
            _ = try await permission.approve(commandID: UUID(), actionID: command.id, expectedVersion: action.metadata.version, digest: action.digest)
        } catch {
            try? await permission.deny(commandID: UUID(), actionID: command.id, expectedVersion: action.metadata.version)
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).cancel(commandID: UUID(), taskID: taskID) }
            throw error
        }
        let invocation = try await permission.begin(actionID: command.id, digest: action.digest)
        guard invocation.applied else { throw WorkspaceBrowserError.unknown }
        do {
            let count = try await service.copyCookies(selectedTransfer)
            let result = ChatJSON.object(["state": .string("succeeded"), "cookie_count": .number(Double(count))])
            try await permission.finish(commandID: UUID(), invocationID: invocation.resultID, state: .succeeded, result: String(decoding: WorkspaceCoding.encode(result), as: UTF8.self))
            if context.taskID == nil { try? await WorkspaceTaskService(repository: repository, identity: identity).completeActionTask(taskID: taskID) }
            return result
        } catch { try? await permission.finish(commandID: UUID(), invocationID: invocation.resultID, state: .unknown); throw error }
    }
    private func result(_ operation: WorkspaceBrowserResult, call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        switch operation {
        case .value(let value): return value
        case .image(let data):
            guard data.count <= 4 * 1024 * 1024 else { throw WorkspaceBrowserError.unavailable }
            let id = try await files.store(commandID: WorkspaceLogicalID.make(kind: "BrowserImage", workspaceID: identity.workspaceID, parts: [context.sourceMessageID.uuidString, call.id]),
                name: "browser.png", mediaType: "image/png", data: data, taskID: context.taskID)
            return .object(["artifact_id": .string(id.uuidString), "name": .string("browser.png"), "url": .string(WorkspaceResultLink.url(for: id).absoluteString)])
        }
    }
}
