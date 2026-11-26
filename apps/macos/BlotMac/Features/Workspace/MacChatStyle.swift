import BlotDesign
import BlotDomain
import Foundation
import SwiftUI

enum MacChatStyle {
    static var canvas: Color { WorkspaceStyle.canvas }
    static var sidebar: Color { BlotColor.dynamic(.init(light: 0xF6F6F6FF, dark: 0x111111FF)) }
    static var incoming: Color { BlotColor.dynamic(.init(light: 0xEEEEEEFF, dark: 0x242424FF)) }
    static var selection: Color { BlotColor.dynamic(.init(light: 0xE6E6E6FF, dark: 0x303030FF)) }
    static var edge: Color { BlotColor.dynamic(.init(light: 0xE7E7E7FF, dark: 0x252525FF)) }
}

/// Source-message linkage is not an explicit user quotation.
nonisolated enum MacChatMessageContext {
    static func quoteID(_ message: BlotV3.Message) -> UUID? {
        message.role == .user ? message.replyToMessageId : nil
    }
    static func startsDate(_ message: BlotV3.Message, after previous: BlotV3.Message?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(message.metadata.createdAt, inSameDayAs: previous.metadata.createdAt)
            || message.metadata.createdAt.timeIntervalSince(previous.metadata.createdAt) >= 3600
    }
}

struct MacChatIconButton: View {
    @Environment(\.macSidebarTracksHover) private var tracksHover
    static let size: CGFloat = 38
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { BlotIcon(symbol: symbol, size: 18).frame(width: Self.size, height: Self.size).blotChromeSurface(cornerRadius: 22).blotHitArea() }
            .buttonStyle(BlotHitTargetButtonStyle(hoverIn: Circle(), hoverColor: tracksHover ? .clear : BlotColor.hover))
            .macSidebarHoverTarget().foregroundStyle(WorkspaceStyle.ink).macHoverTip(title).accessibilityLabel(title)
    }
}

nonisolated enum MacChatAgentActivity: String, CaseIterable {
    case idle, working, waiting, blocked, thinking, done
    static func resolve(task: BlotV3.TaskState?, needsInput: Bool, generating: Bool) -> Self {
        if needsInput { return .waiting }
        if generating { return .thinking }
        switch task {
        case .planning: return .thinking
        case .running, .queued: return .working
        case .waiting_user: return .waiting
        case .waiting_approval, .paused, .failed, .interrupted: return .blocked
        case .completed: return .done
        default: return .idle
        }
    }
}

@MainActor
extension WorkspaceStore {
    var macChatActivity: MacChatAgentActivity {
        let pending = (snapshot.cards ?? []).contains { card in
            card.state == "pending" && (card.expiresAt.map { $0 > Date() } ?? true)
                && snapshot.messages.contains { $0.metadata.id == card.messageId && $0.conversationId == selectedConversationID }
                && !["task", "plugin", "subscription", "page"].contains(card.kind)
        }
        return .resolve(task: currentTask?.state, needsInput: pending, generating: isReplying)
    }
}

struct MacChatAgentAvatar: View {
    let agent: BlotV3.AgentProfile
    let activity: MacChatAgentActivity
    var size: CGFloat = 22
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blotReduceMotion) private var reduceMotion
    @State private var started = Date()
    private var moving: Bool { phase == .active && !reduceMotion && !systemReduceMotion && [.working, .waiting, .thinking].contains(activity) }
    private var motion: BlotState {
        switch activity {
        case .idle: .idle
        case .working: .working
        case .waiting: .waiting
        case .blocked: .blocked
        case .thinking: .thinking
        case .done: .happy
        }
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !moving)) { context in
            WorkspaceAvatar(shape: .init(rawValue: agent.avatarShape) ?? .round,
                color: WorkspaceAvatarView.color(agent.avatarColor), size: size,
                pose: BlotMotion.pose(state: motion, elapsed: moving ? context.date.timeIntervalSince(started) : BlotMotion.restingTime))
        }.onChange(of: activity) { _, _ in started = Date() }.accessibilityHidden(true)
    }
}
