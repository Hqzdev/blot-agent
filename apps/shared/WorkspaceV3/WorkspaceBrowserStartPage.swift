import BlotAppleIntegrations
import BlotDesign
import BlotWorkspace
import SwiftUI
import Observation

extension EnvironmentValues {
    @Entry var workspacePanelNavigation: WorkspacePanelNavigation? = nil
}

@MainActor @Observable
final class WorkspacePanelNavigation {
    var path: [WorkspaceToolDestination] = []
    var fileID: UUID?
    var taskID: UUID?
    var fileQuery = ""
    var dismissDetail: WorkspacePanelDismissAction?
    func open(_ route: WorkspaceRoute) { path.append(.page(route)) }
}

@MainActor
final class WorkspacePanelNavigationRegistry {
    private var values: [UUID: WorkspacePanelNavigation] = [:]
    private let empty = WorkspacePanelNavigation()
    func navigation(for tab: BrowserTab?) -> WorkspacePanelNavigation {
        guard let tab else { return empty }
        if let value = values[tab.id] { return value }
        let value = WorkspacePanelNavigation()
        if let page = tab.localPage, let destination = WorkspaceToolDestination(identifier: page) {
            value.path = [destination]
            if page.hasPrefix("page:file:") { value.fileID = UUID(uuidString: String(page.dropFirst(10))) }
        }
        values[tab.id] = value; return value
    }
    func reset(_ tab: BrowserTab?, to destination: WorkspaceToolDestination?) {
        let value = navigation(for: tab)
        value.fileID = nil; value.taskID = nil; value.path = destination.map { [$0] } ?? []
        value.fileQuery = ""
    }
    func retain(_ ids: Set<UUID>) { values = values.filter { ids.contains($0.key) } }
    func clear() { values.removeAll() }
}

enum WorkspaceToolDestination: Hashable {
    case page(WorkspaceRoute), projects, details, fileChange(UUID)
    #if os(macOS)
    case changes(WorkspaceChangesSource)
    #endif
    var identifier: String {
        switch self {
        case .fileChange(let id): "file-change:" + id.uuidString
        case .projects: "projects"
        case .details: "details"
        case .page(let route): "page:" + route.rawValue
        #if os(macOS)
        case .changes(let source): source.identifier
        #endif
        }
    }
    init?(identifier: String) {
        #if os(macOS)
        if let source = WorkspaceChangesSource(identifier: identifier) { self = .changes(source); return }
        #endif
        if identifier.hasPrefix("file-change:"), let id = UUID(uuidString: String(identifier.dropFirst(12))) { self = .fileChange(id) }
        else if identifier == "projects" { self = .projects }
        else if identifier == "details" { self = .details }
        else if identifier.hasPrefix("page:file:"), UUID(uuidString: String(identifier.dropFirst(10))) != nil { self = .page(.file) }
        else if identifier.hasPrefix("page:"), let route = WorkspaceRoute(rawValue: String(identifier.dropFirst(5))), !route.isAuthentication { self = .page(route) }
        else { return nil }
    }
    var glyph: BlotGlyph {
        switch self {
        case .fileChange: .document
        #if os(macOS)
        case .changes: .pullRequest
        #endif
        case .projects: .code
        case .details: .people
        case .page(let route):
            switch route {
            case .files, .file: .folder
            case .pages: .bookmark
            case .running: .list
            case .skills: .skill
            case .memory: .memory
            case .schedules: .calendar
            case .mcp: .puzzle
            case .devices: .laptop
            case .browserSettings: .globe
            default: .grid
            }
        }
    }
    func title(russian: Bool) -> String {
        switch self {
        case .fileChange: russian ? "Просмотр файла" : "File preview"
        #if os(macOS)
        case .changes: russian ? "Изменения" : "Changes"
        #endif
        case .projects: russian ? "Терминал и Git" : "Terminal and Git"
        case .details: russian ? "Об этом чате" : "About this chat"
        case .page(let route):
            switch route {
            case .files, .file: russian ? "Файлы" : "Files"
            case .pages: russian ? "Библиотека" : "Library"
            case .running: russian ? "Задачи" : "Tasks"
            case .skills: russian ? "Навыки" : "Skills"
            case .memory: russian ? "Память" : "Memory"
            case .schedules: russian ? "Расписания" : "Schedules"
            case .mcp: "MCP"
            case .devices: russian ? "Устройства" : "Devices"
            case .browserSettings: russian ? "Доступ браузера" : "Browser access"
            case .connections: russian ? "Приложения" : "Apps"
            #if os(macOS)
            case .marketplace: russian ? "Приложения" : "Apps"
            #endif
            default: WorkspaceCopy.text(route.title, language: russian ? "ru" : "en")
            }
        }
    }
    static var tools: [Self] {
        var values: [Self] = [.page(.files), .page(.pages), .projects, .page(.running), .page(.skills), .page(.memory), .page(.schedules), .page(.mcp), .page(.devices), .page(.browserSettings)]
        #if os(macOS)
        values.insert(.page(.marketplace), at: 4)
        values.append(.details)
        #else
        values.insert(.page(.connections), at: 4)
        #endif
        return values
    }
}

