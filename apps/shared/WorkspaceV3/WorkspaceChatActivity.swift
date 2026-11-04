import BlotDomain
import Foundation
import Observation

@MainActor @Observable
final class WorkspaceChatActivity {
    struct Draft: Equatable {
        let messageID: UUID
    }

    private(set) var readMessageIDs: Set<UUID> = []
    private(set) var drafts: [UUID: Draft] = [:]
    @ObservationIgnored private var tasks: [UUID: _Concurrency.Task<Void, Never>] = [:]
    @ObservationIgnored private var tails: [UUID: UUID] = [:]
    private var pending: [UUID: Set<UUID>] = [:]
    private(set) var onlineConversationIDs: Set<UUID> = []
    @ObservationIgnored private var presenceTasks: [UUID: _Concurrency.Task<Void, Never>] = [:]

    func isResponding(in conversationID: UUID) -> Bool { !(pending[conversationID]?.isEmpty ?? true) }
    func isTyping(in conversationID: UUID) -> Bool { drafts[conversationID] != nil }

    func activate(_ conversationID: UUID) {
        onlineConversationIDs.insert(conversationID)
        presenceTasks[conversationID]?.cancel()
        presenceTasks[conversationID] = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .seconds(30)) } catch { return }
            guard let self else { return }
            if self.isResponding(in: conversationID) { self.activate(conversationID) }
            else { self.onlineConversationIDs.remove(conversationID); self.presenceTasks[conversationID] = nil }
        }
    }

    func enqueue(message: BlotV3.Message, replies: [String], onRead: @escaping @MainActor () -> Void,
                 complete: @escaping @MainActor (String, Bool) -> Void) {
        let conversationID = message.conversationId
        let messageID = message.metadata.id
        let previous = tails[conversationID].flatMap { tasks[$0] }
        tails[conversationID] = messageID
        pending[conversationID, default: []].insert(messageID)
        activate(conversationID)
        tasks[messageID] = _Concurrency.Task { [weak self] in
            guard let self else { return }
            defer { self.finish(messageID: messageID, conversationID: conversationID) }
            try? await self.deliver(replies, messageID: messageID, conversationID: conversationID,
                                    previous: previous, onRead: onRead, complete: complete)
        }
    }

    private func deliver(_ replies: [String], messageID: UUID, conversationID: UUID,
                         previous: _Concurrency.Task<Void, Never>?, onRead: @MainActor () -> Void,
                         complete: @MainActor (String, Bool) -> Void) async throws {
        try await _Concurrency.Task.sleep(for: .seconds(1))
        readMessageIDs.insert(messageID)
        onRead()
        if let previous { await previous.value }
        try _Concurrency.Task.checkCancellation()
        try await _Concurrency.Task.sleep(for: .milliseconds(300))
        for (index, reply) in replies.enumerated() {
            try _Concurrency.Task.checkCancellation()
            if index > 0 { try await _Concurrency.Task.sleep(for: .seconds(1)) }
            drafts[conversationID] = Draft(messageID: messageID)
            try await _Concurrency.Task.sleep(for: .milliseconds(index == 0 ? 1100 : 2200))
            try _Concurrency.Task.checkCancellation()
            drafts[conversationID] = nil
            complete(reply, index == replies.count - 1)
        }
    }

    func cancelAll() {
        for task in tasks.values { task.cancel() }
        tasks = [:]; tails = [:]; drafts = [:]; readMessageIDs = []; pending = [:]
        for task in presenceTasks.values { task.cancel() }
        presenceTasks = [:]; onlineConversationIDs = []
    }

    func forgetReadMessages(_ ids: Set<UUID>) {
        readMessageIDs.subtract(ids)
    }

    func forgetConversation(_ id: UUID) {
        cancel(in: id)
        presenceTasks[id]?.cancel(); presenceTasks[id] = nil
        onlineConversationIDs.remove(id)
    }

    func cancel(in conversationID: UUID) {
        for id in pending[conversationID] ?? [] { tasks[id]?.cancel(); tasks[id] = nil }
        pending[conversationID] = nil; tails[conversationID] = nil; drafts[conversationID] = nil
    }

    private func finish(messageID: UUID, conversationID: UUID) {
        if drafts[conversationID]?.messageID == messageID { drafts[conversationID] = nil }
        tasks[messageID] = nil
        pending[conversationID]?.remove(messageID)
        if pending[conversationID]?.isEmpty == true {
            pending[conversationID] = nil
            activate(conversationID)
        }
        if tails[conversationID] == messageID { tails[conversationID] = nil }
    }
}
