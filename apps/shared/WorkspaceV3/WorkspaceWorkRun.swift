import BlotDomain
import BlotWorkspace
import Foundation

/// A run spans model turns for one request and one author, never the next user's task.
nonisolated struct WorkspaceWorkRun: Identifiable, Sendable {
    let messages: [BlotV3.Message]
    let steps: [BlotV3.ModelStep]
    let activityIDs: Set<UUID>
    let isRunning: Bool
    var id: UUID { messages[0].metadata.id }
    var final: BlotV3.Message? {
        guard let last = messages.last, !activityIDs.contains(last.metadata.id),
              [.completed, .failed, .interrupted, .canceled].contains(last.delivery) else { return nil }
        return last
    }
    var progress: [BlotV3.Message] { messages.filter { $0.metadata.id != final?.metadata.id } }
    var artifactIDs: [UUID] {
        var seen: Set<UUID> = []
        return messages.flatMap(\.artifactIds).filter { seen.insert($0).inserted }
    }
    var changeArtifactIDs: [UUID] {
        var seen: Set<UUID> = []
        return steps.flatMap { step -> [UUID] in
            guard let raw = step.toolResultsJSON, raw.utf8.count <= 4_194_304,
                  let results = try? JSONDecoder().decode([String: ChatJSON].self, from: Data(raw.utf8)) else { return [] }
            return results.values.compactMap { value in
                guard case .object(let fields) = value, case .string(let id) = fields["change_artifact_id"] else { return nil }
                return UUID(uuidString: id)
            }
        }.filter { seen.insert($0).inserted }
    }
    var seconds: Int {
        let start = steps.map(\.metadata.createdAt).min() ?? messages[0].metadata.createdAt
        let end = final?.metadata.updatedAt ?? steps.map(\.metadata.updatedAt).max() ?? messages.last!.metadata.updatedAt
        return max(1, Int(ceil(end.timeIntervalSince(start))))
    }
    var failed: Bool { steps.contains { [.failed, .interrupted, .canceled].contains($0.state) } || final.map { $0.delivery != .completed } == true }
    func summary(russian: Bool) -> String {
        let duration = seconds >= 60 ? "\(seconds / 60)" + (russian ? "м " : "m ") + "\(seconds % 60)" + (russian ? "с" : "s") : "\(seconds)" + (russian ? "с" : "s")
        return (failed ? (russian ? "Работа остановлена · " : "Work stopped · ") : (russian ? "Работа заняла " : "Worked for ")) + duration
    }
    static func hasCalls(_ step: BlotV3.ModelStep) -> Bool {
        guard let raw = step.toolCallsJSON, raw.utf8.count <= 4_194_304 else { return false }
        return (try? JSONDecoder().decode([ChatToolCall].self, from: Data(raw.utf8)))?.isEmpty == false
    }
    static func groups(messages: [BlotV3.Message], steps: [BlotV3.ModelStep], responding: Bool) -> [UUID: Self] {
        let indexed = Dictionary(grouping: steps, by: \.responseMessageId)
        var groups: [[BlotV3.Message]] = []
        for message in messages {
            guard message.role == .assistant else { groups.append([message]); continue }
            if let previous = groups.last?.last, !WorkspaceMessageSeries.starts(message, after: previous) { groups[groups.count - 1].append(message) }
            else { groups.append([message]) }
        }
        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard group[0].role == .assistant else { return nil }
            let steps = group.flatMap { indexed[$0.metadata.id] ?? [] }
            let activityIDs = Set(steps.filter(hasCalls).map(\.responseMessageId))
            guard !activityIDs.isEmpty else { return nil }
            var run = Self(messages: group, steps: steps, activityIDs: activityIDs, isRunning: false)
            run = Self(messages: group, steps: steps, activityIDs: activityIDs, isRunning: run.final == nil && responding && group.last?.commandId == messages.last?.commandId)
            return (run.id, run)
        })
    }
}
