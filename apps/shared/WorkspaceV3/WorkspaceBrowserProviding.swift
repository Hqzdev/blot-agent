import BlotAppleIntegrations
import BlotWorkspace
import CryptoKit
import Foundation
import Observation
import WebKit

@MainActor
enum WorkspaceBrowserProfile {
    static func identifier(_ directory: URL) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(directory.standardizedFileURL.path.utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    static func erase(_ directory: URL) async {
        await WorkspaceBrowserController.eraseSavedProfiles(directory: directory)
        let data = WKWebsiteDataStore(forIdentifier: identifier(directory))
        await data.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }
}

@MainActor @Observable
final class WorkspaceBrowserState {
    var controller: WorkspaceBrowserController?
    var activeSession: WorkspaceBrowserSessionKey = .workspace

    func selectSession(_ session: WorkspaceBrowserSessionKey) {
        activeSession = session
        controller?.activateSession(session)
    }
}

@MainActor
private final class WorkspaceBrowserDriver: WorkspaceBrowserExecuting {
    private let resolve: @MainActor @Sendable (Bool) throws -> WorkspaceBrowserController?
    init(resolve: @escaping @MainActor @Sendable (Bool) throws -> WorkspaceBrowserController?) { self.resolve = resolve }
    func prepare(_ command: WorkspaceBrowserCommand) async throws -> WorkspaceBrowserBinding {
        guard let browser = try resolve(true) else { throw WorkspaceBrowserError.unavailable }; return try await browser.prepare(command)
    }
    func execute(_ command: WorkspaceBrowserCommand, binding: WorkspaceBrowserBinding) async throws -> WorkspaceBrowserResult {
        guard let browser = try resolve(true) else { throw WorkspaceBrowserError.unavailable }; return try await browser.execute(command, binding: binding)
    }
    func browserProfiles() async -> [WorkspaceBrowserProfileInfo] { (try? resolve(true))?.profiles ?? [] }
    func copyCookies(_ transfer: WorkspaceCardContent.CookieTransfer) async throws -> Int {
        guard let browser = try resolve(true) else { throw WorkspaceBrowserError.unavailable }; return try await browser.copyCookies(transfer)
    }
    func beginManual(session: WorkspaceBrowserSessionKey, tabID: UUID) async throws {
        guard let browser = try resolve(true) else { throw WorkspaceBrowserError.unavailable }; try await browser.beginManual(session: session, tabID: tabID)
    }
    func endManual(session: WorkspaceBrowserSessionKey) async { await (try? resolve(false))?.endManual(session: session) }
    func stop(scope: WorkspaceBrowserScope?) async { (try? resolve(false))?.stop(scope: scope) }
}

@MainActor
protocol WorkspaceBrowserProviding {
    var automaticBrowserAccess: Bool { get }
    var browserSession: WorkspaceBrowserState { get }
    var workspaceBrowser: WorkspaceBrowserController { get }
    func browserService() async throws -> WorkspaceBrowserService
}
extension LocalWorkspaceService: WorkspaceBrowserProviding {
    var workspaceBrowser: WorkspaceBrowserController {
        if let browserController = browserSession.controller { return browserController }
        let profile = WorkspaceBrowserProfile.identifier(browserProfileDirectory)
        let controller = makeBrowser(profile, browserDirectory)
        controller.activateSession(browserSession.activeSession)
        browserSession.controller = controller; return controller
    }
    func browserService() async throws -> WorkspaceBrowserService {
        if let browserAccess { return browserAccess }
        let driver = WorkspaceBrowserDriver { [weak self] create in
            guard let self else { throw WorkspaceBrowserError.unavailable }
            return create ? self.workspaceBrowser : self.browserSession.controller
        }
        let value = WorkspaceBrowserService(repository: repository, identity: try await context(), credentials: mcpCredentials, driver: driver, automaticAccess: automaticBrowserAccess)
        browserAccess = value; return value
    }
    func browserTools() async throws -> WorkspaceBrowserTools {
        let center = appleIntegrations.interactions
        return try await WorkspaceBrowserTools(service: browserService(), repository: repository, identity: context(), files: fileService()) { title, details in
            try await center.confirm(title: title, details: details)
        }
    }
}
