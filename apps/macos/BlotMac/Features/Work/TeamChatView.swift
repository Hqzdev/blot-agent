import BlotDesign
import SwiftUI

struct TeamChatView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if let id = UUID(uuidString: app.selectedRunID) {
            RunWorkspaceView(runID: id).id(id)
        } else {
            EmptyState(icon: "users", title: "Choose a run",
                       detail: "Start a new team run or open an existing one in the sidebar.",
                       actionTitle: "New run", actionIcon: "plus") { app.openNewRun() }
                .frame(maxHeight: .infinity)
        }
    }
}
