#if os(macOS)
import Foundation
import Testing
@testable import BlotWorkspace

private func nativeWait(_ engine: NativeProcessEngine, _ command: NativeCommand) async throws -> NativeProcessSnapshot {
    _ = try await engine.start(command)
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while ContinuousClock.now < deadline {
        let value = try await engine.status(command.id)
        if value.finishedAt != nil { return value }
        try await _Concurrency.Task.sleep(for: .milliseconds(10))
    }
    _ = try? await engine.stop(command.id); throw NativeExecutionError.unavailable
}

@Test func nativeProcessesCaptureBothStreamsBoundOutputAndTerminateGroups() async throws {
    let engine = NativeProcessEngine(), project = UUID()
    let command = NativeCommand(projectID: project, root: "/private/tmp", executable: "/bin/sh", arguments: ["-c", "printf hello; printf problem >&2"])
    let result = try await nativeWait(engine, command)
    #expect(result.stdout == "hello" && result.stderr == "problem" && result.exitCode == 0)
    let huge = NativeCommand(projectID: project, root: "/private/tmp", executable: "/usr/bin/python3", arguments: ["-c", "print('x'*1200000)"])
    let bounded = try await nativeWait(engine, huge)
    #expect(bounded.truncated && bounded.stdout.utf8.count <= 1_048_576)
    let waiting = NativeCommand(projectID: project, root: "/private/tmp", executable: "/bin/sh", arguments: ["-c", "sleep 30 & wait"], timeout: 1)
    let timed = try await nativeWait(engine, waiting)
    #expect(timed.state == .timedOut && timed.finishedAt != nil)
    let cancel = NativeCommand(projectID: project, root: "/private/tmp", executable: "/bin/sleep", arguments: ["30"])
    _ = try await engine.start(cancel)
    await #expect(throws: NativeExecutionError.busy) { _ = try await engine.start(.init(projectID: project, root: "/private/tmp", executable: "/bin/echo")) }
    _ = try await engine.stop(cancel.id)
    await engine.stopAll()
    #expect(try await engine.status(cancel.id).state == .canceled)
}

@Test func nativeFilesRejectEscapesSymlinksAndStaleWrites() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { cleanupWorkspaceTestStorage(folder) }
    let file = folder.appendingPathComponent("file.txt")
    try Data("before".utf8).write(to: file)
    let files = try NativeProjectFiles(root: folder.path)
    let hash = try #require(files.read("file.txt").mcpFields["sha256"]?.mcpString)
    _ = try files.write("file.txt", content: "after", expectedHash: hash)
    #expect(throws: NativeExecutionError.changed) { _ = try files.write("file.txt", content: "lost", expectedHash: hash) }
    #expect(throws: NativeExecutionError.accessDenied) { _ = try files.read("../outside") }
    try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
    #expect(throws: NativeExecutionError.accessDenied) { _ = try files.read("link") }
    #expect(throws: NativeExecutionError.accessDenied) { _ = try files.read(".git/config") }
}

private struct NativeGitFixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let engine = NativeProcessEngine()
    let project = UUID()
    var command: NativeCommand { .init(projectID: project, root: folder.path, executable: "/usr/bin/git") }
    init() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try await run(["init", "-b", "mac/test"])
        _ = try await run(["config", "user.name", "Native test"]); _ = try await run(["config", "user.email", "native@example.test"])
        try Data("first\n".utf8).write(to: folder.appendingPathComponent("a.txt")); try Data("user\n".utf8).write(to: folder.appendingPathComponent("b.txt"))
        _ = try await run(["add", "."]); _ = try await run(["commit", "-m", "Initial"])
    }
    func run(_ args: [String]) async throws -> String {
        let result = try await nativeWait(engine, .init(projectID: project, root: folder.path, executable: "/usr/bin/git", arguments: args,
            environment: ["PATH": "/usr/bin:/bin", "HOME": folder.path, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]))
        guard result.exitCode == 0 else { throw NativeExecutionError.gitFailed(result.stderr) }; return result.stdout
    }
}

