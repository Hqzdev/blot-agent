import BlotDesign
import SwiftUI

@main
struct BlotMacApp: App {
    @State private var workspace = WorkspaceBootstrap.makeStore()
    @FocusedValue(\.teamSceneActions) private var teamActions
    init() {
        #if DEBUG
        if MacKeychainVerification.requested { _Concurrency.Task { await MacKeychainVerification.run() } }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if MacKeychainVerification.requested { ProgressView() }
            else { WorkspaceRootView(store: workspace) }
            #else
            WorkspaceRootView(store: workspace)
            #endif
        }
        .defaultSize(width: 1280, height: 820)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(workspace.t(teamActions == nil ? "New chat" : "Create agent")) {
                    if let teamActions { teamActions.createAgent() }
                    else { workspace.navigate(.home) }
                }.keyboardShortcut("n")
            }
            CommandGroup(replacing: .appSettings) {
                Button(workspace.t("Settings")) {
                    if let teamActions { teamActions.settings() }
                    else { workspace.navigate(.settings) }
                }.keyboardShortcut(",")
            }
            CommandMenu(workspace.t("Go")) {
                Button(workspace.t("Search")) {
                    if let teamActions { teamActions.search() }
                    else { workspace.navigate(.search) }
                }.keyboardShortcut("k").disabled(teamActions?.canSearch == false)
                Button(workspace.t("Back")) {
                    if let teamActions { teamActions.back() } else { workspace.back() }
                }.keyboardShortcut("[")
                #if DEBUG
                Button(workspace.t("Screen catalog")) { workspace.catalogVisible = true }
                #endif
            }
        }
    }
}
