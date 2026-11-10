#if os(macOS)
import Foundation
import Security

@objc public protocol NativeExecutorXPC {
    func perform(_ data: Data, reply: @escaping (Data?, String?) -> Void)
    func shutdown(reply: @escaping () -> Void)
}

public enum NativeCodeIdentity {
    public static func requirement(at url: URL) throws -> String {
        var code: SecStaticCode?, requirement: SecRequirement?, text: CFString?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: UInt32(kSecCSCheckAllArchitectures)), nil) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess, let text else { throw NativeExecutionError.unavailable }
        return text as String
    }
}

/// No public socket or legacy backend endpoint. The OS enforces the embedded helper's exact code requirement.
public actor NativeXPCClient: NativeExecuting {
    public static let identifier = "dev.blot.workspace-executor"
    private var connection: NSXPCConnection?
    private var pending: [UUID: CheckedContinuation<ChatJSON, Error>] = [:]
    private var timers: [UUID: _Concurrency.Task<Void, Never>] = [:]
    private var stopped = false
    public init() {}
    private func connect() throws -> NSXPCConnection {
        guard !stopped else { throw NativeExecutionError.unavailable }
        if let connection { return connection }
        let service = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/BlotWorkspaceExecutor.xpc")
        let requirement = try NativeCodeIdentity.requirement(at: service)
        let connection = NSXPCConnection(serviceName: Self.identifier)
        connection.remoteObjectInterface = NSXPCInterface(with: NativeExecutorXPC.self)
        connection.setCodeSigningRequirement(requirement)
        connection.interruptionHandler = { [weak self] in _Concurrency.Task { await self?.failed() } }
        connection.invalidationHandler = { [weak self] in _Concurrency.Task { await self?.failed() } }
        connection.resume(); self.connection = connection
        return connection
    }
    public func request(_ request: NativeRequest) async throws -> ChatJSON {
        let connection = try connect(), data = try WorkspaceCoding.encode(request), id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                let proxy = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in _Concurrency.Task { await self?.finish(id, data: nil, error: "unavailable") } }
                guard let executor = proxy as? NativeExecutorXPC else { finish(id, data: nil, error: "unavailable"); return }
                executor.perform(data) { [weak self] data, error in _Concurrency.Task { await self?.finish(id, data: data, error: error) } }
                timers[id] = _Concurrency.Task { [weak self] in
                    do { try await _Concurrency.Task.sleep(for: .seconds(130)); await self?.expire(id) } catch {}
                }
            }
        } onCancel: { _Concurrency.Task { await self.expire(id) } }
    }
    private func finish(_ id: UUID, data: Data?, error: String?) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        timers.removeValue(forKey: id)?.cancel()
        if let data, data.count <= 8 * 1024 * 1024, let result = try? JSONDecoder().decode(ChatJSON.self, from: data) { continuation.resume(returning: result) }
        else { continuation.resume(throwing: NativeExecutionError.remote(error ?? "unavailable")) }
    }
    private func expire(_ id: UUID) { timers.removeValue(forKey: id)?.cancel(); pending.removeValue(forKey: id)?.resume(throwing: NativeExecutionError.unknown) }
    private func failed() {
        connection = nil
        for timer in timers.values { timer.cancel() }; timers = [:]
        let continuations = pending.values; pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: NativeExecutionError.unknown) }
    }
    public func stopAll() async {
        stopped = true
        if let connection, let proxy = connection.remoteObjectProxy as? NativeExecutorXPC {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let once = NativeShutdownReply(continuation)
                proxy.shutdown { once.finish() }
                _Concurrency.Task { try? await _Concurrency.Task.sleep(for: .seconds(4)); once.finish() }
            }
            connection.invalidate()
        }
        connection = nil; failed()
    }
}

private final class NativeShutdownReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    init(_ continuation: CheckedContinuation<Void, Never>) { self.continuation = continuation }
    func finish() { lock.lock(); let value = continuation; continuation = nil; lock.unlock(); value?.resume() }
}
#endif
