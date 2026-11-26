import BlotWorkspace
import Foundation
import WebKit

extension WorkspaceBrowserController {
    public func createProfile(name: String) throws {
        guard dataStore.isPersistent, profiles.count < 16, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw WorkspaceBrowserError.denied }
        let profile = WorkspaceBrowserProfileInfo(id: UUID(), name: String(name.prefix(80)))
        profiles.append(profile)
        do { try selectProfile(profile.id) } catch { profiles.removeAll { $0.id == profile.id }; throw error }
    }
    public func selectProfile(_ id: UUID) throws {
        guard profiles.contains(where: { $0.id == id }), sessionTabs.allSatisfy({ !$0.unsaved && !$0.loading }),
              !manualSessions.contains(activeSession) else { throw WorkspaceBrowserError.denied }
        for tab in sessionTabs {
            detachAgent(from: tab)
            pages.removeValue(forKey: tab.id)?.detach(); tab.isLive = false; tab.documentID = UUID()
        }
        sessionProfiles[activeSession] = id
        saveTabs()
        if let selectedID { try select(selectedID) }
    }
    public var selectedProfileID: UUID { sessionProfiles[activeSession] ?? legacyProfileID }
    func store(for session: WorkspaceBrowserSessionKey) -> WKWebsiteDataStore {
        guard let id = sessionProfiles[session], id != legacyProfileID else { return dataStore }
        return WKWebsiteDataStore(forIdentifier: id)
    }
    public func browserProfiles() async -> [WorkspaceBrowserProfileInfo] { profiles }
    public func copyCookies(_ transfer: WorkspaceCardContent.CookieTransfer) async throws -> Int {
        guard dataStore.isPersistent, profiles.contains(where: { $0.id == transfer.sourceProfileID }), profiles.contains(where: { $0.id == transfer.destinationProfileID }),
              transfer.sourceProfileID != transfer.destinationProfileID, !transfer.domains.isEmpty else { throw WorkspaceBrowserError.denied }
        let domains = Set(transfer.domains.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) })
        guard domains.count <= 32, domains.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains(":") && !$0.contains("*") }) else { throw WorkspaceBrowserError.denied }
        let source = transfer.sourceProfileID == legacyProfileID ? dataStore : WKWebsiteDataStore(forIdentifier: transfer.sourceProfileID)
        let destination = transfer.destinationProfileID == legacyProfileID ? dataStore : WKWebsiteDataStore(forIdentifier: transfer.destinationProfileID)
        let cookies = await source.httpCookieStore.allCookies().filter {
            domains.contains($0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))) && ($0.expiresDate.map { $0 > Date() } ?? true)
        }
        guard cookies.count <= 256 else { throw WorkspaceBrowserError.denied }
        for cookie in cookies { try _Concurrency.Task.checkCancellation(); await destination.httpCookieStore.setCookie(cookie) }
        return cookies.count
    }
}