/// A blank tab is a local launch surface: no site request or plugin discovery runs here.
struct WorkspaceBrowserStartPage: View {
    let controller: WorkspaceBrowserController
    let select: (WorkspaceToolDestination) -> Void
    @Environment(WorkspaceStore.self) private var store
    @State private var more = false
    private var ru: Bool { store.language == "ru" }
    private var featured: [WorkspaceToolDestination] { Array(WorkspaceToolDestination.tools.prefix(5)) }
    private var sites: [BrowserTab] { Array(controller.sessionTabs.filter { $0.url != nil }.suffix(6)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(ru ? "Инструменты" : "Tools").font(.system(size: 16, weight: .semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(featured, id: \.self) { tool in toolCard(tool) }
                    Button { more.toggle() } label: {
                        HStack(spacing: 12) {
                            BlotIcon(.more).frame(width: 20).foregroundStyle(WorkspaceStyle.secondary)
                            Text(ru ? "Ещё инструменты" : "More tools")
                            Spacer(minLength: 0)
                            BlotIcon(symbol: more ? "chevron.up" : "chevron.down", size: 10)
                        }.panelToolCard()
                    }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityValue(more ? (ru ? "Развёрнуто" : "Expanded") : (ru ? "Свёрнуто" : "Collapsed"))
                    if more { ForEach(Array(WorkspaceToolDestination.tools.dropFirst(5)), id: \.self) { tool in toolCard(tool) } }
                }
                if !sites.isEmpty {
                    Text(ru ? "Открытые сайты" : "Open websites").font(.system(size: 14, weight: .semibold)).padding(.top, 6)
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(sites) { tab in
                                Button {
                                    do { try controller.select(tab.id) } catch { controller.error = error.localizedDescription }
                                } label: {
                                    VStack(spacing: 12) {
                                        Text(String((tab.url?.host ?? "").prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold))
                                            .frame(width: 42, height: 42).background(WorkspaceStyle.surface, in: Circle())
                                        Text(tab.title).font(.system(size: 12)).lineLimit(1)
                                        Text(tab.url?.host ?? "").font(.system(size: 10)).foregroundStyle(WorkspaceStyle.secondary).lineLimit(1)
                                    }.frame(width: 112).padding(.vertical, 10).contentShape(RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(WorkspaceRowButtonStyle(padding: 0))
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }.accessibilityIdentifier("workspace.browser.start")
    }
    private func toolCard(_ tool: WorkspaceToolDestination) -> some View {
        Button { select(tool) } label: {
            HStack(spacing: 12) {
                BlotIcon(tool.glyph).frame(width: 20).foregroundStyle(WorkspaceStyle.secondary)
                Text(tool.title(russian: ru)).lineLimit(2)
                Spacer(minLength: 0)
                BlotIcon(symbol: "chevron.right", size: 9).foregroundStyle(WorkspaceStyle.secondary)
            }.panelToolCard()
        }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityIdentifier("workspace.tools.\(tool.identifier)")
    }
}

private extension View {
    func panelToolCard() -> some View {
        self.font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(WorkspaceStyle.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct WorkspaceBrowserToolPage: View {
    let navigation: WorkspacePanelNavigation
    @Environment(WorkspaceStore.self) private var store
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                HStack {
                    Button { navigation.path.removeLast() } label: {
                        BlotLabel(ru ? "Назад" : "Back", symbol: "chevron.left", size: BlotIconSize.control)
                            .padding(6).blotHitArea()
                    }.buttonStyle(WorkspaceRowButtonStyle(padding: 0))
                    Spacer()
                    Text(navigation.path.last?.title(russian: ru) ?? "").font(.headline).lineLimit(1)
                    Spacer()
                    Button { navigation.path.removeAll() } label: {
                        BlotIcon(.grid, size: BlotIconSize.control).padding(6).blotHitArea()
                    }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityLabel(ru ? "Все инструменты" : "All tools")
                }.padding(14)
                Divider()
            }
            if let destination = navigation.path.last { content(destination) }
        }
        .environment(\.workspacePanelNavigation, navigation)
        .accessibilityIdentifier("workspace.browser.tool-page")
    }
    private var showsHeader: Bool {
        #if os(macOS)
        if case .changes? = navigation.path.last { return false }
        if navigation.path.last == .page(.file), let id = navigation.fileID { return store.documentEdits[id] == nil }
        return true
        #else
        true
        #endif
    }
    @ViewBuilder private func content(_ destination: WorkspaceToolDestination) -> some View {
        switch destination {
        case .fileChange(let id): WorkspaceFileChangePreview(id: id).id(id)
        #if os(macOS)
        case .changes(let source): MacWorkspaceChangesPage(source: source).id(source)
        #endif
        case .projects: ScrollView { WorkspaceNativeProjectsView().padding(18) }
        case .details:
            #if os(macOS)
            MacLiveTeamInspector()
            #endif
        case .page(.files):
            ScrollView { WorkspaceTeamView(route: .files, openFile: { id in navigation.fileID = id; navigation.open(.file) }).padding(18) }
        case .page(.file): WorkspaceLocalFileView(artifactID: navigation.fileID)
        case .page(.running): ScrollView { WorkspaceTaskExecutionView(taskID: navigation.taskID).padding(18) }
        default:
            if case .page(let route) = destination { WorkspacePage(route: route) }
        }
    }
}
