import BlotDomain
import Foundation

/// Only recorded usage is counted; missing provider token counts stay unknown.
struct MacSettingsActivity {
    let inputTokens: Int
    let outputTokens: Int
    let uncountedSteps: Int
    let calls: Int
    let activeDays: Int
    let peakTokens: Int
    let dailyTokens: [Date: Int]

    init(snapshot: WorkspaceSnapshot, calendar: Calendar = .current) {
        let steps = snapshot.modelSteps ?? []
        inputTokens = steps.reduce(0) { $0 + ($1.inputTokens ?? 0) }
        outputTokens = steps.reduce(0) { $0 + ($1.outputTokens ?? 0) }
        calls = steps.count
        uncountedSteps = steps.filter { $0.inputTokens == nil || $0.outputTokens == nil }.count
        peakTokens = steps.map { ($0.inputTokens ?? 0) + ($0.outputTokens ?? 0) }.max() ?? 0
        activeDays = Set(snapshot.messages.map { calendar.startOfDay(for: $0.metadata.createdAt) }).count
        dailyTokens = steps.reduce(into: [:]) { result, step in
            result[calendar.startOfDay(for: step.metadata.createdAt), default: 0] += (step.inputTokens ?? 0) + (step.outputTokens ?? 0)
        }
    }
    var totalTokens: Int { inputTokens + outputTokens }
}
