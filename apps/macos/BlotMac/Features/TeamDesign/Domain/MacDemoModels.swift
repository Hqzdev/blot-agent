import Foundation

struct MacDemoAgent: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var role: String
    var instructions: String
    var color: String
    var avatarShape: String
    var preview: String
    var unread = false
    var notifications = true
    var avatarData: Data?
}

struct MacDemoGroup: Identifiable, Codable {
    let id: String
    var name: String
    var agentIDs: [String]
}

struct MacDemoRoutine: Identifiable, Codable {
    let id: String
    var title: String
    var agentID: String
    var instructions: String
    var enabled = true
    var frequency = "По будням"
    var time = "09:00"
    var weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт"]
    var quiet = true
    var requiresApproval = true
    var lastRun: Date?
    var schedule: String {
        let days =
            frequency == "По будням" && Set(weekdays) != Set(["Пн", "Вт", "Ср", "Чт", "Пт"])
            ? weekdays.joined(separator: ", ") : frequency
        return days + " · " + time
    }
}

struct MacDemoMessage: Identifiable, Codable {
    enum Kind: String, Codable {
        case text, onboarding, briefing, connection, email, routine, products, invoices, transactions
        case document, suggestions, event, agentCreated
    }
    let id: String
    var authorID: String?
    var isUser = false
    var text: String
    var kind: Kind = .text
    var referenceID: String?
    var attachments: [String] = []
    var createdAt = Date()
    var replyToID: String?
    var reactions: [MacDemoReaction]?

    init(
        authorID: String? = nil, isUser: Bool = false, text: String, kind: Kind = .text,
        referenceID: String? = nil, attachments: [String] = [], replyToID: String? = nil
    ) {
        id = UUID().uuidString
        self.authorID = authorID
        self.isUser = isUser
        self.text = text
        self.kind = kind
        self.referenceID = referenceID
        self.attachments = attachments
        self.replyToID = replyToID
    }
}

struct MacDemoMemory: Identifiable, Codable {
    let id: String
    var text: String
    var agentID: String?
}

struct MacDemoSkill: Identifiable, Codable {
    let id: String
    var title: String
    var instructions: String
    var agentID: String
}

struct MacDemoConnection: Identifiable, Codable {
    let id: String
    var pluginID: String
    var label: String
    var account: String
    var allowRead = true
    var allowDraft = true
    var allowSend = false
    var endpoint = ""
    var authentication = "OAuth"
}

struct MacDemoEmail: Identifiable, Codable {
    let id: String
    var sender: String
    var address: String
    var subject: String
    var incoming: String
    var reply: String
    var agentID: String
    var sent = false
    var accountLabel = "Рабочая почта"
}

struct MacDemoDocument: Identifiable, Codable {
    let id: String
    var title: String
    var body: String
    var agentID: String
    var published = false
}

struct MacDemoTransaction: Identifiable, Codable {
    let id: String
    var vendor: String
    var category: String
    var amount: Double
    var approved = false
}

struct MacDemoProduct: Identifiable, Codable {
    let id: String
    let name: String
    let price: Double
    let rating: String
    let detail: String
    var selected = false
    var referenceURL: String {
        "https://www.amazon.com/s?k=" + (name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)
    }
}

struct MacDemoSettings: Codable {
    var profileName = "Ярослав"
    var language = "Русский"
    var notifications = true
    var launchAtLogin = false
    var automaticUpdates = true
    var updateTrack = "Стабильный"
    var usageLimit = "Отключено"
    var plan = "Pro"
    var usedActions = 34
    var weeklyLimit = 100
    var lastUpdateCheck: Date?
    var usageResetAt =
        Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.end ?? Date().addingTimeInterval(604800)

    init() {}
    private enum CodingKeys: String, CodingKey {
        case profileName, language, notifications, launchAtLogin, automaticUpdates, updateTrack, usageLimit
        case plan, usedActions, weeklyLimit, lastUpdateCheck, usageResetAt
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profileName = try values.decodeIfPresent(String.self, forKey: .profileName) ?? profileName
        language = try values.decodeIfPresent(String.self, forKey: .language) ?? language
        notifications = try values.decodeIfPresent(Bool.self, forKey: .notifications) ?? notifications
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? launchAtLogin
        automaticUpdates = try values.decodeIfPresent(Bool.self, forKey: .automaticUpdates) ?? automaticUpdates
        updateTrack = try values.decodeIfPresent(String.self, forKey: .updateTrack) ?? updateTrack
        usageLimit = try values.decodeIfPresent(String.self, forKey: .usageLimit) ?? usageLimit
        plan = try values.decodeIfPresent(String.self, forKey: .plan) ?? plan
        usedActions = try values.decodeIfPresent(Int.self, forKey: .usedActions) ?? usedActions
        weeklyLimit = max(1, try values.decodeIfPresent(Int.self, forKey: .weeklyLimit) ?? weeklyLimit)
        lastUpdateCheck = try values.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        usageResetAt = try values.decodeIfPresent(Date.self, forKey: .usageResetAt) ?? usageResetAt
    }
}

struct MacDemoState: Codable {
    var version = 1
    var agents: [MacDemoAgent]
    var groups: [MacDemoGroup]
    var routines: [MacDemoRoutine]
    var threads: [String: [MacDemoMessage]]
    var memories: [MacDemoMemory]
    var skills: [MacDemoSkill]
    var connections: [MacDemoConnection]
    var emails: [MacDemoEmail]
    var documents: [MacDemoDocument]
    var transactions: [MacDemoTransaction]
    var products: [MacDemoProduct]
    var cart: [String]? = []
    var events = ["14:00 · Встреча по проекту", "16:30 · Обсуждение макетов"]
    var settings = MacDemoSettings()
}
