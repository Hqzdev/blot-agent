import Foundation

public enum WorkspaceNativeCatalog {
    static let string: ChatJSON = .object(["type": .string("string")])
    static let strings: ChatJSON = .object(["type": .string("array"), "items": string])
    public static let definitions: [ChatToolDefinition] = [
        tool("project_read_file", "Read a UTF-8 file in the selected project; returns its hash and truncation status.", ["path": string], ["path"]),
        tool("project_search", "Search literal text in the selected project.", ["query": string], ["query"]),
        tool("project_write_file", "Write a UTF-8 project file only if expected_hash matches. Use missing for a new file. Confirmation or a project rule is required.", ["path": string, "content": string, "expected_hash": string], ["path", "content", "expected_hash"]),
        tool("process_run", "Run a native command on the selected Mac project. executable must be absolute; shell scripts require an explicit /bin/sh or /bin/zsh. A running result is NOT completion: poll process_status until terminal and inspect exitCode. No interactive stdin.", ["executable": string, "arguments": strings, "directory": string, "variables": strings, "timeout_seconds": .object(["type": .string("integer")])], ["executable", "arguments"]),
        tool("process_status", "Get this source/task's process output and actual result. Continue polling while running.", ["process_id": string], ["process_id"]),
        tool("process_stop", "Stop this source/task's process and its process group.", ["process_id": string], ["process_id"]),
        tool("git_status", "Read branch, HEAD and working tree status of the selected project.", [:], []),
        tool("git_diff", "Read the selected project's actual diff against HEAD.", [:], []),
        tool("git_log", "Read the selected project's latest commits.", [:], []),
        tool("git_branch", "Create a task branch at an explicit base ref without switching the user's checkout. Follow the repository's branch rules.", ["branch": string, "base": string], ["branch", "base"]),
        tool("git_prepare_commit", "Freeze a proposed commit of selected files. Optional branch targets an existing, unchecked-out task branch without switching the user's checkout or index. Create it with git_branch first. Returns exact diff, tree, HEAD and preparation ID; does not commit. Selected staged files and incompatible target-base files are rejected.", ["paths": strings, "message": string, "branch": string], ["paths", "message"]),
        tool("git_commit", "Commit a frozen preparation after approval; preserves unrelated staged files. A changed file, HEAD or index invalidates it.", ["preparation_id": string], ["preparation_id"]),
        tool("git_prepare_push", "Prepare an exact push to a named remote and destination task branch. Optional source_branch selects a task branch without switching the checkout. Does not push.", ["remote": string, "branch": string, "source_branch": string], ["remote", "branch"]),
        tool("git_push", "Push an exact preparation after separate user confirmation. Never force-push.", ["preparation_id": string], ["preparation_id"])
    ]
    public static var toolIDs: [String] { definitions.map(\.name) }
    public static let trustedClasses = ["file.write", "process.run", "git.branch", "git.commit"]
    static func operation(_ name: String) throws -> NativeRequest.Operation {
        let mapping: [String: NativeRequest.Operation] = ["project_read_file": .fileRead, "project_search": .fileSearch, "project_write_file": .fileWrite,
            "process_run": .start, "process_status": .status, "process_stop": .stop, "git_status": .gitStatus, "git_diff": .gitDiff,
            "git_log": .gitLog, "git_branch": .gitBranch, "git_prepare_commit": .gitPrepareCommit, "git_commit": .gitCommit,
            "git_prepare_push": .gitPreparePush, "git_push": .gitPush]
        guard let value = mapping[name] else { throw WorkspaceToolError.unknownTool }; return value
    }
    static func writes(_ name: String) -> Bool { ["project_write_file", "process_run", "git_branch", "git_commit", "git_push"].contains(name) }
    static func operationClass(_ name: String) -> String {
        ["project_write_file": "file.write", "process_run": "process.run", "git_branch": "git.branch", "git_commit": "git.commit", "git_push": "git.push"][name] ?? "read"
    }
    private static func tool(_ name: String, _ description: String, _ properties: [String: ChatJSON], _ required: [String]) -> ChatToolDefinition {
        .init(name: name, description: description, parameters: .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(ChatJSON.string)), "additionalProperties": .bool(false)]))
    }
}

public struct WorkspaceNativeProject: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let root: String
    public let bookmark: Data?
    public let revision: UUID
    public var agents: Set<UUID>
    public var trustedClasses: Set<String>
    public var variables: [String: String]
    public var gitToken: String
    public var gitCredentialURL: String
    public var sshAuthSocket: String
}

struct WorkspaceNativeState: Codable {
    var projects: [WorkspaceNativeProject] = []
    var conversations: [String: UUID] = [:]
}

public struct NativeUnavailableExecutor: NativeExecuting {
    public init() {}
    public func request(_ request: NativeRequest) async throws -> ChatJSON { throw NativeExecutionError.unavailable }
    public func stopAll() async {}
}
