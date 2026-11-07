import AuthenticationServices
import BlotWorkspace
import UIKit
import XCTest

@MainActor
final class WorkspaceBrowserAuthenticatorTests: XCTestCase {
    func testFailedStartAndCallbackCompleteOnlyOnce() async throws {
        let browser = BrowserSessionFixture()
        browser.startResult = false
        browser.onStart = { $0(nil, URLError(.cancelled)) }
        let authenticator = try browser.authenticator()
        do {
            _ = try await authenticator.signIn(authorization())
            XCTFail("A failed session must throw")
        } catch { XCTAssertTrue(error is WorkspaceCloudError) }
        await drainCallbacks()
        XCTAssertEqual(browser.sessions.count, 1)
    }

    func testLateCallbackFromFailedAttemptCannotCompleteNextSignIn() async throws {
        let browser = BrowserSessionFixture()
        browser.startResult = false
        let authenticator = try browser.authenticator()
        do { _ = try await authenticator.signIn(authorization()); XCTFail("Expected failed start") }
        catch { XCTAssertTrue(error is WorkspaceCloudError) }
        let first = try XCTUnwrap(browser.sessions.first)
        browser.startResult = true
        let second = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(2, in: browser)
        first.callback(nil, URLError(.cancelled))
        await drainCallbacks()
        let callback = URL(string: "blot-agent-ios:/oauth/account?code=second")!
        browser.sessions[1].callback(callback, nil)
        let secondResult = try await second.value
        XCTAssertEqual(secondResult, callback)
    }

    func testDuplicateCallbacksReturnFirstResultAndPermitAnotherAttempt() async throws {
        let browser = BrowserSessionFixture()
        let authenticator = try browser.authenticator()
        let task = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(1, in: browser)
        let callback = URL(string: "blot-agent-ios:/oauth/account?code=first")!
        browser.sessions[0].callback(callback, nil)
        browser.sessions[0].callback(nil, URLError(.cancelled))
        let taskResult = try await task.value
        XCTAssertEqual(taskResult, callback)
        await drainCallbacks()
        let next = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(2, in: browser)
        browser.sessions[1].callback(callback, nil)
        let nextResult = try await next.value
        XCTAssertEqual(nextResult, callback)
    }

    func testCancellationFinishesWithoutCallbackAndLateResultLeavesNewAttemptAlone() async throws {
        let browser = BrowserSessionFixture()
        let authenticator = try browser.authenticator()
        let task = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(1, in: browser)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected task cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await drainCallbacks()
        XCTAssertEqual(browser.sessions[0].cancelCount, 1)
        let next = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(2, in: browser)
        browser.sessions[0].callback(nil, URLError(.cancelled))
        await drainCallbacks()
        XCTAssertEqual(browser.sessions[1].cancelCount, 0)
        let callback = URL(string: "blot-agent-ios:/oauth/account?code=next")!
        browser.sessions[1].callback(callback, nil)
        let nextResult = try await next.value
        XCTAssertEqual(nextResult, callback)
    }

    func testOverlappingAttemptIsRejectedAndOriginalStillCompletes() async throws {
        let browser = BrowserSessionFixture()
        let authenticator = try browser.authenticator()
        let first = _Concurrency.Task { try await authenticator.signIn(authorization()) }
        await waitForSessions(1, in: browser)
        do { _ = try await authenticator.signIn(authorization()); XCTFail("Expected duplicate rejection") }
        catch { XCTAssertTrue(error is WorkspaceCloudError) }
        XCTAssertEqual(browser.sessions.count, 1)
        let callback = URL(string: "blot-agent-ios:/oauth/account?code=first")!
        browser.sessions[0].callback(callback, nil)
        let firstResult = try await first.value
        XCTAssertEqual(firstResult, callback)
    }

    func testMissingActiveWindowDoesNotCreateBrowserSession() async throws {
        let browser = BrowserSessionFixture()
        let authenticator = try browser.authenticator(hasWindow: false)
        do { _ = try await authenticator.signIn(authorization()); XCTFail("Expected missing window error") }
        catch { XCTAssertTrue(error is WorkspaceCloudError) }
        XCTAssertTrue(browser.sessions.isEmpty)
    }

    private func authorization() throws -> WorkspaceBrowserAuthorization {
        try .init(loginURL: URL(string: "https://example.com/login")!, platform: "ios")
    }

    private func waitForSessions(_ count: Int, in browser: BrowserSessionFixture) async {
        let deadline = Date().addingTimeInterval(2)
        while browser.sessions.count < count && Date() < deadline { await _Concurrency.Task.yield() }
        XCTAssertEqual(browser.sessions.count, count)
    }

    private func drainCallbacks() async {
        for _ in 0..<10 { await _Concurrency.Task.yield() }
    }
}

@MainActor
private final class BrowserSessionFixture {
    var startResult = true
    var onStart: ((ASWebAuthenticationSession.CompletionHandler) -> Void)?
    private(set) var sessions: [FakeBrowserSession] = []

    func authenticator(hasWindow: Bool = true) throws -> WorkspaceBrowserAuthenticator {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        return WorkspaceBrowserAuthenticator(makeSession: { [self] _, _, completion in
            let session = FakeBrowserSession(startResult: startResult, callback: completion, onStart: onStart)
            sessions.append(session)
            return session
        }, findAnchor: { hasWindow ? window : nil })
    }
}

@MainActor
private final class FakeBrowserSession: WorkspaceBrowserSession {
    let callback: ASWebAuthenticationSession.CompletionHandler
    private let startResult: Bool
    private let onStart: ((ASWebAuthenticationSession.CompletionHandler) -> Void)?
    private(set) var cancelCount = 0

    init(startResult: Bool, callback: @escaping ASWebAuthenticationSession.CompletionHandler,
        onStart: ((ASWebAuthenticationSession.CompletionHandler) -> Void)?) {
        self.startResult = startResult
        self.callback = callback
        self.onStart = onStart
    }
    func start() -> Bool { onStart?(callback); return startResult }
    func cancel() { cancelCount += 1 }
}
