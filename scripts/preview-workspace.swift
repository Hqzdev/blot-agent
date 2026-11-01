import AppKit
import SwiftUI

/// An isolated preview process: it never restores credentials or starts the backend.
@main
struct WorkspaceDesignPreview: App {
    @State private var state: AppState

    init() {
        let state = AppState()
        precondition(state.product == .work)
        state.currentUser = AuthUser(email: "design-preview@blot.local", name: "Ярослав")
        state.settings.reduceMotion = true
        let projectID = UUID().uuidString
        state.workChat.registerProject(id: projectID, name: "Запуск Blot")
        state.openWorkChatProject(projectID)
        precondition(state.workChat.selectedProjectID == projectID)
        state.openQuickChat()
        precondition(state.workChat.selectedProjectID == nil && state.workRoute == .home)
        if CommandLine.arguments.contains("--project") { state.openWorkChatProject(projectID) }
        if CommandLine.arguments.contains("--chat") {
            let session = WorkChatSession(title: "План запуска приложения", messages: [
                WorkChatMessage(text: "Помоги составить план запуска приложения.", fromUser: true),
                WorkChatMessage(text: "Начнём с трёх этапов: подготовим основной сценарий, проверим его на реальных задачах и соберём обратную связь.\n\nКакая часть приложения уже готова к тестированию?", fromUser: false)
            ])
            state.workChat.add(session)
            state.openWorkChat(session.id)
        }
        state.theme = CommandLine.arguments.contains("--light") ? .light : .dark
        _state = State(initialValue: state)
    }

    var body: some Scene {
        WindowGroup("Blot · Design Preview") {
            BlotWindowContent(state: state)
        }.defaultSize(width: 1200, height: 780)
    }
}
