#if os(macOS)
import CryptoKit
import Darwin
import Foundation

/// Fixed Git operations freeze trees and compare refs; arbitrary user commands use a different execution path.
public actor NativeGitService {
    private struct CommitPreparation {
        let id: UUID; let root: String; let project: UUID; let head: String; let branch: String; let tree: String
        let sourceHead: String; let sourceBranch: String
        let message: String; let paths: [String]; let hashes: [String: String]; let indexHash: String; let indexPath: String
        let expires: Date
    }
    private struct PushPreparation {
        let id: UUID; let root: String; let project: UUID; let commit: String; let branch: String; let remote: String
        let endpoint: String; let destination: String; let expires: Date
        let checkoutHead: String; let checkoutBranch: String
    }
    private let engine: NativeProcessEngine
    private var commits: [UUID: CommitPreparation] = [:]
    private var pushes: [UUID: PushPreparation] = [:]
    public init(engine: NativeProcessEngine) { self.engine = engine }

    public func perform(_ operation: NativeRequest.Operation, command: NativeCommand, parameters p: [String: String]) async throws -> ChatJSON {
        let root = try await repository(command)
        switch operation {
        case .gitStatus:
            return .object(["branch": .string(try await branch(command)), "head": .string(try await head(command)),
                "status": .string(try await git(command, ["status", "--short", "--untracked-files=normal"]))])
        case .gitDiff: return .object(["diff": .string(try await git(command, ["diff", "--no-ext-diff", "--no-textconv", "HEAD", "--"]))])
        case .gitLog: return .object(["log": .string(try await git(command, ["log", "-20", "--format=%H %s"]))])
        case .gitBranch:
            let name = try required(p, "branch")
            try validateBranch(name)
            let base = try required(p, "base")
            let sha = try await git(command, ["rev-parse", "--verify", "--end-of-options", base + "^{commit}"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sha.count == 40 || sha.count == 64 else { throw NativeExecutionError.invalidRequest }
            _ = try await git(command, ["branch", "--no-track", "--", name, sha])
            return .object(["branch": .string(name), "head": .string(sha), "state": .string("succeeded")])
        case .gitPrepareCommit:
            let paths = try JSONDecoder().decode([String].self, from: Data(required(p, "paths").utf8))
            let message = try required(p, "message")
            guard !paths.isEmpty, paths.count <= 100, Set(paths).count == paths.count, message.utf8.count <= 2000 else { throw NativeExecutionError.invalidRequest }
            let files = try NativeProjectFiles(root: root)
            for path in paths { _ = try files.url(path) }
            let sourceHead = try await head(command), sourceBranch = try await branch(command)
            let currentBranch = p["branch"] ?? sourceBranch
            try await protect(command, branch: currentBranch)
            let currentHead = try await git(command, ["rev-parse", "--verify", "refs/heads/" + currentBranch]).trimmingCharacters(in: .whitespacesAndNewlines)
            if currentBranch != sourceBranch {
                guard try await !git(command, ["worktree", "list", "--porcelain"]).contains("branch refs/heads/" + currentBranch + "\n"),
                      try await git(command, ["diff", "--name-only", sourceHead, currentHead, "--"] + paths).isEmpty else { throw NativeExecutionError.changed }
            }
            // Never consume an existing staged hunk in one of the selected files.
            guard try await git(command, ["diff", "--cached", "--name-only", "--"] + paths).isEmpty else {
                throw NativeExecutionError.gitFailed("В выбранных файлах уже есть staged-изменения. Сначала сохраните или снимите их самостоятельно.")
            }
            let indexPath = try await git(command, ["rev-parse", "--path-format=absolute", "--git-path", "index"]).trimmingCharacters(in: .whitespacesAndNewlines)
            let indexHash = try fileHash(URL(fileURLWithPath: indexPath))
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("blot-git-index-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary); try? FileManager.default.removeItem(atPath: temporary.path + ".lock") }
            let env = ["GIT_INDEX_FILE": temporary.path]
            _ = try await git(command, ["read-tree", currentHead], environment: env)
            let hashes = try snapshot(files: files, paths: paths)
            for path in paths {
                let file = try files.url(path)
                if FileManager.default.fileExists(atPath: file.path) {
                    let sha = try await git(command, ["hash-object", "-w", "--no-filters", "--", file.path]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let mode = ((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o111 == 0 ? "100644" : "100755"
                    _ = try await git(command, ["update-index", "--add", "--cacheinfo", mode + "," + sha + "," + path], environment: env)
                } else { _ = try await git(command, ["update-index", "--force-remove", "--", path], environment: env) }
            }
            let tree = try await git(command, ["write-tree"], environment: env).trimmingCharacters(in: .whitespacesAndNewlines)
            let diff = try await git(command, ["diff", "--no-ext-diff", "--no-textconv", currentHead, tree, "--"])
            guard !diff.isEmpty, diff.utf8.count <= 40 * 1024, try snapshot(files: files, paths: paths) == hashes,
                  try await head(command) == sourceHead, try await branch(command) == sourceBranch else { throw NativeExecutionError.changed }
            let id = UUID()
            commits[id] = .init(id: id, root: root, project: command.projectID, head: currentHead, branch: currentBranch, tree: tree,
                sourceHead: sourceHead, sourceBranch: sourceBranch,
                message: message, paths: paths, hashes: hashes, indexHash: indexHash, indexPath: indexPath, expires: Date().addingTimeInterval(600))
            prune()
            return .object(["preparation_id": .string(id.uuidString), "head": .string(currentHead), "branch": .string(currentBranch),
                "checkout_head": .string(sourceHead), "checkout_branch": .string(sourceBranch), "tree": .string(tree), "message": .string(message), "diff": .string(diff)])
        case .gitCommit:
            let id = try preparationID(p)
            guard let prepared = commits[id], prepared.root == root, prepared.project == command.projectID, prepared.expires > Date() else { throw NativeExecutionError.changed }
            try await protect(command, branch: prepared.branch)
            guard try await head(command) == prepared.sourceHead, try await branch(command) == prepared.sourceBranch,
                  try await git(command, ["rev-parse", "--verify", "refs/heads/" + prepared.branch]).trimmingCharacters(in: .whitespacesAndNewlines) == prepared.head,
                  try snapshot(files: NativeProjectFiles(root: root), paths: prepared.paths) == prepared.hashes,
                  try fileHash(URL(fileURLWithPath: prepared.indexPath)) == prepared.indexHash else { throw NativeExecutionError.changed }
            if prepared.branch != prepared.sourceBranch {
                guard try await !git(command, ["worktree", "list", "--porcelain"]).contains("branch refs/heads/" + prepared.branch + "\n") else { throw NativeExecutionError.accessDenied }
                let commit = try await git(command, ["commit-tree", prepared.tree, "-p", prepared.head, "-m", prepared.message], environment: gitIdentity(command)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard try snapshot(files: NativeProjectFiles(root: root), paths: prepared.paths) == prepared.hashes,
                      try fileHash(URL(fileURLWithPath: prepared.indexPath)) == prepared.indexHash else { throw NativeExecutionError.changed }
                _ = try await git(command, ["update-ref", "refs/heads/" + prepared.branch, commit, prepared.head])
                commits[id] = nil
                return .object(["commit": .string(commit), "branch": .string(prepared.branch), "state": .string("succeeded"), "checkout_unchanged": .bool(true)])
            }
            let lock = prepared.indexPath + ".lock"
            let fd = open(lock, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw NativeExecutionError.busy }
            close(fd)
            defer { try? FileManager.default.removeItem(atPath: lock) }
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("blot-git-commit-index-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary); try? FileManager.default.removeItem(atPath: temporary.path + ".lock") }
            if FileManager.default.fileExists(atPath: prepared.indexPath) { try FileManager.default.copyItem(atPath: prepared.indexPath, toPath: temporary.path) }
            let env = ["GIT_INDEX_FILE": temporary.path]
            if !FileManager.default.fileExists(atPath: temporary.path) { _ = try await git(command, ["read-tree", prepared.head], environment: env) }
            for path in prepared.paths {
                let entry = try await git(command, ["ls-tree", "-z", prepared.tree, "--", path])
                if entry.isEmpty { _ = try await git(command, ["update-index", "--force-remove", "--", path], environment: env) }
                else {
                    guard let tab = entry.firstIndex(of: "\t") else { throw NativeExecutionError.changed }
                    let fields = entry[..<tab].split(separator: " ")
                    guard fields.count == 3 else { throw NativeExecutionError.changed }
                    _ = try await git(command, ["update-index", "--add", "--cacheinfo", String(fields[0]) + "," + String(fields[2]) + "," + path], environment: env)
                }
            }
            let identity = try await gitIdentity(command)
            let commit = try await git(command, ["commit-tree", prepared.tree, "-p", prepared.head, "-m", prepared.message], environment: identity).trimmingCharacters(in: .whitespacesAndNewlines)
            guard try fileHash(URL(fileURLWithPath: prepared.indexPath)) == prepared.indexHash,
                  try snapshot(files: NativeProjectFiles(root: root), paths: prepared.paths) == prepared.hashes else { throw NativeExecutionError.changed }
            try Data(contentsOf: temporary).write(to: URL(fileURLWithPath: lock))
            _ = try await git(command, ["update-ref", "refs/heads/" + prepared.branch, commit, prepared.head])
            guard rename(lock, prepared.indexPath) == 0 else { throw NativeExecutionError.unknown }
            commits[id] = nil
            return .object(["commit": .string(commit), "branch": .string(prepared.branch), "state": .string("succeeded")])
        case .gitPreparePush:
            let name = try required(p, "remote"), destination = try required(p, "branch")
            guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil else { throw NativeExecutionError.invalidRequest }
            try validateBranch(destination)
            let checkoutBranch = try await branch(command), checkoutHead = try await head(command)
            let currentBranch = p["source_branch"] ?? checkoutBranch
            try await protect(command, branch: currentBranch)
            let commit = try await git(command, ["rev-parse", "--verify", "refs/heads/" + currentBranch]).trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoints = try await git(command, ["remote", "get-url", "--push", "--all", name]).split(whereSeparator: \.isNewline).map(String.init)
            guard endpoints.count == 1, let endpoint = endpoints.first, !endpoint.hasPrefix("-"), !endpoint.contains("ext::"),
                  !endpoint.contains("\n"), !endpoint.contains("\r"), !endpoint.hasPrefix("git://"), !endpoint.contains("@") || !endpoint.contains("://") || endpoint.hasPrefix("ssh://") else { throw NativeExecutionError.accessDenied }
            if let url = URL(string: endpoint), ["https", "http", "ssh"].contains(url.scheme) {
                guard url.password == nil, url.query == nil, url.fragment == nil, url.scheme == "ssh" || url.user == nil else { throw NativeExecutionError.accessDenied }
            }
            let remoteDefault = try await git(command, ["ls-remote", "--symref", "--", endpoint, "HEAD"])
            guard !remoteDefault.contains("ref: refs/heads/" + destination + "\t") else { throw NativeExecutionError.accessDenied }
            let id = UUID()
            pushes[id] = .init(id: id, root: root, project: command.projectID, commit: commit, branch: currentBranch, remote: name,
                endpoint: endpoint, destination: "refs/heads/" + destination, expires: Date().addingTimeInterval(600), checkoutHead: checkoutHead, checkoutBranch: checkoutBranch)
            prune()
            return .object(["preparation_id": .string(id.uuidString), "commit": .string(commit), "remote": .string(name),
                "endpoint": .string(endpoint), "source_branch": .string(currentBranch), "destination": .string("refs/heads/" + destination)])
        case .gitPush, .gitReconcilePush:
            if operation == .gitReconcilePush, let commit = p["commit"] {
                let remote = try required(p, "remote"), endpoint = try required(p, "endpoint"), destination = try required(p, "destination")
                guard commit.range(of: #"^(?:[0-9a-f]{40}|[0-9a-f]{64})$"#, options: .regularExpression) != nil,
                      remote.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil,
                      destination.hasPrefix("refs/heads/") else { throw NativeExecutionError.invalidRequest }
                try validateBranch(String(destination.dropFirst(11)))
                guard try await git(command, ["remote", "get-url", "--push", "--all", remote]).trimmingCharacters(in: .whitespacesAndNewlines) == endpoint else { throw NativeExecutionError.changed }
                let actual = try await git(command, ["ls-remote", "--", endpoint, destination])
                return .object(["state": .string(actual.split(separator: "\t").first.map(String.init) == commit ? "succeeded" : "unknown"), "commit": .string(commit), "remote_ref": .string(actual)])
            }
            let id = try preparationID(p)
            guard let prepared = pushes[id], prepared.root == root, prepared.project == command.projectID else { throw NativeExecutionError.changed }
            let actualEndpoint = try await git(command, ["remote", "get-url", "--push", "--all", prepared.remote]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard actualEndpoint == prepared.endpoint else { throw NativeExecutionError.changed }
            if operation == .gitPush {
                guard prepared.expires > Date(), try await head(command) == prepared.checkoutHead, try await branch(command) == prepared.checkoutBranch,
                      try await git(command, ["rev-parse", "--verify", "refs/heads/" + prepared.branch]).trimmingCharacters(in: .whitespacesAndNewlines) == prepared.commit else { throw NativeExecutionError.changed }
                try await protect(command, branch: prepared.branch)
                let defaultRef = try await git(command, ["ls-remote", "--symref", "--", prepared.endpoint, "HEAD"])
                guard !defaultRef.contains("ref: " + prepared.destination + "\t") else { throw NativeExecutionError.accessDenied }
                _ = try await git(command, ["push", "--porcelain", "--", prepared.endpoint, prepared.commit + ":" + prepared.destination])
            }
            let remote = try await git(command, ["ls-remote", "--", prepared.endpoint, prepared.destination])
            let matched = remote.split(separator: "\t").first.map(String.init) == prepared.commit
            return .object(["state": .string(matched ? "succeeded" : "unknown"), "remote_ref": .string(remote), "commit": .string(prepared.commit)])
        default: throw NativeExecutionError.invalidRequest
        }
    }
    private func repository(_ c: NativeCommand) async throws -> String {
        let actual = try await git(c, ["rev-parse", "--show-toplevel"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: c.root).resolvingSymlinksInPath().standardizedFileURL.path
        guard URL(fileURLWithPath: actual).resolvingSymlinksInPath().path == root else { throw NativeExecutionError.accessDenied }; return root
    }
    private func head(_ c: NativeCommand) async throws -> String { try await git(c, ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func branch(_ c: NativeCommand) async throws -> String { try await git(c, ["symbolic-ref", "--quiet", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func validateBranch(_ name: String) throws {
        guard name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$"#, options: .regularExpression) != nil,
              !name.contains(".."), !name.contains("//"), !name.hasSuffix("/"), !name.hasSuffix(".lock"),
              !["main", "master"].contains(name), !name.hasSuffix("/main") else { throw NativeExecutionError.accessDenied }
    }
    private func protect(_ c: NativeCommand, branch: String) async throws {
        try validateBranch(branch)
        if let value = try? await git(c, ["symbolic-ref", "refs/remotes/origin/HEAD"]), value.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/remotes/origin/" + branch { throw NativeExecutionError.accessDenied }
    }
    private func gitIdentity(_ c: NativeCommand) async throws -> [String: String] {
        var result: [String: String] = [:]
        for (key, names) in [("user.name", ["GIT_AUTHOR_NAME", "GIT_COMMITTER_NAME"]), ("user.email", ["GIT_AUTHOR_EMAIL", "GIT_COMMITTER_EMAIL"])] {
            let value = try await git(c, ["config", "--get", key], environment: ["GIT_CONFIG_GLOBAL": NSHomeDirectory() + "/.gitconfig"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.utf8.count <= 1000, !value.contains("\n") else { throw NativeExecutionError.invalidRequest }
            for name in names { result[name] = value }
        }
        return result
    }
    private func snapshot(files: NativeProjectFiles, paths: [String]) throws -> [String: String] {
        var values: [String: String] = [:]
        for path in paths {
            let url = try files.url(path)
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular, (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 32 * 1024 * 1024 else { throw NativeExecutionError.invalidRequest }
            }
            let mode = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber
            values[path] = try fileHash(url) + ":" + String(mode?.intValue ?? 0)
        }
        return values
    }
    private func fileHash(_ url: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: url.path) else { return "missing" }
        return NativeProjectFiles.hash(try Data(contentsOf: url))
    }
    private func required(_ p: [String: String], _ key: String) throws -> String {
        guard let value = p[key], !value.isEmpty, value.utf8.count <= 32 * 1024, !value.contains("\0") else { throw NativeExecutionError.invalidRequest }; return value
    }
    private func preparationID(_ p: [String: String]) throws -> UUID { guard let id = UUID(uuidString: try required(p, "preparation_id")) else { throw NativeExecutionError.invalidRequest }; return id }
    private func prune() {
        commits = commits.filter { $0.value.expires > Date() }; pushes = pushes.filter { $0.value.expires > Date() }
        if commits.count > 100 { commits.removeAll() }; if pushes.count > 100 { pushes.removeAll() }
    }
    private func git(_ c: NativeCommand, _ args: [String], environment: [String: String] = [:]) async throws -> String {
        var env = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "TMPDIR": FileManager.default.temporaryDirectory.path,
            "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"]
        // Only Git receives explicitly configured authentication settings.
        for (key, value) in c.environment where ["SSH_AUTH_SOCK", "GIT_SSH_COMMAND", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"].contains(key) { env[key] = value }
        env.merge(environment) { _, new in new }
        var prefix = ["--no-pager", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "-c", "submodule.recurse=false", "-c", "protocol.ext.allow=never", "-c", "credential.helper=", "-c", "diff.external=", "-c", "core.pager=cat", "-c", "commit.gpgsign=false", "-c", "http.followRedirects=false", "-c", "core.sshCommand=/usr/bin/ssh"]
        // Disable repository-provided clean/smudge programs, including when updating a temporary index.
        if !args.starts(with: ["config"]) {
            let names = try? await git(c, ["config", "--null", "--name-only", "--get-regexp", "^filter\\..*\\.(clean|smudge|process|required)$"], environment: environment)
            for name in (names ?? "").split(separator: "\0") { prefix += ["-c", String(name) + "=" + (name.hasSuffix(".required") ? "false" : "")] }
        }
        let command = NativeCommand(projectID: c.projectID, root: c.root, executable: "/usr/bin/git", arguments: prefix + ["-C", c.root] + args, environment: env)
        _ = try await engine.start(command)
        while true {
            try _Concurrency.Task.checkCancellation()
            let state = try await engine.status(command.id)
            if state.finishedAt != nil {
                guard state.state == .succeeded, !state.truncated else { throw NativeExecutionError.gitFailed(String(state.stderr.prefix(2000))) }
                return state.stdout
            }
            try await _Concurrency.Task.sleep(for: .milliseconds(10))
        }
    }
}
#endif
