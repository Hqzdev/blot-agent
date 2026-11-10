import AuthenticationServices
import BlotWorkspace
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
protocol WorkspaceBrowserSession: AnyObject {
    func start() -> Bool
    func cancel()
}

extension ASWebAuthenticationSession: WorkspaceBrowserSession {}

@MainActor
final class WorkspaceBrowserAuthenticator {
    typealias SessionFactory = (WorkspaceBrowserAuthorization, ASWebAuthenticationPresentationContextProviding,
        @escaping ASWebAuthenticationSession.CompletionHandler) -> any WorkspaceBrowserSession

    private let makeSession: SessionFactory
    private let findAnchor: () -> ASPresentationAnchor?
    private var activeAttempt: Attempt?

    init(makeSession: SessionFactory? = nil, findAnchor: (() -> ASPresentationAnchor?)? = nil) {
        self.makeSession = makeSession ?? Self.makeSystemSession
        self.findAnchor = findAnchor ?? Self.foregroundAnchor
    }

    func signIn(_ authorization: WorkspaceBrowserAuthorization) async throws -> URL {
        try _Concurrency.Task.checkCancellation()
        guard activeAttempt == nil, let anchor = findAnchor() else {
            throw WorkspaceCloudError.authenticationRequired
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !_Concurrency.Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let attempt = Attempt(id: id, anchor: anchor, continuation: continuation)
                activeAttempt = attempt
                let session = makeSession(authorization, attempt) { [weak self] callback, error in
                    _Concurrency.Task { @MainActor in
                        let result: Result<URL, Error> = callback.map { .success($0) }
                            ?? .failure(error ?? WorkspaceCloudError.authenticationRequired)
                        self?.complete(id, with: result)
                    }
                }
                attempt.session = session
                if !session.start() {
                    complete(id, with: .failure(WorkspaceCloudError.authenticationRequired))
                }
            }
        } onCancel: {
            _Concurrency.Task { @MainActor [weak self] in self?.cancel(id) }
        }
    }

    private func complete(_ id: UUID, with result: Result<URL, Error>) {
        // start(), callbacks, and cancellation all compete for this one terminal result.
        guard let attempt = activeAttempt, attempt.id == id else { return }
        activeAttempt = nil
        attempt.continuation.resume(with: result)
    }

    private func cancel(_ id: UUID) {
        guard let attempt = activeAttempt, attempt.id == id else { return }
        complete(id, with: .failure(CancellationError()))
        attempt.session?.cancel()
    }

    private static func makeSystemSession(_ authorization: WorkspaceBrowserAuthorization,
        context: ASWebAuthenticationPresentationContextProviding,
        completion: @escaping ASWebAuthenticationSession.CompletionHandler) -> any WorkspaceBrowserSession {
        let session = ASWebAuthenticationSession(url: authorization.url,
            callbackURLScheme: authorization.callbackURL.scheme, completionHandler: completion)
        session.presentationContextProvider = context
        return session
    }

    private static func foregroundAnchor() -> ASPresentationAnchor? {
        #if os(macOS)
        guard NSApp.isActive else { return nil }
        return NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && !$0.isMiniaturized })
        #else
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows).first { $0.isKeyWindow && !$0.isHidden }
        #endif
    }

    /// Keeps the selected window alive for this session, independent of later attempts.
    private final class Attempt: NSObject, ASWebAuthenticationPresentationContextProviding {
        let id: UUID
        let continuation: CheckedContinuation<URL, Error>
        private let anchor: ASPresentationAnchor
        var session: (any WorkspaceBrowserSession)?

        init(id: UUID, anchor: ASPresentationAnchor, continuation: CheckedContinuation<URL, Error>) {
            self.id = id
            self.anchor = anchor
            self.continuation = continuation
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor }
    }
}
