import SwiftUI

struct PhoneWorkspaceNavigationStack: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let root = store.rootRoute
        NavigationStack(path: Binding(
            get: { store.rootRoute == root ? store.history : [] },
            set: { path in
                guard store.rootRoute == root else { return }
                store.restoreNavigation(path)
            })) {
            PhoneWorkspacePage(route: root)
                .navigationDestination(for: WorkspaceRoute.self) { PhoneWorkspacePage(route: $0) }
        }
        .id(root)
    }
}

private struct PhoneWorkspacePage: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let unified = PhoneWorkspacePageHeader.isUsed(on: route)
        let floating = unified || PhoneWorkspaceScreen.usesFloatingControls(route) && store.screenState == .normal
        return PhoneWorkspaceScreen(route: route)
            .id(route)
            .modifier(PhoneComposerMenuOverlay())
            .environment(\.phonePageTitle, unified ? PhoneWorkspacePageHeader.title(for: route, store: store) : nil)
            .safeAreaInset(edge: .top, spacing: 0) {
                if unified { PhoneWorkspacePageHeader(route: route) }
            }
            .navigationTitle(floating ? "" : store.t(route.title))
            .toolbar(floating ? .hidden : .visible, for: .navigationBar)
            .navigationBarBackButtonHidden(floating)
            .navigationBarTitleDisplayMode(!unified && [.chats, .agents, .schedules, .settings].contains(route) ? .large : .inline)
            .toolbarBackground(.automatic, for: .navigationBar)
    }
}
