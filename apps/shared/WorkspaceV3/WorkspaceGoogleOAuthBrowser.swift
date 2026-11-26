import BlotWorkspace
import Foundation
import Dispatch
#if os(macOS)
import AppKit
import Network
#endif

@MainActor final class WorkspaceGoogleOAuthBrowser {
    private let native = WorkspaceMCPOAuthBrowser()
    #if os(macOS)
    private var receiver: WorkspaceGoogleLoopbackReceiver?
    #endif
    func cancel() {
        native.cancel()
        #if os(macOS)
        receiver?.cancel()
        #endif
    }
    func signIn(configuration: GoogleOAuthConfiguration, access: Set<GoogleAccess>) async throws -> (GoogleOAuthAuthorization, URL) {
        #if os(macOS)
        guard configuration.usesLoopback, receiver == nil else { throw GoogleOAuthError.invalidConfiguration }
        let receiver = WorkspaceGoogleLoopbackReceiver()
        self.receiver = receiver
        defer { receiver.cancel(); self.receiver = nil }
        let port = try await receiver.start()
        let authorization = try GoogleOAuthAuthorization(configuration: configuration.loopback(port: port), access: access)
        let callback = try await receiver.callback(authorization: authorization) {
            NSWorkspace.shared.open(authorization.url)
        }
        NSApp.activate()
        return (authorization, callback)
        #else
        let authorization = try GoogleOAuthAuthorization(configuration: configuration, access: access)
        return (authorization, try await native.signIn(url: authorization.url, redirectURI: configuration.redirectURI))
        #endif
    }
}

#if os(macOS)
/// Receives one state/PKCE-bound redirect on an ephemeral IPv4 loopback port.
@MainActor private final class WorkspaceGoogleLoopbackReceiver {
    private var listener: NWListener?
    private var ready: CheckedContinuation<UInt16, Error>?
    private var waiting: CheckedContinuation<URL, Error>?
    private var authorization: GoogleOAuthAuthorization?
    private var timeout: _Concurrency.Task<Void, Never>?
    private var connections: [UUID: NWConnection] = [:]
    private var buffers: [UUID: Data] = [:]
    private var completed = false
    private let queue = DispatchQueue(label: "dev.blot.google-oauth-loopback")

    func start() async throws -> UInt16 {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    listener.stateUpdateHandler = { [weak self, weak listener] state in
                        _Concurrency.Task { @MainActor in
                            guard let self else { return }
                            switch state {
                            case .ready:
                                guard let port = listener?.port?.rawValue else { self.finish(.failure(GoogleOAuthError.serviceUnavailable)); return }
                                let ready = self.ready; self.ready = nil; ready?.resume(returning: port)
                            case .failed: self.finish(.failure(GoogleOAuthError.serviceUnavailable))
                            default: break
                            }
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in
                        _Concurrency.Task { @MainActor in self?.accept(connection) }
                    }
                    listener.start(queue: queue)
                } catch { finish(.failure(GoogleOAuthError.serviceUnavailable)) }
            }
        } onCancel: { _Concurrency.Task { @MainActor [weak self] in self?.cancel() } }
    }

    func callback(authorization: GoogleOAuthAuthorization, open: () -> Bool) async throws -> URL {
        self.authorization = authorization
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting = continuation
                timeout = _Concurrency.Task { [weak self] in
                    do { try await _Concurrency.Task.sleep(for: .seconds(600)); self?.finish(.failure(GoogleOAuthError.authorizationExpired)) }
                    catch {}
                }
                if !open() { finish(.failure(GoogleOAuthError.serviceUnavailable)) }
            }
        } onCancel: { _Concurrency.Task { @MainActor [weak self] in self?.cancel() } }
    }

    func cancel() { finish(.failure(CancellationError())) }

    private func accept(_ connection: NWConnection) {
        guard connections.count < 8, authorization != nil else { connection.cancel(); return }
        let id = UUID(); connections[id] = connection; buffers[id] = Data()
        connection.start(queue: queue)
        receive(id)
    }
    private func receive(_ id: UUID) {
        guard let connection = connections[id] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            _Concurrency.Task { @MainActor in
                guard let self, self.connections[id] != nil else { return }
                if let data { self.buffers[id, default: Data()].append(data) }
                guard let buffer = self.buffers[id], buffer.count <= 16384 else { self.close(id); return }
                if buffer.range(of: Data("\r\n\r\n".utf8)) != nil { self.handle(buffer, id: id) }
                else if complete || error != nil { self.close(id) }
                else { self.receive(id) }
            }
        }
    }
    private func handle(_ data: Data, id: UUID) {
        guard let authorization, let line = String(data: data, encoding: .utf8)?.components(separatedBy: "\r\n").first else { close(id); return }
        let parts = line.split(separator: " ")
        guard parts.count == 3, parts[0] == "GET", parts[1].hasPrefix("/oauthredirect?"),
              var url = URLComponents(url: authorization.configuration.redirectURI, resolvingAgainstBaseURL: false),
              let received = URLComponents(string: String(parts[1])), received.scheme == nil, received.host == nil,
              received.path == url.path, received.fragment == nil else { reply(id, valid: false); return }
        url.percentEncodedQuery = received.percentEncodedQuery
        guard let callback = url.url else { reply(id, valid: false); return }
        do {
            _ = try authorization.tokenRequest(callback: callback)
            reply(id, valid: true)
            finish(.success(callback), preserving: id)
        } catch GoogleOAuthError.accessDenied {
            reply(id, valid: false)
            finish(.failure(GoogleOAuthError.accessDenied), preserving: id)
        } catch { reply(id, valid: false) }
    }
    private func reply(_ id: UUID, valid: Bool) {
        guard let connection = connections[id] else { return }
        let message = valid ? "Вход завершён. Вернитесь в Ori. Эту вкладку можно закрыть." : "Этот запрос входа не принят. Вернитесь в Ori и повторите подключение."
        let body = Data(("<!doctype html><html lang=ru><meta charset=utf-8><title>Ori</title><p>" + message + "</p></html>").utf8)
        var response = Data("HTTP/1.1 \(valid ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; frame-ancestors 'none'\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            connection.cancel()
            _Concurrency.Task { @MainActor in self?.close(id) }
        })
    }
    private func close(_ id: UUID) { connections.removeValue(forKey: id)?.cancel(); buffers[id] = nil }
    private func finish(_ result: Result<URL, Error>, preserving: UUID? = nil) {
        guard !completed else { return }
        completed = true
        let ready = ready; self.ready = nil
        if let ready { ready.resume(throwing: GoogleOAuthError.serviceUnavailable) }
        let waiting = waiting; self.waiting = nil
        waiting?.resume(with: result)
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil; authorization = nil
        for id in Array(connections.keys) where id != preserving { close(id) }
    }
}
#endif
