import BlotDomain
import Foundation

/// File and branch details come from successful native tool results, never the final assistant text.
struct WorkspaceTaskResultCard {
    func content(task: BlotV3.Task, projection: WorkspaceProjection, failed: Bool) -> WorkspaceCardContent {
        let actions = Dictionary(uniqueKeysWithValues: projection.actions.filter { $0.execution.taskId == task.metadata.id }.map { ($0.metadata.id, $0) })
        var branch: String?
        var pullRequestURL: URL?
        var files: Set<String> = []
        var statistics: (additions: Int, deletions: Int)?
        for invocation in projection.invocations.sorted(by: { $0.metadata.createdAt < $1.metadata.createdAt }) where invocation.state == .succeeded {
            guard let action = actions[invocation.preparedActionId], let raw = invocation.result,
                  let result = try? WorkspaceCoding.decode(ChatJSON.self, from: Data(raw.utf8)),
                  result.mcpFields["state"] != .string("failed"), result.mcpFields["state"] != .string("unknown") else { continue }
            if ["git_status", "git_branch", "git_commit"].contains(action.toolId), case .string(let value) = result.mcpFields["branch"] { branch = value }
            if action.toolId == "project_write_file", result.mcpFields["state"] == .string("succeeded"), case .string(let path) = result.mcpFields["path"] { files.insert(path); statistics = nil }
            if ["git_diff", "git_prepare_commit"].contains(action.toolId), case .string(let diff) = result.mcpFields["diff"] { statistics = Self.statistics(diff) }
            if action.toolId == "process_run", result.mcpFields["exitCode"] == .number(0),
               let arguments = try? WorkspaceCoding.decode(ChatJSON.self, from: Data(action.parameters.utf8)),
               case .string(let executable) = arguments.mcpFields["executable"], URL(fileURLWithPath: executable).lastPathComponent == "gh",
               case .array(let values) = arguments.mcpFields["arguments"], values.starts(with: [.string("pr"), .string("view")]),
               values.contains(.string("--json")), values.contains(.string("url")),
               case .string(let output) = result.mcpFields["stdout"],
               let object = try? WorkspaceCoding.decode(ChatJSON.self, from: Data(output.utf8)), case .string(let rawURL) = object.mcpFields["url"],
               let url = URL(string: rawURL), url.scheme == "https", url.host == "github.com" {
                let parts = url.path.split(separator: "/")
                if parts.count == 4, parts[2] == "pull", Int(parts[3]).map({ $0 > 0 }) == true { pullRequestURL = url }
            }
        }
        return .task(.init(title: task.goal, branch: branch, files: files.sorted(), pullRequestURL: pullRequestURL, state: failed ? "failed" : "completed", additions: statistics?.additions, deletions: statistics?.deletions))
    }

    static func statistics(_ diff: String) -> (additions: Int, deletions: Int)? {
        var inHunk = false, recognized = false, additions = 0, deletions = 0
        for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("diff --git ") { inHunk = false }
            else if line.hasPrefix("@@ ") { inHunk = true; recognized = true }
            else if inHunk && line.hasPrefix("+") { additions += 1 }
            else if inHunk && line.hasPrefix("-") { deletions += 1 }
        }
        return recognized ? (additions, deletions) : nil
    }
}
