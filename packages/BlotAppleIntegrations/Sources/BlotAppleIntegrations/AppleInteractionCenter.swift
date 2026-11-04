import BlotWorkspace
import Foundation
import Observation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

public struct AppleInteraction: Identifiable, Sendable {
    public enum Kind: Sendable { case confirmation, mail }
    public let id: UUID
    public let kind: Kind
    public let title: String
    public let details: String
    public let fields: [String: String]
}

/// Serializes native UI requests; cancellation and timeout always release the awaiting tool.
@MainActor @Observable
public final class AppleInteractionCenter {
    public private(set) var pending: AppleInteraction?
    private var queue: [AppleInteraction] = []
    @ObservationIgnored private var continuations: [UUID: CheckedContinuation<ChatJSON, Error>] = [:]
    @ObservationIgnored private var shortcutTokens: Set<UUID> = []
    @ObservationIgnored private var timeouts: [UUID: _Concurrency.Task<Void, Never>] = [:]
    public init() {}
    public func finish(_ id: UUID, result: Result<ChatJSON, Error>) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        timeouts.removeValue(forKey: id)?.cancel()
        shortcutTokens.remove(id)
        queue.removeAll { $0.id == id }
        if pending?.id == id { pending = queue.isEmpty ? nil : queue.removeFirst() }
        continuation.resume(with: result)
    }
    public func cancelAll() {
        for id in Array(continuations.keys) { finish(id, result: .failure(AppleIntegrationError.canceled)) }
    }
    func confirm(title: String, details: String) async throws -> Bool {
        let result = try await request(.init(id: UUID(), kind: .confirmation, title: title, details: details, fields: [:]))
        return result == .bool(true)
    }
    func compose(_ a: AppleArguments) async throws -> ChatJSON {
        try await request(.init(id: UUID(), kind: .mail, title: "Письмо", details: "Отправка в системном редакторе",
            fields: ["recipient": try a.required("recipient"), "subject": a["subject"] ?? "", "body": a["body"] ?? ""]))
    }
    func runShortcut(name: String, input: String) async throws -> ChatJSON {
        let token = UUID()
        #if os(macOS)
        let scheme = "blot-agent-macos"
        #else
        let scheme = "blot-agent-ios"
        #endif
        func callback(_ status: String) -> String { "\(scheme)://apple-shortcut/\(token.uuidString)/\(status)" }
        var components = URLComponents(); components.scheme = "shortcuts"; components.host = "x-callback-url"; components.path = "/run-shortcut"
        components.queryItems = [.init(name: "name", value: name), .init(name: "input", value: "text"), .init(name: "text", value: input),
            .init(name: "x-success", value: callback("success")), .init(name: "x-cancel", value: callback("cancel")), .init(name: "x-error", value: callback("error"))]
        guard let url = components.url else { throw AppleIntegrationError.invalidArguments }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[token] = continuation; shortcutTokens.insert(token); scheduleTimeout(token)
                #if os(macOS)
                if !NSWorkspace.shared.open(url) { finish(token, result: .failure(AppleIntegrationError.unavailable)) }
                #else
                UIApplication.shared.open(url) { [weak self] opened in
                    if !opened { self?.finish(token, result: .failure(AppleIntegrationError.unavailable)) }
                }
                #endif
            }
        } onCancel: { _Concurrency.Task { @MainActor in self.finish(token, result: .failure(CancellationError())) } }
    }
    @discardableResult public func handle(_ url: URL) -> Bool {
        guard ["blot-agent-macos", "blot-agent-ios"].contains(url.scheme ?? ""), url.host == "apple-shortcut" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let token = UUID(uuidString: parts[0]), shortcutTokens.contains(token) else { return true }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        switch parts[1] {
        case "success":
            let value = items.first { $0.name == "result" }?.value ?? ""
            guard value.utf8.count <= 48 * 1024 else { finish(token, result: .failure(AppleIntegrationError.invalidArguments)); return true }
            finish(token, result: .success(appleObject(["state": "completed", "result": value])))
        case "cancel": finish(token, result: .failure(AppleIntegrationError.canceled))
        case "error": finish(token, result: .failure(AppleIntegrationError.system(String((items.first { $0.name == "errorMessage" }?.value ?? "Ошибка команды").prefix(1000)))))
        default: break
        }
        return true
    }
    private func request(_ interaction: AppleInteraction) async throws -> ChatJSON {
        try _Concurrency.Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                continuations[interaction.id] = continuation
                if pending == nil { pending = interaction } else { queue.append(interaction) }
                scheduleTimeout(interaction.id)
            }
        } onCancel: { _Concurrency.Task { @MainActor in self.finish(interaction.id, result: .failure(CancellationError())) } }
    }
    private func scheduleTimeout(_ id: UUID) {
        timeouts[id] = _Concurrency.Task { [weak self] in
            do { try await _Concurrency.Task.sleep(for: .seconds(300)) } catch { return }
            self?.finish(id, result: .failure(AppleIntegrationError.uncertainResult))
        }
    }
}
