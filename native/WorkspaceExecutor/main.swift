import BlotWorkspace
import Foundation

/// Each authenticated app connection owns its executor. Losing the app closes all its child processes.
final class ExecutorConnection: NSObject, NativeExecutorXPC, @unchecked Sendable {
    let executor = NativeExecutor()
    func perform(_ data: Data, reply: @escaping (Data?, String?) -> Void) {
        let response = ExecutorResponse(reply)
        Task {
            do {
                guard data.count <= 2 * 1024 * 1024 else { throw NativeExecutionError.invalidRequest }
                let request = try JSONDecoder().decode(NativeRequest.self, from: data)
                guard request.operation == .workspaceRecord || data.count <= 128 * 1024 else { throw NativeExecutionError.invalidRequest }
                let result = try await executor.request(request)
                response.send(try JSONEncoder().encode(result), nil)
            } catch {
                let failure = error as? NativeExecutionError ?? .unknown
                response.send(nil, failure.wireCode + ":" + failure.localizedDescription)
            }
        }
    }
    func shutdown(reply: @escaping () -> Void) {
        let response = ExecutorResponse { _, _ in reply() }
        Task { await executor.stopAll(); response.send(nil, nil) }
    }
}
private final class ExecutorResponse: @unchecked Sendable {
    let reply: (Data?, String?) -> Void
    init(_ reply: @escaping (Data?, String?) -> Void) { self.reply = reply }
    func send(_ data: Data?, _ error: String?) { reply(data, error) }
}

final class ExecutorListener: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        let main = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard let requirement = try? NativeCodeIdentity.requirement(at: main) else { return false }
        connection.setCodeSigningRequirement(requirement)
        let owner = ExecutorConnection()
        connection.exportedInterface = NSXPCInterface(with: NativeExecutorXPC.self)
        connection.exportedObject = owner
        connection.invalidationHandler = { Task { await owner.executor.stopAll() } }
        connection.interruptionHandler = { Task { await owner.executor.stopAll() } }
        connection.resume(); return true
    }
}
let delegate = ExecutorListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
