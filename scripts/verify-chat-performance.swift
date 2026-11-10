import BlotAppleIntegrations
import BlotDesign
import BlotDomain
import BlotWorkspace
import Observation
import SwiftUI
import Synchronization

@MainActor @main
struct VerifyChatPerformance {
    static func main() throws {
        let owner = UUID(), workspace = UUID(), conversation = UUID(), now = Date()
        func metadata(_ id: UUID = UUID()) throws -> BlotV3.RecordMetadata {
            try .init(id: id, ownerId: owner, workspaceId: workspace, version: 1, createdAt: now, updatedAt: now)
        }
        let first = try BlotV3.AgentProfile(metadata: metadata(), name: "Architect", roleId: "custom", avatarShape: "round", avatarColor: "orange", instructions: "Help", modelId: "compatible", accessMode: .ask_first)
        let second = try BlotV3.AgentProfile(metadata: metadata(), name: "Reviewer", roleId: "custom", avatarShape: "round", avatarColor: "blue", instructions: "Help", modelId: "compatible", accessMode: .ask_first)
        var snapshot = WorkspaceSnapshot()
        snapshot.ownerID = owner; snapshot.agents = [first, second]
        snapshot.conversations = [try .init(metadata: metadata(conversation), agentId: first.metadata.id, title: "Large history", mobileOwned: false, pinned: false, archived: false, kind: .group)]
        snapshot.messages = try (0..<10000).map { index in
            try .init(metadata: metadata(), conversationId: conversation, role: index.isMultiple(of: 3) ? .user : .assistant,
                content: "Message \(index): **result** from @Architect and @Reviewer. Open @Mail and @Calendar.\nUnicode: Привет 👋. `@Mail` stays code.",
                delivery: .completed, commandId: UUID(), artifactIds: [], position: index + 1)
        }
        let index = WorkspaceMessageIndex(snapshot.messages)
        let visible = index.visibleMessages(in: conversation)
        precondition(visible.count == 10000 && index.message(snapshot.messages[4321].metadata.id) != nil)
        var window = WorkspaceTranscriptWindow()
        precondition(window.messages(in: visible).count == 80 && window.hasEarlier(in: visible))
        window.loadEarlier(); precondition(window.messages(in: visible).count == 160)
        window.reveal(visible[15].metadata.id, in: visible)
        precondition(window.messages(in: visible).contains { $0.metadata.id == visible[15].metadata.id })
        window.reset(); window.retainPosition(added: 3, followingLatest: false); precondition(window.count == 83)
        window.reset(); precondition(window.count == 80)
        print("PASS: 10,000-message history opens with 80 rows; older pages, pin/reply reveal and reading position remain available")

        let content = WorkspaceChatPresentation()
        content.update(snapshot, previous: WorkspaceSnapshot())
        let plan = WorkspaceGroupPlanProgress(summary: "Check changes", steps: [
            .init(agentID: first.metadata.id, name: first.name, task: "Implement"),
            .init(agentID: second.metadata.id, name: second.name, task: "Review")])
        let planID = UUID()
        func planMessage(_ text: String) throws -> BlotV3.Message {
            try .init(metadata: metadata(planID), conversationId: conversation, role: .assistant, content: text, delivery: .completed,
                      commandId: UUID(), artifactIds: [], authorAgentId: first.metadata.id)
        }
        let initialPlan = try planMessage(plan.markdown)
        let advancedPlan = try planMessage(plan.updating(agentID: first.metadata.id, completed: true).markdown)
        precondition(content.plan(for: initialPlan)?.completedCount == 0)
        precondition(content.plan(for: advancedPlan)?.completedCount == 1)
        precondition(content.plan(for: snapshot.messages[1]) == nil)
        let response = snapshot.messages[1]
        let mail = AppleToolCatalog.all.first { $0.plugin == .mail }!.definition.name
        let calendar = AppleToolCatalog.all.first { $0.plugin == .calendar }!.definition.name
        func step(_ name: String) throws -> BlotV3.ModelStep {
            let request = try JSONSerialization.data(withJSONObject: ["messages": [["role": "tool", "toolCallID": "call", "name": name, "content": String(repeating: "recorded output ", count: 1000)]]])
            return try .init(metadata: metadata(planID), conversationId: conversation, sourceMessageId: snapshot.messages[0].metadata.id,
                responseMessageId: response.metadata.id, executorDeviceId: owner, originDeviceId: owner, executionMode: .local_owned,
                stepIndex: 0, modelId: "compatible", budgetTokenLimit: 20000, requestJSON: String(decoding: request, as: UTF8.self), state: .completed)
        }
        // Use a response without an inline mention, so the durable tool badge remains visible.
        let plain = try BlotV3.Message(metadata: response.metadata, conversationId: conversation, role: .assistant, content: "Completed", delivery: .completed, commandId: UUID(), artifactIds: [])
        var updated = snapshot; updated.modelSteps = [try step(mail)]
        content.update(updated, previous: snapshot)
        precondition(content.plugins(for: plain).first?.entry.appleID == .mail)
        let previous = updated; updated.modelSteps = [try step(calendar)]
        content.update(updated, previous: previous)
        precondition(content.plugins(for: plain).first?.entry.appleID == .calendar)
        precondition(WorkspacePluginReference.mentionedIDs(in: "`@Mail` [@Calendar](https://example.com)").isEmpty)
        precondition(!WorkspacePluginReference.mentionedIDs(in: "Use @Mail").isEmpty)
        print("PASS: same-version plan and tool changes invalidate cached results; inline code and links retain their meaning")

        let flag = Mutex(false)
        withObservationTracking { _ = content.agents; _ = content.conversations; _ = content.artifacts; _ = content.reactions } onChange: { flag.withLock { $0 = true } }
        var toolOnly = updated; toolOnly.modelSteps = []
        content.update(toolOnly, previous: updated)
        precondition(!flag.withLock { $0 } && content.plugins(for: plain).isEmpty)
        print("PASS: tool-only changes do not invalidate message authors, attachments, reactions or conversation identity")

        content.update(updated, previous: toolOnly)
        _ = content.plugins(for: plain)
        let badgeClock = ContinuousClock()
        let uncachedStart = badgeClock.now
        for _ in 0..<400 { precondition(WorkspaceMessagePluginAttribution().references(for: plain, steps: updated.modelSteps!).count == 1) }
        let uncachedBadges = uncachedStart.duration(to: badgeClock.now)
        let cachedStart = badgeClock.now
        for _ in 0..<400 { precondition(content.plugins(for: plain).count == 1) }
        print("BADGE BENCHMARK: 400 lookups with a 16 KB tool log; uncached=\(uncachedBadges), cached=\(cachedStart.duration(to: badgeClock.now))")

        let dense = ProcessInfo.processInfo.environment["BLOT_CHAT_DENSE"] == "1"
        let sample = try snapshot.messages.suffix(40).map { message in
            guard dense else { return message }
            return try BlotV3.Message(metadata: message.metadata, conversationId: conversation, role: message.role,
                content: String(repeating: "**Result** from @Architect and @Reviewer; use @Mail. Unicode 👋. ", count: 12),
                delivery: message.delivery, commandId: message.commandId, artifactIds: [])
        }
        let clock = ContinuousClock()
        let start = clock.now
        for _ in 0..<8 {
            try autoreleasepool {
                let renderer = ImageRenderer(content: VStack(alignment: .leading) {
                    ForEach(sample, id: \.metadata.id) { message in
                        WorkspaceMessageText(text: message.content, agents: snapshot.agents).font(.system(size: 13))
                    }
                }.frame(width: 660, height: 1200, alignment: .top).clipped())
                renderer.scale = 1
                guard renderer.cgImage != nil else { throw CocoaError(.coderInvalidValue) }
            }
        }
        print("RENDER BENCHMARK: 40 \(dense ? "mention-heavy" : "rich") messages × 8 actual SwiftUI image renders: \(start.duration(to: clock.now))")
    }
}