@Test func nativeGitCommitFreezesContentAndPreservesUnrelatedStagedChanges() async throws {
    let f = try await NativeGitFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    try Data("task\n".utf8).write(to: f.folder.appendingPathComponent("a.txt"))
    try Data("user staged\n".utf8).write(to: f.folder.appendingPathComponent("b.txt")); _ = try await f.run(["add", "b.txt"])
    let service = NativeGitService(engine: f.engine)
    let preparation = try await service.perform(.gitPrepareCommit, command: f.command, parameters: ["paths": "[\"a.txt\"]", "message": "Task result"])
    let id = try #require(preparation.mcpFields["preparation_id"]?.mcpString)
    let result = try await service.perform(.gitCommit, command: f.command, parameters: ["preparation_id": id])
    #expect(result.mcpFields["state"] == .string("succeeded"))
    #expect(try await f.run(["diff", "--cached", "--name-only"]).trimmingCharacters(in: .whitespacesAndNewlines) == "b.txt")
    #expect(try await f.run(["show", "HEAD:a.txt"]) == "task\n")
    #expect(try await f.run(["show", "HEAD:b.txt"]) == "user\n")
    #expect(try await f.run(["diff", "--", "a.txt"]).isEmpty)
}

@Test func nativeGitRejectsChangedPreparationAndProtectedBranches() async throws {
    let f = try await NativeGitFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    try Data("task".utf8).write(to: f.folder.appendingPathComponent("a.txt"))
    let service = NativeGitService(engine: f.engine)
    let p = try await service.perform(.gitPrepareCommit, command: f.command, parameters: ["paths": "[\"a.txt\"]", "message": "Task"])
    try Data("user changed".utf8).write(to: f.folder.appendingPathComponent("a.txt"))
    await #expect(throws: NativeExecutionError.changed) { _ = try await service.perform(.gitCommit, command: f.command, parameters: ["preparation_id": p.mcpFields["preparation_id"]!.mcpString!]) }
    _ = try await f.run(["branch", "-m", "main"])
    await #expect(throws: NativeExecutionError.accessDenied) { _ = try await service.perform(.gitPrepareCommit, command: f.command, parameters: ["paths": "[\"a.txt\"]", "message": "No"] ) }
}

@Test func nativeGitPushUsesExactPreparedCommitAndReconcilesLocalRemote() async throws {
    let f = try await NativeGitFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    let remote = f.folder.appendingPathComponent("remote.git")
    _ = try await f.run(["init", "--bare", remote.path]); _ = try await f.run(["remote", "add", "origin", remote.path])
    let service = NativeGitService(engine: f.engine)
    let p = try await service.perform(.gitPreparePush, command: f.command, parameters: ["remote": "origin", "branch": "mac/result"])
    let id = try #require(p.mcpFields["preparation_id"]?.mcpString)
    let result = try await service.perform(.gitPush, command: f.command, parameters: ["preparation_id": id])
    #expect(result.mcpFields["state"] == .string("succeeded"))
    let reconciled = try await service.perform(.gitReconcilePush, command: f.command, parameters: ["preparation_id": id])
    #expect(reconciled.mcpFields["state"] == .string("succeeded"))
    let reopened = NativeGitService(engine: f.engine)
    let restored = try await reopened.perform(.gitReconcilePush, command: f.command, parameters: ["commit": p.mcpFields["commit"]!.mcpString!, "remote": "origin", "endpoint": remote.path, "destination": "refs/heads/mac/result"])
    #expect(restored.mcpFields["state"] == .string("succeeded"))
}

