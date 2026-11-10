#if os(macOS)
import Foundation

/// Shared implementation behind the private XPC service and the on-device verification harness.
public actor NativeExecutor: NativeExecuting {
    private let processes = NativeProcessEngine()
    private lazy var git = NativeGitService(engine: processes)
    private var reserved: Set<String> = []
    private var stopped = false
    private let storage: NativeWorkspaceStorage
    public init(workspaceHome: URL = FileManager.default.homeDirectoryForCurrentUser) {
        storage = NativeWorkspaceStorage(home: workspaceHome.standardizedFileURL.resolvingSymlinksInPath())
    }
    public func request(_ request: NativeRequest) async throws -> ChatJSON {
        guard !stopped else { throw NativeExecutionError.unavailable }
        try request.command.validate()
        let c = request.command, p = request.parameters
        switch request.operation {
        case .workspacePrepare: return try storage.prepare(p)
        case .workspaceRecord: return try storage.record(p, removing: false)
        case .workspaceRemoveRecord: return try storage.record(p, removing: true)
        case .workspaceCopyArtifact: return try storage.copyArtifact(p)
        case .workspaceEraseOwner: return try storage.erase(p)
        case .start:
            guard !reserved.contains(c.root) else { throw NativeExecutionError.busy }
            var environment = ["HOME": NSHomeDirectory(), "TMPDIR": FileManager.default.temporaryDirectory.path]
            environment.merge(c.environment) { _, new in new }
            let command = NativeCommand(id: c.id, projectID: c.projectID, root: c.root, directory: c.directory, executable: c.executable,
                arguments: c.arguments, environment: environment, timeout: c.timeout)
            return try await processes.start(command).json()
        case .status: return try await processes.status(c.id).json()
        case .stop: return try await processes.stop(c.id).json()
        default:
            guard !reserved.contains(c.root), await !processes.active(in: c.root) else { throw NativeExecutionError.busy }
            reserved.insert(c.root); defer { reserved.remove(c.root) }
            if [.workspaceList, .workspaceRead, .workspaceWrite, .workspaceMkdir].contains(request.operation) {
                let files = try NativeScopedFiles(root: URL(fileURLWithPath: c.root)); defer { files.closeRoot() }
                switch request.operation {
                case .workspaceList: return try files.list(p["path"] ?? ".")
                case .workspaceMkdir:
                    try files.mkdir(p["path"] ?? "")
                    return .object(["state": .string("succeeded"), "path": .string(p["path"] ?? "")])
                case .workspaceRead:
                    let data = try files.read(p["path"] ?? "")
                    guard String(data: data, encoding: .utf8) != nil else { throw NativeExecutionError.invalidRequest }
                    return .object(["content": .string(String(decoding: data.prefix(48_000), as: UTF8.self)), "sha256": .string(NativeScopedFiles.hash(data)), "truncated": .bool(data.count > 48_000)])
                case .workspaceWrite:
                    let expected = p["expected_hash"] ?? ""
                    guard expected == "missing" || expected.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw NativeExecutionError.invalidRequest }
                    let hash = try files.write(p["path"] ?? "", data: Data((p["content"] ?? "").utf8), expected: expected)
                    return .object(["state": .string("succeeded"), "sha256": .string(hash), "path": .string(p["path"] ?? "")])
                default: throw NativeExecutionError.invalidRequest
                }
            }
            let files = try NativeProjectFiles(root: c.root)
            switch request.operation {
            case .fileRead: return try files.read(p["path"] ?? "")
            case .fileSearch: return try files.search(p["query"] ?? "")
            case .fileWrite: return try files.write(p["path"] ?? "", content: p["content"] ?? "", expectedHash: p["expected_hash"] ?? "")
            default: return try await git.perform(request.operation, command: c, parameters: p)
            }
        }
    }
    public func stopAll() async { stopped = true; await processes.stopAll() }
}
#endif
