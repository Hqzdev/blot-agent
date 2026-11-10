import Foundation

public enum NativeExecutionError: Error, Equatable, Sendable, LocalizedError {
    case unavailable, programUnavailable, invalidRequest, accessDenied, busy, changed, unknown, gitFailed(String)
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Нативный исполнитель недоступен. Проверьте подпись приложения и доступ к проекту."
        case .programUnavailable: "Программа не найдена или недоступна для запуска. Проверьте путь к установленному инструменту и его права."
        case .invalidRequest: "Проверьте программу, аргументы, папку и ограничения команды."
        case .accessDenied: "Доступ к проекту или действию не выдан."
        case .busy: "Проект уже занят командой или достигнут лимит процессов."
        case .changed: "Проект, файлы или Git изменились после подготовки. Подготовьте действие заново."
        case .unknown: "Результат действия неизвестен. Сначала сверьте состояние проекта."
        case .gitFailed(let message): "Git: " + message
        }
    }
    public var wireCode: String {
        switch self {
        case .unavailable: "unavailable"
        case .programUnavailable: "programUnavailable"
        case .invalidRequest: "invalidRequest"
        case .accessDenied: "accessDenied"
        case .busy: "busy"
        case .changed: "changed"
        case .unknown: "unknown"
        case .gitFailed: "gitFailed"
        }
    }
    static func remote(_ text: String) -> NativeExecutionError {
        let fields = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        switch fields.first.map(String.init) {
        case "changed": return .changed
        case "programUnavailable": return .programUnavailable
        case "accessDenied": return .accessDenied
        case "busy": return .busy
        case "invalidRequest": return .invalidRequest
        case "unknown": return .unknown
        case "gitFailed": return .gitFailed(String(fields.last?.prefix(1800) ?? "Git request failed"))
        default: return .unavailable
        }
    }
}

public struct NativeCommand: Codable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let root: String
    public let directory: String
    public let executable: String
    public let arguments: [String]
    public let environment: [String: String]
    public let timeout: Int
    public init(id: UUID = UUID(), projectID: UUID, root: String, directory: String = ".", executable: String,
                arguments: [String] = [], environment: [String: String] = [:], timeout: Int = 120) {
        self.id = id; self.projectID = projectID; self.root = root; self.directory = directory; self.executable = executable
        self.arguments = arguments; self.environment = environment; self.timeout = timeout
    }
    public func validate() throws {
        guard root.hasPrefix("/"), !root.contains("\0"), !directory.hasPrefix("/"), !directory.contains("\0"),
              executable.hasPrefix("/"), !executable.contains("\0"), executable.utf8.count <= 4096,
              arguments.count <= 100, arguments.allSatisfy({ $0.utf8.count <= 8192 && !$0.contains("\0") }),
              (1...1800).contains(timeout), environment.count <= 50,
              environment.allSatisfy({ key, value in key.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil && value.utf8.count <= 8192 && !value.contains("\0") }),
              try JSONEncoder().encode(self).count <= 64 * 1024 else { throw NativeExecutionError.invalidRequest }
    }
}

public struct NativeProcessSnapshot: Codable, Equatable, Sendable, Identifiable {
    public enum State: String, Codable, Sendable { case running, succeeded, failed, canceled, timedOut }
    public let id: UUID
    public let projectID: UUID
    public let executable: String
    public let arguments: [String]
    public let state: State
    public let stdout: String
    public let stderr: String
    public let truncated: Bool
    public let exitCode: Int32?
    public let startedAt: Date
    public let finishedAt: Date?
}

public struct NativeRequest: Codable, Sendable {
    public enum Operation: String, Codable, Sendable {
        case start, status, stop, fileRead, fileSearch, fileWrite, gitStatus, gitDiff, gitLog, gitPrepareCommit, gitCommit, gitPreparePush, gitPush, gitReconcilePush, gitBranch
        case workspacePrepare, workspaceRecord, workspaceRemoveRecord, workspaceEraseOwner, workspaceList, workspaceRead, workspaceWrite, workspaceMkdir, workspaceCopyArtifact
    }
    public let operation: Operation
    public let command: NativeCommand
    public let parameters: [String: String]
    public init(_ operation: Operation, command: NativeCommand, parameters: [String: String] = [:]) {
        self.operation = operation; self.command = command; self.parameters = parameters
    }
}

public protocol NativeExecuting: Sendable {
    func request(_ request: NativeRequest) async throws -> ChatJSON
    func stopAll() async
}

extension NativeProcessSnapshot {
    func json() throws -> ChatJSON { try JSONDecoder().decode(ChatJSON.self, from: WorkspaceCoding.encode(self)) }
}
