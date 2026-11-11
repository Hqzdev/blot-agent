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
        if let page = tab.localPage, let destination = WorkspaceToolDestination(identifier: page) { value.path = [destination] }
        values[tab.id] = value; return value
    }
    func reset(_ tab: BrowserTab?, to destination: WorkspaceToolDestination?) {
        let value = navigation(for: tab)
        value.fileID = nil; value.taskID = nil; value.path = destination.map { [$0] } ?? []
    }
    func retain(_ ids: Set<UUID>) { values = values.filter { ids.contains($0.key) } }
    func clear() { values.removeAll() }
}

enum WorkspaceToolDestination: Hashable {
    case page(WorkspaceRoute), projects, details
    var identifier: String {
        switch self { case .projects: "projects"; case .details: "details"; case .page(let route): "page:" + route.rawValue }
    }
    init?(identifier: String) {
        if identifier == "projects" { self = .projects }
        else if identifier == "details" { self = .details }
        else if identifier.hasPrefix("page:"), let route = WorkspaceRoute(rawValue: String(identifier.dropFirst(5))), !route.isAuthentication { self = .page(route) }
        else { return nil }
    }
    var symbol: String {
        switch self {
        case .projects: "terminal"
        case .details: "person.2"
        case .page(let route):
            switch route {
            case .files, .file: "folder"
            case .running: "checklist"
            case .skills: "shippingbox"
            case .memory: "brain"
            case .schedules: "calendar"
            case .mcp: "puzzlepiece.extension"
            case .devices: "laptopcomputer.and.iphone"
            default: "square.grid.2x2"
            }
        }
    }
    func title(russian: Bool) -> String {
        switch self {
        case .projects: russian ? "Терминал и Git" : "Terminal and Git"
        case .details: russian ? "Об этом чате" : "About this chat"
        case .page(let route):
            switch route {
            case .files, .file: russian ? "Файлы" : "Files"
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
        var values: [Self] = [.page(.files), .projects, .page(.running), .page(.skills), .page(.memory), .page(.schedules), .page(.mcp), .page(.devices), .page(.browserSettings)]
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
                VStack(alignment: .leading, spacing: 6) {
                    Text(ru ? "Инструменты" : "Tools").font(.system(size: 16, weight: .semibold))
                    Text(ru ? "Откройте нужное рядом с разговором" : "Keep what you need beside the conversation")
                        .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                    ForEach(featured, id: \.self) { tool in toolCard(tool) }
                    Button { more.toggle() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2").frame(width: 20).foregroundStyle(WorkspaceStyle.secondary)
                            Text(ru ? "Ещё инструменты" : "More tools")
                            Spacer(minLength: 0)
                            Image(systemName: more ? "chevron.up" : "chevron.down").font(.system(size: 10))
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
                Text(ru ? "Адрес или запрос — в строке сверху. Результаты Google откроются в этой вкладке." : "Enter an address or search above. Google results open in this tab.")
                    .font(.system(size: 12)).foregroundStyle(WorkspaceStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(24).frame(maxWidth: 900, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }.accessibilityIdentifier("workspace.browser.start")
    }
    private func toolCard(_ tool: WorkspaceToolDestination) -> some View {
        Button { select(tool) } label: {
            HStack(spacing: 12) {
                Image(systemName: tool.symbol).frame(width: 20).foregroundStyle(WorkspaceStyle.secondary)
                Text(tool.title(russian: ru)).lineLimit(2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(WorkspaceStyle.secondary)
            }.panelToolCard()
        }.buttonStyle(WorkspaceRowButtonStyle(padding: 0)).accessibilityIdentifier("workspace.tools.\(tool.symbol)")
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
            HStack {
                Button { navigation.path.removeLast() } label: { Label(ru ? "Назад" : "Back", systemImage: "chevron.left") }.buttonStyle(.plain)
                Spacer()
                Text(navigation.path.last?.title(russian: ru) ?? "").font(.headline).lineLimit(1)
                Spacer()
                Button { navigation.path.removeAll() } label: { Image(systemName: "square.grid.2x2") }.buttonStyle(.plain).accessibilityLabel(ru ? "Все инструменты" : "All tools")
            }.padding(14)
            Divider()
            if let destination = navigation.path.last { content(destination) }
        }
        .environment(\.workspacePanelNavigation, navigation)
        .accessibilityIdentifier("workspace.browser.tool-page")
    }
    @ViewBuilder private func content(_ destination: WorkspaceToolDestination) -> some View {
        switch destination {
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
