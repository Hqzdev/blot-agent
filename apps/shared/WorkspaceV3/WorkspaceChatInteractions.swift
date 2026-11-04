import Foundation

struct WorkspaceMessageMetadata: Codable, Equatable {
    var replyToMessageID: UUID?
    var reaction: String?
    var reactedAt: Date?
}

struct WorkspaceChatInteractions: Codable, Equatable {
    static let reactions = ["👍", "❤️", "😂", "😮", "😢", "🔥"]
    var pinnedOrder: [UUID] = []
    var messages: [UUID: WorkspaceMessageMetadata] = [:]
    var unreadMessageIDs: [UUID: Set<UUID>]?
    var manuallyUnreadIDs: Set<UUID>?
    var mutedConversationIDs: Set<UUID>?
    var agentReadMessageIDs: Set<UUID>?

    func unreadCount(in conversationID: UUID) -> Int {
        max(unreadMessageIDs?[conversationID]?.count ?? 0, manuallyUnreadIDs?.contains(conversationID) == true ? 1 : 0)
    }
    func isMuted(_ id: UUID) -> Bool { mutedConversationIDs?.contains(id) == true }
    mutating func receive(_ messageID: UUID, in conversationID: UUID) {
        if unreadMessageIDs == nil { unreadMessageIDs = [:] }
        unreadMessageIDs?[conversationID, default: []].insert(messageID)
    }
    mutating func markRead(_ id: UUID) { unreadMessageIDs?[id] = nil; manuallyUnreadIDs?.remove(id) }
    mutating func markUnread(_ id: UUID) {
        if manuallyUnreadIDs == nil { manuallyUnreadIDs = [] }
        manuallyUnreadIDs?.insert(id)
    }
    mutating func toggleMute(_ id: UUID) {
        if mutedConversationIDs == nil { mutedConversationIDs = [] }
        if isMuted(id) { mutedConversationIDs?.remove(id) } else { mutedConversationIDs?.insert(id) }
    }
    mutating func agentRead(_ messageID: UUID) {
        if agentReadMessageIDs == nil { agentReadMessageIDs = [] }
        agentReadMessageIDs?.insert(messageID)
    }
    mutating func forgetConversation(_ id: UUID) {
        pinnedOrder.removeAll { $0 == id }; markRead(id); mutedConversationIDs?.remove(id)
    }

    mutating func removeMessages(_ ids: Set<UUID>) {
        agentReadMessageIDs?.subtract(ids)
        for id in ids { messages[id] = nil }
        for (id, metadata) in messages where metadata.replyToMessageID.map(ids.contains) == true {
            messages[id]?.replyToMessageID = nil
        }
    }
}
