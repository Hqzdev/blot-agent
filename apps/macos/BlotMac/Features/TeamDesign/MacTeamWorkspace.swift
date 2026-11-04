import BlotDesign
import SwiftUI

struct MacTeamWorkspace: View {
    @State private var presentation = MacTeamPresentation()
    @Environment(WorkspaceStore.self) private var workspace

    var body: some View {
        @Bindable var presentation = presentation
        ZStack {
            if presentation.settingsVisible {
                MacTeamSettings()
                    .transition(.opacity)
            } else {
                workspaceContent.transition(.opacity)
            }
        }
        .kAnimation(KMotion.panel, value: presentation.settingsVisible)
        .kAnimation(KMotion.sidebar, value: presentation.sidebarVisible)
        .kAnimation(KMotion.sidebar, value: presentation.inspectorVisible && presentation.isConversation)
        .teamControls()
        .environment(presentation)
        .toolbar(removing: .title)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .focusedSceneValue(\.teamSceneActions, sceneActions)
        .frame(minWidth: 1100, minHeight: 700)
        .font(.system(size: 13))
        .background(WorkspaceStyle.canvas)
        .overlay(alignment: .topLeading) {
            GeometryReader { _ in
                MacTeamNativeWindowButtons().frame(width: 60, height: 16)
                    .padding(.leading, 24).padding(.top, 24)
            }.ignoresSafeArea(.container, edges: .top)
        }
        .sheet(item: $presentation.sheet) { sheet in
            MacTeamSheetContent(sheet: sheet).environment(presentation)
        }
        .task {
            while !Task.isCancelled {
                presentation.demo.runDueRoutines()
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let error = presentation.demo.persistenceError {
                BlotLabel(error, symbol: "exclamationmark.circle", size: BlotIconSize.inline).font(.system(size: 11))
                    .padding(10).frame(maxWidth: .infinity).background(WorkspaceStyle.surface)
            }
        }
        .onChange(of: workspace.settingsRoute, initial: true) { _, route in
            if route != nil {
                presentation.showSettings()
                workspace.settingsRoute = nil
            }
        }
        .onChange(of: workspace.route) { _, route in
            if route == .home { presentation.sheet = .newAgent }
        }
    }

    private var sceneActions: MacTeamSceneActions {
        MacTeamSceneActions(
            createAgent: {
                presentation.closeSettings()
                presentation.sheet = .newAgent
            },
            settings: { presentation.showSettings() },
            back: {
                if presentation.settingsVisible { presentation.closeSettings() }
                else { workspace.back() }
            },
            search: { presentation.settingsSearchFocusRequest += 1 },
            canSearch: presentation.settingsVisible
        )
    }

    private var workspaceContent: some View {
        HStack(spacing: 0) {
            if presentation.sidebarVisible {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 64).accessibilityHidden(true)
                        .contentShape(Rectangle())
                        .gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
                    MacTeamSidebar()
                }
                    .frame(width: 252)
                    .frame(maxHeight: .infinity)
                    .background(MacTeamStyle.sidebar)
                    .transition(.kPanel(.leading))
            }
            ZStack {
                Group {
                    switch presentation.selection {
                    case .agent, .group: MacTeamConversation(initialMessages: presentation.messages)
                    case .library(.marketplace): MacTeamMarketplace()
                    case .library(let destination): MacTeamLibrary(destination: destination)
                    }
                }.id(presentation.selection).transition(.opacity)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .kAnimation(KMotion.panel, value: presentation.selection)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if presentation.isConversation {
                        MacTeamHeader(leadingInset: presentation.sidebarVisible ? 18 : 108)
                            .zIndex(1)
                    }
                }
                .overlay(alignment: .top) {
                    if !presentation.isConversation {
                        MacTeamHeader(leadingInset: presentation.sidebarVisible ? 18 : 108)
                    }
                }
            if presentation.inspectorVisible && presentation.isConversation {
                MacTeamInspector().frame(width: 306)
                    .padding(.top, 6).background(MacTeamStyle.sidebar)
                    .transition(.kPanel(.trailing))
            }
        }
    }

}

struct MacTeamSheetContent: View {
    let sheet: MacTeamSheet
    @AppStorage("blot.v3.reduceMotion") private var reduceMotion = false
    var body: some View {
        Group {
            switch sheet {
            case .newAgent: MacTeamAgentEditor(isNew: true)
            case .editAgent: MacTeamAgentEditor(isNew: false)
            case .agentProfile(let id): MacTeamAgentEditor(isNew: false, agentID: id)
            case .group(let id): MacTeamGroupEditor(groupID: id)
            case .addPlugin: MacTeamPluginPicker()
            case .plugin(let plugin): MacTeamPluginConnection(plugin: plugin)
            case .template(let id): MacTeamTemplateDetail(templateID: id)
            case .routine(let id): MacTeamRoutineEditor(routineID: id)
            case .email: MacTeamEmailReview()
            case .transactions: MacTeamTransactionReview()
            case .skill: MacTeamItemEditor(kind: .skills)
            case .memory: MacTeamItemEditor(kind: .memory)
            case .attachment: MacTeamAttachmentPicker()
            case .document: MacTeamDocumentEditor()
            case .billing: MacTeamBillingPanel()
            }
        }.background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink).teamControls()
            .kMotionRoot(reduceMotion: reduceMotion)
    }
}
