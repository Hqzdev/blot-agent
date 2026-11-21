import AuthenticationServices
import BlotWorkspace
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class WorkspaceBrowserAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: ASPresentationAnchor?
    private var attemptID: UUID?
    private var continuation: CheckedContinuation<URL, Error>?
    func signIn(_ authorization: WorkspaceBrowserAuthorization) async throws -> URL {
        try _Concurrency.Task.checkCancellation()
        guard session == nil else { throw WorkspaceCloudError.authenticationRequired }
        #if os(macOS)
        anchor = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        #else
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        #endif
        guard anchor != nil else { throw WorkspaceCloudError.authenticationRequired }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try _Concurrency.Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.attemptID = id
                self.continuation = continuation
                let attempt = ASWebAuthenticationSession(url: authorization.url, callbackURLScheme: authorization.callbackURL.scheme) { [weak self] callback, error in
                    _Concurrency.Task { @MainActor in
                        if let callback { self?.finish(id: id, result: .success(callback)) }
                        else if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                            self?.finish(id: id, result: .failure(CancellationError()))
                        } else {
                            self?.finish(id: id, result: .failure(error ?? WorkspaceCloudError.authenticationRequired))
                        }
                    }
                }
                attempt.presentationContextProvider = self
                session = attempt
                if !attempt.start() {
                    finish(id: id, result: .failure(WorkspaceCloudError.authenticationRequired))
                }
            }
        } onCancel: {
            _Concurrency.Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }
    private func cancel(id: UUID) {
        guard attemptID == id else { return }
        let pending = session
        finish(id: id, result: .failure(CancellationError()))
        pending?.cancel()
    }
    private func finish(id: UUID, result: Result<URL, Error>) {
        guard attemptID == id else { return }
        let pending = continuation
        continuation = nil; session = nil; anchor = nil; attemptID = nil
        pending?.resume(with: result)
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let anchor else { preconditionFailure("Authentication requires an active presentation window") }
        return anchor
    }
}
