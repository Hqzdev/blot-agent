import BlotDomain
import Foundation

public enum WorkspaceMessageOrder {
    public static func ordered(_ messages: [BlotV3.Message]) -> [BlotV3.Message] {
        messages.enumerated().map { ($0.element, $0.element.position ?? $0.offset + 1) }.sorted {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.0.metadata.id.uuidString < $1.0.metadata.id.uuidString
        }.map(\.0)
    }

    public static func isAfter(_ message: BlotV3.Message, legacyPosition: Int, read: BlotV3.ConversationReadPosition?) -> Bool {
        guard let read else { return true }
        let position = message.position ?? legacyPosition
        return position > read.position || (position == read.position && message.metadata.id.uuidString > read.messageId.uuidString)
    }
}
