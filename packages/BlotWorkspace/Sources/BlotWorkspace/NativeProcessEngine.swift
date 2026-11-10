#if os(macOS)
import Darwin
import Foundation

/// Owns process groups and bounded pipe buffers. It never evaluates a command through an implicit shell.
public actor NativeProcessEngine {
    private struct Job {
        let command: NativeCommand
        let pid: pid_t
        let started: Date
        let output: FileHandle
        let errors: FileHandle
        var stdout = Data(), stderr = Data()
        var truncated = false
        var state = NativeProcessSnapshot.State.running
        var exitCode: Int32?
        var finished: Date?
        var timer: _Concurrency.Task<Void, Never>?
        var watcher: _Concurrency.Task<Void, Never>?
        var descendants: [pid_t: NativeProcessIdentity] = [:]
        var openPipes = 2
    }
    private var jobs: [UUID: Job] = [:]
    private var stopped = false
    public init() {}

    public func start(_ command: NativeCommand) throws -> NativeProcessSnapshot {
        guard !stopped else { throw NativeExecutionError.unavailable }
        try command.validate()
        if let old = jobs[command.id] {
            guard old.command == command else { throw NativeExecutionError.changed }
            return snapshot(old)
        }
        let active = jobs.values.filter { $0.finished == nil }
        guard active.count < 4, !active.contains(where: { $0.command.projectID == command.projectID || $0.command.root == command.root }) else { throw NativeExecutionError.busy }
        let cwd = try NativeProjectFiles(root: command.root).url(command.directory, directory: true)
        var stdoutFD: [Int32] = [0, 0], stderrFD: [Int32] = [0, 0]
        guard pipe(&stdoutFD) == 0 else { throw NativeExecutionError.unavailable }
        guard pipe(&stderrFD) == 0 else { close(stdoutFD[0]); close(stdoutFD[1]); throw NativeExecutionError.unavailable }
        var actions: posix_spawn_file_actions_t?, attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions); posix_spawnattr_init(&attributes)
        defer { posix_spawn_file_actions_destroy(&actions); posix_spawnattr_destroy(&attributes) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, stdoutFD[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&actions, stderrFD[1], STDERR_FILENO)
        for fd in stdoutFD + stderrFD { posix_spawn_file_actions_addclose(&actions, fd) }
        posix_spawn_file_actions_addchdir(&actions, cwd.path)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
        posix_spawnattr_setpgroup(&attributes, 0)
        let args = ([command.executable] + command.arguments).map { strdup($0) } + [nil]
        let env = command.environment.sorted { $0.key < $1.key }.map { strdup($0.key + "=" + $0.value) } + [nil]
        defer { for value in args + env { free(value) } }
        var child: pid_t = 0
        let result = args.withUnsafeBufferPointer { argv in env.withUnsafeBufferPointer { envp in
            posix_spawn(&child, command.executable, &actions, &attributes, UnsafeMutablePointer(mutating: argv.baseAddress!), UnsafeMutablePointer(mutating: envp.baseAddress!))
        } }
        close(stdoutFD[1]); close(stderrFD[1])
        guard result == 0 else { close(stdoutFD[0]); close(stderrFD[0]); throw NativeExecutionError.programUnavailable }
        let out = FileHandle(fileDescriptor: stdoutFD[0], closeOnDealloc: true), err = FileHandle(fileDescriptor: stderrFD[0], closeOnDealloc: true)
        jobs[command.id] = Job(command: command, pid: child, started: Date(), output: out, errors: err)
        read(out, id: command.id, error: false); read(err, id: command.id, error: true)
        jobs[command.id]?.watcher = _Concurrency.Task { [weak self] in
            while !_Concurrency.Task.isCancelled {
                await self?.observe(command.id)
                do { try await _Concurrency.Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
        jobs[command.id]?.timer = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .seconds(command.timeout)); await self?.terminate(command.id, state: .timedOut) } catch {}
        }
        let pid = child
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
            let exitStatus = status
            _Concurrency.Task { await self?.exited(command.id, status: exitStatus) }
        }
        if jobs.count > 100 {
            for key in jobs.values.filter({ $0.finished != nil }).sorted(by: { $0.started < $1.started }).prefix(jobs.count - 100).map(\.command.id) { jobs[key] = nil }
        }
        return snapshot(jobs[command.id]!)
    }
    public func status(_ id: UUID) throws -> NativeProcessSnapshot {
        guard let job = jobs[id] else { throw NativeExecutionError.unknown }; return snapshot(job)
    }
    public func active(in root: String) -> Bool { jobs.values.contains { $0.finished == nil && $0.command.root == root } }
    public func stop(_ id: UUID) throws -> NativeProcessSnapshot {
        guard jobs[id] != nil else { throw NativeExecutionError.unknown }
        terminate(id, state: .canceled); return snapshot(jobs[id]!)
    }
    public func stopAll() async {
        stopped = true
        for id in jobs.keys { terminate(id, state: .canceled) }
        let end = ContinuousClock.now.advanced(by: .seconds(3))
        while jobs.values.contains(where: { $0.finished == nil }), ContinuousClock.now < end { try? await _Concurrency.Task.sleep(for: .milliseconds(20)) }
    }
    private func read(_ handle: FileHandle, id: UUID, error: Bool) {
        let state = NativePipeState()
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(16)) { continuation in
            handle.readabilityHandler = { handle in
                let bytes = handle.availableData
                if bytes.isEmpty { handle.readabilityHandler = nil; continuation.finish() }
                else if case .dropped = continuation.yield(bytes) {
                    state.drop()
                }
            }
        }
        _Concurrency.Task { [weak self] in
            for await bytes in stream { await self?.append(bytes, id: id, error: error) }
            if state.dropped { await self?.markTruncated(id) }
            await self?.append(Data(), id: id, error: error)
        }
    }
    private func markTruncated(_ id: UUID) { jobs[id]?.truncated = true }
    private func append(_ bytes: Data, id: UUID, error: Bool) {
        guard var job = jobs[id] else { return }
        if bytes.isEmpty { job.openPipes = max(0, job.openPipes - 1) }
        let available = max(0, 1_048_576 - job.stdout.count - job.stderr.count)
        let accepted = bytes.prefix(available)
        if error { job.stderr.append(accepted) } else { job.stdout.append(accepted) }
        job.truncated = job.truncated || accepted.count != bytes.count
        if job.exitCode != nil && job.openPipes == 0 { job.finished = Date() }
        jobs[id] = job
    }
    private func terminate(_ id: UUID, state: NativeProcessSnapshot.State) {
        observe(id)
        guard var job = jobs[id], job.finished == nil, job.exitCode == nil else { return }
        job.state = state; jobs[id] = job
        let pid = job.pid
        for child in job.descendants.values { child.signal(SIGTERM) }
        kill(-pid, SIGTERM)
        _Concurrency.Task { [weak self] in
            try? await _Concurrency.Task.sleep(for: .milliseconds(500))
            await self?.force(id, pid: pid)
        }
    }
    private func force(_ id: UUID, pid: pid_t) {
        guard let job = jobs[id], job.pid == pid, job.finished == nil else { return }
        for child in job.descendants.values { child.signal(SIGKILL) }
        kill(-pid, SIGKILL)
    }
    private func exited(_ id: UUID, status: Int32) {
        guard var job = jobs[id] else { return }
        job.timer?.cancel(); job.timer = nil
        job.watcher?.cancel(); job.watcher = nil
        for child in job.descendants.values { child.signal(SIGKILL) }
        let code = (status & 0x7f) == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
        job.exitCode = code
        if job.state == .running { job.state = code == 0 ? .succeeded : .failed }
        // A child must not leave background grandchildren holding output pipes or running after the job ends.
        kill(-job.pid, SIGKILL)
        if job.openPipes == 0 { job.finished = Date() }
        jobs[id] = job
    }
    private func observe(_ id: UUID) {
        guard var job = jobs[id], job.exitCode == nil else { return }
        job.descendants.merge(NativeProcessIdentity.descendants(of: job.pid)) { _, new in new }
        jobs[id] = job
    }
    private func snapshot(_ job: Job) -> NativeProcessSnapshot {
        .init(id: job.command.id, projectID: job.command.projectID, executable: job.command.executable, arguments: job.command.arguments,
              state: job.state, stdout: String(decoding: job.stdout, as: UTF8.self),
              stderr: String(decoding: job.stderr, as: UTF8.self), truncated: job.truncated, exitCode: job.exitCode, startedAt: job.started, finishedAt: job.finished)
    }
}

private final class NativePipeState: @unchecked Sendable {
    private let lock = NSLock()
    private var lost = false
    var dropped: Bool { lock.lock(); defer { lock.unlock() }; return lost }
    func drop() { lock.lock(); lost = true; lock.unlock() }
}
#endif
