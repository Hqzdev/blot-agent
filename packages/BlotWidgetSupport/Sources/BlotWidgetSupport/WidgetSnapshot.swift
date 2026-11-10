import Foundation

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let ownerID: UUID?
    public var updatedAt: Date
    public let language: String
    public let agents: [WidgetAgent]
    public let conversations: [WidgetConversation]
    public let decisions: [WidgetDecision]
    public let schedules: [WidgetSchedule]
    public let runningCount: Int
    public let completedCount: Int

    public init(ownerID: UUID? = nil, updatedAt: Date = .now, language: String = "ru",
                agents: [WidgetAgent] = [], conversations: [WidgetConversation] = [],
                decisions: [WidgetDecision] = [], schedules: [WidgetSchedule] = [],
                runningCount: Int = 0, completedCount: Int = 0) {
        version = 1
        self.ownerID = ownerID; self.updatedAt = updatedAt; self.language = language
        self.agents = agents; self.conversations = conversations; self.decisions = decisions
        self.schedules = schedules; self.runningCount = runningCount; self.completedCount = completedCount
    }

    public var isSignedIn: Bool { ownerID != nil }
    public func text(_ russian: String, _ english: String) -> String { language == "ru" ? russian : english }
}

public enum WidgetWorkState: String, Codable, Sendable {
    case idle, running, waiting, completed, failed, paused, offline
}

public struct WidgetAgent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let shape: String
    public let color: String
    public let state: WidgetWorkState
    public init(id: UUID, name: String, shape: String, color: String, state: WidgetWorkState) {
        self.id = id; self.name = name; self.shape = shape; self.color = color; self.state = state
    }
}

public struct WidgetConversation: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let agentID: UUID?
    public let state: WidgetWorkState
}

public struct WidgetDecision: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let title: String
    public let expiresAt: Date?
}

public struct WidgetSchedule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let agentID: UUID?
    public let nextRun: Date
    public init(id: UUID, title: String, agentID: UUID?, nextRun: Date) {
        self.id = id; self.title = title; self.agentID = agentID; self.nextRun = nextRun
    }
}
