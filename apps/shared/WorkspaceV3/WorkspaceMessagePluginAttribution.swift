import BlotAppleIntegrations
import BlotDomain
import BlotWorkspace
import Foundation

struct WorkspaceMessagePluginAttribution {
    func references(for message: BlotV3.Message, steps: [BlotV3.ModelStep]) -> [WorkspacePluginReference] {
        guard message.role == .assistant else { return [] }
        var names: [String] = []
        for step in steps where step.responseMessageId == message.metadata.id {
            // Runtime appends tool messages only after executing their matching calls.
            if let request = try? JSONDecoder().decode(ToolContext.self, from: Data(step.requestJSON.utf8)) {
                names += request.messages.compactMap { $0.role == "tool" && $0.toolCallID != nil ? $0.name : nil }
            }
            if let raw = step.toolCallsJSON, let results = step.toolResultsJSON,
               let calls = try? JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8)),
               let values = try? JSONDecoder().decode([String: ChatJSON].self, from: Data(results.utf8)) {
                names += calls.filter { values[$0.id] != nil }.map(\.name)
            }
        }
        var seen = WorkspacePluginReference.mentionedIDs(in: message.content)
        return names.compactMap { name in
            guard let plugin = WorkspacePluginReference.plugin(forTool: name), seen.insert(plugin.entry.id).inserted else { return nil }
            return plugin
        }
    }
    private struct ToolContext: Decodable {
        let messages: [Message]
        struct Message: Decodable { let role: String; let name: String?; let toolCallID: String? }
    }
}
