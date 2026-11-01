import BlotDesign
import SwiftUI

/// Native toolbar controls receive the system's shared Liquid Glass treatment.
struct ShellToolbar: ToolbarContent {
    @Environment(AppState.self) private var app

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            if app.showingSettings || app.profileVisible || app.activeTool != nil {
                Button { app.openQuickChat() } label: { Label("На главную", systemImage: "house") }
                    .help("На главную")
            }
            Button { app.navigateHistory(-1) } label: { Label("Назад", systemImage: "chevron.left") }
                .disabled(!app.shell.history.canGoBack).help("Назад · ⌘[")
            Button { app.navigateHistory(1) } label: { Label("Вперёд", systemImage: "chevron.right") }
                .disabled(!app.shell.history.canGoForward).help("Вперёд · ⌘]")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if app.runControlsAvailable {
                Button { app.pauseOrResumeRun() } label: {
                    Label(app.currentRunPaused ? "Продолжить" : "Пауза",
                          systemImage: app.currentRunPaused ? "play" : "pause")
                }.disabled(!app.canPauseOrResumeRun)
                Button { app.confirmingStopRun = true } label: { Label("Остановить", systemImage: "stop") }
                    .disabled(!app.canStopRun)
            }
            if let conversation = app.currentConversation { ConversationToolbarMenu(item: conversation) }
            if app.shellSupportsProjectPanel {
                Button { app.toggleShellPanel() } label: { Label("Панель проекта", systemImage: "sidebar.right") }
                    .help("Панель проекта · ⌥⌘0")
            }
        }
    }
}
