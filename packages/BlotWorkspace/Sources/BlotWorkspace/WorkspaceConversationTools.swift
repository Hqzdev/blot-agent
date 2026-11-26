import Foundation
import BlotDomain

/// Questions are explicit structured tool results, never extracted from assistant prose.
public struct WorkspaceConversationTools: WorkspaceToolExecuting {
    public static let toolIDs = ["conversation_ask", "subscription_plans", "connection_status", "secure_input_request"]
    private let repository: WorkspaceRepository
    private let identity: WorkspaceIdentity
    public init(repository: WorkspaceRepository, identity: WorkspaceIdentity) { self.repository = repository; self.identity = identity }
    public var definitions: [ChatToolDefinition] {
        [.init(name: "connection_status", description: "Show the actual state of an installed MCP app. Omit connection_id to list account app IDs first. Added does not mean authenticated or connected.", parameters: .object([
            "type": .string("object"), "properties": .object(["connection_id": .object(["type": .string("string")])]), "required": .array([])])),
         .init(name: "secure_input_request", description: "Request an API key or service token in a native secure field. Value stays in device Keychain; only a reference is returned. Saving does not configure or connect an app. Never request passwords or payment details.", parameters: .object([
            "type": .string("object"), "properties": .object(["purpose": .object(["type": .string("string")]), "name": .object(["type": .string("string"), "enum": .array([.string("API key"), .string("Service token")])])]),
            "required": .array([.string("purpose"), .string("name")])])),
         .init(name: "conversation_ask", description: "Ask the owner a required question inline. Waits for their answer. Do not ask for passwords, tokens, or payment details.", parameters: .object([
            "type": .string("object"), "properties": .object([
                "question": .object(["type": .string("string")]),
                "choices": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                "allow_custom": .object(["type": .string("boolean")])]),
            "required": .array([.string("question"), .string("choices"), .string("allow_custom")])])),
         .init(name: "subscription_plans", description: "Show Ori subscription plans and a link to the website checkout. Never request card details in chat.",
               parameters: .object(["type": .string("object"), "properties": .object([:]), "required": .array([])]))]
    }
    public func execute(_ call: ChatToolCall, context: WorkspaceToolContext) async throws -> ChatJSON {
        let service = WorkspaceConversationCardService(repository: repository, identity: identity)
        let id = WorkspaceToolCallIdentity.actionID(workspaceID: identity.workspaceID, sourceID: context.sourceMessageID, callID: call.id)
        switch call.name {
        case "connection_status":
            if case .object(let fields) = call.arguments, fields["connection_id"] == nil {
                let connections = try await repository.records(BlotV3.McpConnection.self, workspaceID: identity.workspaceID).filter { $0.metadata.ownerId == identity.ownerID }
                return .object(["apps": .array(connections.map { .object(["connection_id": .string($0.metadata.id.uuidString), "name": .string($0.name), "state": .string($0.state.rawValue)]) })])
            }
            guard case .object(let fields) = call.arguments, case .string(let raw) = fields["connection_id"], let connectionID = UUID(uuidString: raw),
                  let connection = try await repository.record(BlotV3.McpConnection.self, id: connectionID, workspaceID: identity.workspaceID),
                  connection.metadata.ownerId == identity.ownerID else { throw WorkspaceStorageError.missingRecord }
            try await service.create(id: id, sourceMessageID: context.sourceMessageID, operationID: connectionID, agentID: context.agentID,
                content: .plugin(.init(name: connection.name, detail: "", connectionID: connectionID)))
            return .object(["state": .string(connection.state.rawValue)])
        case "secure_input_request":
            guard case .object(let fields) = call.arguments, case .string(let purpose) = fields["purpose"], case .string(let name) = fields["name"] else { throw WorkspaceToolError.invalidArguments }
            let reference = "card:" + identity.ownerID.uuidString + ":" + id.uuidString
            try await service.create(id: id, sourceMessageID: context.sourceMessageID, operationID: id, agentID: context.agentID,
                content: .credential(.init(name: name, purpose: purpose, reference: reference)))
            let response = try await service.waitForResponse(cardID: id)
            return .object(["state": .string(response.action), "secret_ref": response.action == "saved" ? .string(reference) : .null])
        case "conversation_ask":
            guard case .object(let fields) = call.arguments, case .string(let prompt) = fields["question"],
                  case .array(let rawChoices) = fields["choices"], case .bool(let custom) = fields["allow_custom"] else { throw WorkspaceToolError.invalidArguments }
            let choices = try rawChoices.map { value -> String in
                guard case .string(let text) = value else { throw WorkspaceToolError.invalidArguments }; return text
            }
            try await service.create(id: id, sourceMessageID: context.sourceMessageID, operationID: id, agentID: context.agentID,
                content: .question(.init(prompt: prompt, choices: choices, allowsCustomAnswer: custom)))
            let response = try await service.waitForResponse(cardID: id)
            return .object(["answer": response.value.map(ChatJSON.string) ?? .null, "state": .string(response.action == "submit" ? "answered" : "dismissed")])
        case "subscription_plans":
            guard let url = URL(string: "https://blot-agent.vercel.app/app/pricing?cardId=" + id.uuidString) else { throw WorkspaceToolError.invalidArguments }
            try await service.create(id: id, sourceMessageID: context.sourceMessageID, operationID: id, agentID: context.agentID,
                content: .subscription(.init(checkoutURL: url)))
            return .object(["state": .string("awaiting_website_checkout"), "url": .string(url.absoluteString)])
        default: throw WorkspaceToolError.unknownTool
        }
    }
}
