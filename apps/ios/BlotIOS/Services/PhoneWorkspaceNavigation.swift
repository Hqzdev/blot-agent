import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class PhoneWorkspaceNavigation {
    struct Context {
        var path: [WorkspaceRoute]
        var conversationID: UUID?
        var agentID: UUID?
        var recordID: UUID?
    }

    var filesQuery = ""
    private var contexts: [WorkspaceRoute: Context] = [:]
    private var positions: [WorkspaceRoute: ScrollPosition] = [:]
    private var offsets: [WorkspaceRoute: CGFloat] = [:]

    func remember(_ context: Context, for tab: WorkspaceRoute) { contexts[tab] = context }
    func context(for tab: WorkspaceRoute) -> Context? { contexts[tab] }

    func position(for route: WorkspaceRoute) -> Binding<ScrollPosition> {
        Binding(get: { self.positions[route] ?? ScrollPosition(edge: .top) },
                set: { self.positions[route] = $0 })
    }

    func forgetConversation(_ id: UUID) {
        for (tab, context) in contexts where context.conversationID == id {
            contexts[tab] = Context(path: [], conversationID: nil, agentID: nil, recordID: nil)
        }
    }

    func recordOffset(_ offset: CGFloat, for route: WorkspaceRoute) { offsets[route] = offset }

    func restorePosition(for route: WorkspaceRoute) {
        guard let offset = offsets[route] else { return }
        var position = ScrollPosition(edge: .top)
        position.scrollTo(y: offset)
        positions[route] = position
    }

    func reset() { contexts = [:]; positions = [:]; offsets = [:]; filesQuery = "" }
}
