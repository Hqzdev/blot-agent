import Foundation

public enum WidgetDestination: Equatable, Sendable {
    case compose, agents, schedules, overview
    case conversation(UUID), agent(UUID)

    public var url: URL {
        var parts = URLComponents()
        parts.scheme = "blot-agent-ios"; parts.host = "widgets"
        switch self {
        case .compose: parts.path = "/compose"
        case .agents: parts.path = "/agents"
        case .schedules: parts.path = "/schedules"
        case .overview: parts.path = "/overview"
        case .conversation(let id): parts.path = "/chat/" + id.uuidString
        case .agent(let id): parts.path = "/agent/" + id.uuidString
        }
        return parts.url!
    }

    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "blot-agent-ios", parts.host == "widgets", parts.port == nil,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil else { return nil }
        switch parts.path {
        case "/compose": self = .compose
        case "/agents": self = .agents
        case "/schedules": self = .schedules
        case "/overview": self = .overview
        default:
            let path = parts.path.split(separator: "/", omittingEmptySubsequences: false)
            guard path.count == 3, path[0].isEmpty, let id = UUID(uuidString: String(path[2])) else { return nil }
            switch path[1] {
            case "chat": self = .conversation(id)
            case "agent": self = .agent(id)
            default: return nil
            }
        }
    }
}
