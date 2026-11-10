#if os(macOS)
import Foundation
import Darwin

/// Launches one explicitly trusted executable. No shell and no inherited application environment.
public actor MCPStdioTransport: MCPTransport {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let writer = DispatchQueue(label: "dev.blot.mcp.stdin")
    private let timeout: Double
    private var reader: _Concurrency.Task<Void, Never>?
    private var waiting: (ChatJSON, CheckedContinuation<ChatJSON?, Error>)?
    private var timer: _Concurrency.Task<Void, Never>?
    private var closed = false
    private var started = false
    private let executableURL: URL
    private let directoryURL: URL
    private var scopes: [URL] = []
    public init(configuration: MCPConfiguration) throws {
        try configuration.validate()
        guard configuration.transport == .stdio else { throw MCPError.configuration }
        timeout = configuration.timeout
        executableURL = try Self.resolve(configuration.executableBookmark, path: configuration.endpoint)
        directoryURL = try Self.resolve(configuration.directoryBookmark, path: configuration.workingDirectory)
        process.executableURL = executableURL
        process.arguments = configuration.arguments
        process.currentDirectoryURL = directoryURL
        process.environment = configuration.environment
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
    }
    private func start() throws {
        guard !started else { return }; started = true
        for url in [executableURL, directoryURL] where url.startAccessingSecurityScopedResource() { scopes.append(url) }
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingOldest(64)) { continuation in
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { continuation.finish() }
                else if case .dropped = continuation.yield(data) { continuation.finish(throwing: MCPError.responseTooLarge) }
            }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }
        do { try process.run() } catch { close(); throw MCPError.unavailable }
        reader = _Concurrency.Task { [weak self] in
            var buffer = Data()
            do {
                for try await chunk in stream {
                    buffer.append(chunk)
                    guard buffer.count <= 1_048_576 else { throw MCPError.responseTooLarge }
                    while let end = buffer.firstIndex(of: 10) {
                        let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                        if !line.isEmpty { try await self?.receive(JSONDecoder().decode(ChatJSON.self, from: line)) }
                    }
                }
                await self?.fail(MCPError.unavailable)
            } catch { await self?.fail(error) }
        }
    }
    public func exchange(_ message: ChatJSON) async throws -> ChatJSON? {
        try _Concurrency.Task.checkCancellation()
        guard !closed, waiting == nil else { throw MCPError.unavailable }
        try start()
        guard let id = message.mcpFields["id"] else { try await write(message); return nil }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting = (id, continuation)
                timer = _Concurrency.Task { [weak self, timeout] in
                    do { try await _Concurrency.Task.sleep(for: .seconds(timeout)); await self?.fail(MCPError.timeout) } catch {}
                }
                _Concurrency.Task {
                    do { try await write(message) } catch { fail(error) }
                }
            }
        } onCancel: { _Concurrency.Task { await self.fail(CancellationError()) } }
    }
    private func write(_ value: ChatJSON) async throws {
        var data = try WorkspaceCoding.encode(value); data.append(10)
        guard data.count <= 64 * 1024 else { throw MCPError.responseTooLarge }
        let bytes = data, handle = input.fileHandleForWriting
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.async {
                do { try handle.write(contentsOf: bytes); continuation.resume() }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func receive(_ value: ChatJSON) async throws {
        let fields = value.mcpFields
        guard fields["jsonrpc"] == .string("2.0") else { throw MCPError.protocolViolation }
        if let method = fields["method"]?.mcpString {
            if let id = fields["id"] {
                try await write(method == "ping" ? .object(["jsonrpc": .string("2.0"), "id": id, "result": .object([:])]) :
                    .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(-32601), "message": .string("Client capability not supported")])]))
            }
        } else if let pending = waiting, fields["id"] == pending.0 {
            waiting = nil; timer?.cancel(); timer = nil; pending.1.resume(returning: value)
        } else { throw MCPError.protocolViolation }
    }
    private func fail(_ error: Error) {
        let pending = waiting; waiting = nil; timer?.cancel(); timer = nil
        pending?.1.resume(throwing: error)
        close()
    }
    public func close() {
        guard !closed else { return }; closed = true
        reader?.cancel(); reader = nil; timer?.cancel(); timer = nil
        output.fileHandleForReading.readabilityHandler = nil; errors.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            process.terminate()
            let child = process
            _Concurrency.Task.detached {
                try? await _Concurrency.Task.sleep(for: .seconds(1))
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        try? input.fileHandleForWriting.close()
        for url in scopes { url.stopAccessingSecurityScopedResource() }; scopes = []
        let pending = waiting; waiting = nil; pending?.1.resume(throwing: MCPError.unavailable)
    }
    private static func resolve(_ data: Data?, path: String) throws -> URL {
        guard let data else { return URL(fileURLWithPath: path) }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale, url.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path else { throw MCPError.configuration }
        return url
    }
}
#endif
