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
    func signIn(_ authorization: WorkspaceBrowserAuthorization) async throws -> URL {
        try _Concurrency.Task.checkCancellation()
        guard session == nil else { throw WorkspaceCloudError.authenticationRequired }
        #if os(macOS)
        anchor = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible })
        #else
        anchor = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)
        #endif
        guard anchor != nil else { throw WorkspaceCloudError.authenticationRequired }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let attempt = ASWebAuthenticationSession(url: authorization.url, callbackURLScheme: authorization.callbackURL.scheme) { [weak self] callback, error in
                    _Concurrency.Task { @MainActor in
                        self?.session = nil; self?.anchor = nil
                        if let callback { continuation.resume(returning: callback) }
                        else { continuation.resume(throwing: error ?? WorkspaceCloudError.authenticationRequired) }
                    }
                }
                attempt.presentationContextProvider = self
                session = attempt
                if !attempt.start() {
                    session = nil; anchor = nil
                    continuation.resume(throwing: WorkspaceCloudError.authenticationRequired)
                }
            }
        } onCancel: {
            _Concurrency.Task { @MainActor [weak self] in self?.session?.cancel() }
        }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let anchor else { preconditionFailure("Authentication requires an active presentation window") }
        return anchor
    }
}
