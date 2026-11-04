import BlotDesign
import SwiftUI

@main
struct BlotIOSApp: App {
    @State private var workspace = WorkspaceBootstrap.makeStore()
    init() { BlotIconAppearance.configureNavigation() }
    var body: some Scene {
        WindowGroup { WorkspaceRootView(store: workspace) }
    }
}
