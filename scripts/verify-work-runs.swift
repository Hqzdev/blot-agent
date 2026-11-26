import BlotDomain
import BlotWorkspace
import Foundation

@main struct VerifyWorkRuns {
    static func main() throws {
        let owner = UUID(), workspace = UUID(), conversation = UUID(), command = UUID(), agent = UUID()
        func metadata(_ id: UUID = UUID(), seconds: Double = 0) throws -> BlotV3.RecordMetadata {
            try .init(id: id, ownerId: owner, workspaceId: workspace, version: 1,
                createdAt: Date(timeIntervalSince1970: seconds), updatedAt: Date(timeIntervalSince1970: seconds))
        }
        func message(_ text: String, user: Bool = false, commandID: UUID? = nil, author: UUID? = nil, delivery: BlotV3.DeliveryState = .completed, seconds: Double = 0) throws -> BlotV3.Message {
            try .init(metadata: metadata(seconds: seconds), conversationId: conversation, role: user ? .user : .assistant,
                content: text, delivery: delivery, commandId: commandID ?? command, artifactIds: [], authorAgentId: user ? nil : author ?? agent)
        }
        let user = try message("Create a report", user: true)
        let progress = try message("Creating a folder")
        let toolOnly = try message("")
        let final = try message("Done: report ready", seconds: 125)
        func step(_ response: BlotV3.Message, index: Int) throws -> BlotV3.ModelStep {
            try .init(metadata: metadata(seconds: Double(index)), conversationId: conversation, sourceMessageId: user.metadata.id,
                responseMessageId: response.metadata.id, executorDeviceId: owner, originDeviceId: owner, executionMode: .local_owned,
                stepIndex: index, modelId: "test", budgetTokenLimit: 10000, requestJSON: "{}",
                toolCallsJSON: "[{\"id\":\"call-\(index)\",\"name\":\"workspace_write_file\",\"arguments\":{}}]", state: .completed)
        }
        let steps = try [step(progress, index: 0), step(toolOnly, index: 1)]
        let live = WorkspaceWorkRun.groups(messages: [user, progress, toolOnly], steps: steps, responding: true)
        let active = live[progress.metadata.id]!
        precondition(active.isRunning && active.final == nil && active.progress.count == 2)
        let complete = WorkspaceWorkRun.groups(messages: [user, progress, toolOnly, final], steps: steps, responding: true)
        let run = complete[progress.metadata.id]!
        precondition(complete.count == 1 && run.id == active.id && !run.isRunning)
        precondition(run.final?.metadata.id == final.metadata.id && run.progress.count == 2 && run.seconds == 125)
        precondition(run.summary(russian: false) == "Worked for 2m 5s")
        let nextCommand = UUID(), nextUser = try message("Next task", user: true, commandID: nextCommand)
        let nextProgress = try message("Checking", commandID: nextCommand)
        let moreSteps = try steps + [step(nextProgress, index: 2)]
        let separate = WorkspaceWorkRun.groups(messages: [user, progress, final, nextUser, nextProgress], steps: moreSteps, responding: true)
        precondition(separate.count == 2 && separate[progress.metadata.id]?.final?.metadata.id == final.metadata.id)
        let interrupted = try message("Only part of the task finished", delivery: .interrupted, seconds: 40)
        let stopped = WorkspaceWorkRun.groups(messages: [user, progress, interrupted], steps: steps, responding: false)[progress.metadata.id]!
        precondition(stopped.failed && !stopped.isRunning && stopped.final?.metadata.id == interrupted.metadata.id)
        let ordinary = WorkspaceWorkRun.groups(messages: [user, final], steps: [], responding: false)
        precondition(ordinary.isEmpty)
        let difference = WorkspaceTextDifference(before: "One\nTwo\n", after: "One\nUpdated\nThree\n")
        precondition(difference.added == 2 && difference.removed == 1)
        print("PASS: live work stays expanded; final answer folds one run; subsequent tasks stay separate; interrupted work is retained; durations and line changes use recorded evidence")
    }
}
