import BlotDomain
import SwiftUI

/// Presentation groups reflect the sender and actual delivery time, not paragraph breaks.
enum PhoneMessageTimeline {
    struct Row: Identifiable {
        let message: BlotV3.Message
        let spacing: CGFloat
        let showsDelivery: Bool
        let showsAuthor: Bool
        var id: UUID { message.metadata.id }
    }

    static func rows(in messages: [BlotV3.Message], activityMessageIDs: Set<UUID> = []) -> [Row] {
        let visible = messages.filter { WorkspaceMessagePresentation.isVisible($0) || activityMessageIDs.contains($0.metadata.id) }
        return visible.enumerated().map { index, message in
            let previous = index > 0 ? visible[index - 1] : nil
            let next = index + 1 < visible.count ? visible[index + 1] : nil
            let error = [.failed, .interrupted, .canceled].contains(message.delivery)
            return Row(message: message, spacing: spacing(before: message, previous: previous),
                       showsDelivery: error || (message.role == .user && !consecutive(message, next)),
                       showsAuthor: WorkspaceMessageSeries.starts(message, after: previous))
        }
    }

    private static func spacing(before message: BlotV3.Message, previous: BlotV3.Message?) -> CGFloat {
        guard let previous else { return 0 }
        if message.role == .assistant, !WorkspaceMessageSeries.starts(message, after: previous) { return 12 }
        if consecutive(previous, message) { return 4 }
        return message.metadata.createdAt.timeIntervalSince(previous.metadata.createdAt) >= 120 ? 32 : 22
    }

    private static func consecutive(_ first: BlotV3.Message, _ second: BlotV3.Message?) -> Bool {
        guard let second, first.role == second.role, first.authorAgentId == second.authorAgentId else { return false }
        let interval = second.metadata.createdAt.timeIntervalSince(first.metadata.createdAt)
        return interval >= 0 && interval < 2.5
    }
}