@Test func nativeStopAlsoTerminatesAnObservedChildInAnotherProcessGroup() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { cleanupWorkspaceTestStorage(folder) }
    let engine = NativeProcessEngine()
    let script = "import subprocess,sys,time; p=subprocess.Popen([sys.executable,'-c',\"import time,pathlib; time.sleep(2); pathlib.Path('escaped').write_text('bad')\"],start_new_session=True); print(p.pid,flush=True); time.sleep(30)"
    let command = NativeCommand(projectID: UUID(), root: folder.path, executable: "/usr/bin/python3", arguments: ["-c", script])
    _ = try await engine.start(command)
    let end = ContinuousClock.now.advanced(by: .seconds(3))
    while try await engine.status(command.id).stdout.isEmpty, ContinuousClock.now < end { try await _Concurrency.Task.sleep(for: .milliseconds(20)) }
    try await _Concurrency.Task.sleep(for: .milliseconds(150))
    _ = try await engine.stop(command.id); await engine.stopAll()
    try await _Concurrency.Task.sleep(for: .milliseconds(2100))
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("escaped").path))
}

@Test func nativeExecutorEnforcesFourProcessLimitAndReportsMissingTools() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { cleanupWorkspaceTestStorage(root) }
    let engine = NativeProcessEngine()
    for index in 0..<4 {
        let folder = root.appendingPathComponent(String(index)); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try await engine.start(.init(projectID: UUID(), root: folder.path, executable: "/bin/sleep", arguments: ["30"]))
    }
    await #expect(throws: NativeExecutionError.busy) { _ = try await engine.start(.init(projectID: UUID(), root: root.path, executable: "/bin/echo")) }
    await engine.stopAll()
    let fresh = NativeProcessEngine()
    await #expect(throws: NativeExecutionError.programUnavailable) { _ = try await fresh.start(.init(projectID: UUID(), root: root.path, executable: "/blot-missing-tool")) }
    await fresh.stopAll()
}

@Test func nativeCommitAndPushCanTargetTaskBranchWithoutChangingUserCheckoutOrIndex() async throws {
    let f = try await NativeGitFixture(); defer { cleanupWorkspaceTestStorage(f.folder) }
    _ = try await f.run(["branch", "-m", "main"])
    try Data("task change".utf8).write(to: f.folder.appendingPathComponent("a.txt"))
    try Data("user staged".utf8).write(to: f.folder.appendingPathComponent("b.txt")); _ = try await f.run(["add", "b.txt"])
    let originalIndex = try Data(contentsOf: f.folder.appendingPathComponent(".git/index"))
    let originalHead = try await f.run(["rev-parse", "HEAD"])
    let service = NativeGitService(engine: f.engine)
    _ = try await service.perform(.gitBranch, command: f.command, parameters: ["branch": "mac/task", "base": "HEAD"])
    let prepared = try await service.perform(.gitPrepareCommit, command: f.command, parameters: ["paths": "[\"a.txt\"]", "message": "Focused task", "branch": "mac/task"])
    _ = try await service.perform(.gitCommit, command: f.command, parameters: ["preparation_id": prepared.mcpFields["preparation_id"]!.mcpString!])
    #expect(try await f.run(["symbolic-ref", "--short", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines) == "main")
    #expect(try await f.run(["rev-parse", "HEAD"]) == originalHead)
    #expect(try Data(contentsOf: f.folder.appendingPathComponent(".git/index")) == originalIndex)
    #expect(try await f.run(["show", "mac/task:a.txt"]) == "task change")
    #expect(try await f.run(["show", "mac/task:b.txt"]) == "user\n")
    let remote = f.folder.appendingPathComponent("remote.git")
    _ = try await f.run(["init", "--bare", remote.path]); _ = try await f.run(["remote", "add", "origin", remote.path])
    let push = try await service.perform(.gitPreparePush, command: f.command, parameters: ["remote": "origin", "branch": "mac/task", "source_branch": "mac/task"])
    let pushed = try await service.perform(.gitPush, command: f.command, parameters: ["preparation_id": push.mcpFields["preparation_id"]!.mcpString!])
    #expect(pushed.mcpFields["state"] == .string("succeeded"))
    #expect(try Data(contentsOf: f.folder.appendingPathComponent(".git/index")) == originalIndex)
}
#endif
