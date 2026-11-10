import BlotDomain
import Foundation

/// Missing provider counts stay unknown; available counts are never estimated.
struct PhoneSettingsActivity {
    let inputTokens: Int
    let outputTokens: Int
    let calls: Int
    let uncountedCalls: Int
    let activeDays: Int
    let peakTokens: Int
    let dailyTokens: [Date: Int]
    let models: [Model]
    struct Model: Identifiable {
        let id: String
        let calls: Int
        let tokens: Int
    }
    init(snapshot: WorkspaceSnapshot, calendar: Calendar = .current) {
        let steps = snapshot.modelSteps ?? []
        inputTokens = steps.reduce(0) { $0 + ($1.inputTokens ?? 0) }
        outputTokens = steps.reduce(0) { $0 + ($1.outputTokens ?? 0) }
        calls = steps.count
        uncountedCalls = steps.filter { $0.inputTokens == nil || $0.outputTokens == nil }.count
        activeDays = Set(snapshot.messages.map { calendar.startOfDay(for: $0.metadata.createdAt) }).count
        peakTokens = steps.map { ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0) }.max() ?? 0
        dailyTokens = steps.reduce(into: [:]) { result, step in
            result[calendar.startOfDay(for: step.metadata.createdAt), default: 0] += (step.inputTokens ?? 0) + (step.outputTokens ?? 0)
        }
        models = Dictionary(grouping: steps, by: \.modelId).map { id, steps in
            Model(id: id, calls: steps.count, tokens: steps.reduce(0) { $0 + ($1.inputTokens ?? 0) + ($1.outputTokens ?? 0) })
        }.sorted { $0.id < $1.id }
    }
    var totalTokens: Int { inputTokens + outputTokens }
}
