import BlotDesign
import Foundation
import Observation

struct ShellDestination: Hashable {
    var tool: WorkspaceTool?
    var profile: Bool
    var product: Product
    var code: CodeRoute
    var work: WorkRoute
    var team: TeamRoute
    var runID: String
    var settings: Bool
    var settingsSection: SettingsSection
    var homeProjectID: String
    var workProjectID: String?
    var runProjectID: String
}

@Observable
final class ShellHistory {
    private(set) var entries: [ShellDestination] = []
    private(set) var index = -1
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index + 1 < entries.count }
    func record(_ destination: ShellDestination) {
        guard index < 0 || entries[index] != destination else { return }
        entries = Array(entries.prefix(index + 1))
        entries.append(destination)
        index = entries.count - 1
    }
    func move(_ offset: Int) -> ShellDestination? {
        let next = index + offset
        guard entries.indices.contains(next) else { return nil }
        index = next
        return entries[index]
    }
    func clear() { entries = []; index = -1 }
}

struct ProjectSource: Identifiable, Equatable {
    let id: String
    let name: String
    let path: String
    var url: URL?
}

@Observable
final class ShellState {
    var lastCodeChat: CodeRoute = .home
    var lastWorkChat: WorkRoute = .home
    var sidebarWidth: Double = K.projectSidebarMin
    var rightVisible = true
    var homePanelVisible = false
    var previewSource: ProjectSource?
    var expandedSources = false
    private(set) var pins: Set<String> = []
    private(set) var archived: Set<String> = []
    private(set) var unread: Set<String> = []
    var pinsExpanded = true
    var archiveExpanded = false
    var attachedSources: [String: [ProjectSource]] = [:]
    let history = ShellHistory()
    func clearAccount() {
        lastCodeChat = .home; lastWorkChat = .home
        previewSource = nil; attachedSources = [:]
        pins = []; archived = []; unread = []
        history.clear()
    }
    func togglePin(_ id: String) {
        guard !archived.contains(id) else { return }
        if pins.contains(id) { pins.remove(id) } else { pins.insert(id); pinsExpanded = true }
    }
    func archive(_ id: String) {
        pins.remove(id)
        archived.insert(id)
    }
    func restore(_ id: String) { archived.remove(id) }
    func markUnread(_ id: String) { unread.insert(id) }
    func markRead(_ id: String) { unread.remove(id) }
    func addSources(_ urls: [URL], projectID: String) {
        var sources = attachedSources[projectID] ?? []
        for url in urls where !sources.contains(where: { $0.url == url }) {
            sources.append(ProjectSource(id: url.absoluteString, name: url.lastPathComponent, path: url.path, url: url))
        }
        attachedSources[projectID] = sources
    }
}
