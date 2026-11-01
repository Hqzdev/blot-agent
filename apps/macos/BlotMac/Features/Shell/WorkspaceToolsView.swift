import BlotDesign
import SwiftUI

struct WorkspaceToolsView: View {
    let tool: WorkspaceTool
    var body: some View {
        switch tool {
        case .projects: WorkspaceProjectsView(reviewing: false)
        case .images: ImageLibraryView()
        case .sites: SitesLibraryView()
        case .maps: WorkspaceMapsView()
        case .gpts: AssistantsLibraryView()
        case .codeReview: WorkspaceProjectsView(reviewing: true)
        case .security: WorkspaceSecurityView()
        }
    }
}

private struct WorkspaceProjectsView: View {
    @Environment(AppState.self) private var app
    let reviewing: Bool
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: KSpace.xl) {
                PageHeader(title: reviewing ? "Code Review" : "Projects",
                           subtitle: reviewing ? "Review changes from your project conversations." : "Your projects and their tasks.") {
                    if !reviewing {
                        KButton(title: "Add repository…", icon: "plus") { app.openProfileSettings(.git) }
                    }
                }
                ForEach(app.projects) { project in
                    let tasks = project.tasks.filter { !reviewing || !$0.changedFiles.isEmpty }
                    if !reviewing || !tasks.isEmpty {
                        SettingsGroup(title: project.name, detail: "\(tasks.count) \(tasks.count == 1 ? "task" : "tasks")", action: {
                            if !reviewing {
                                KButton(title: "New task", icon: "plus", kind: .ghost, height: 28) {
                                    app.newTask.projectID = project.id
                                    app.openHome()
                                }
                            }
                        }) {
                            if tasks.isEmpty { SettingsRow(title: "No tasks yet") }
                            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                                if index > 0 { SettingsDivider() }
                                ListRow(title: task.title,
                                        subtitle: reviewing ? "\(task.changedFiles.count) files changed" : nil,
                                        action: {
                                            app.openTask(projectID: project.id, taskID: task.id)
                                            if reviewing { app.openReview(projectID: project.id, task: task) }
                                        }) {
                                    IconTile(icon: "message-square")
                                } trailing: {
                                    StatusBadge(status: task.age)
                                    KIcon("chevron-right", size: 12, color: K.text3)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                    }
                }
                if app.projects.isEmpty || (reviewing && app.projects.allSatisfy { $0.tasks.allSatisfy { $0.changedFiles.isEmpty } }) {
                    EmptyState(icon: reviewing ? "git-pull-request" : "folder",
                               title: reviewing ? "No changes to review" : "No projects",
                               detail: reviewing ? "Changes from project tasks will appear here." : "Connect a Git repository to see its tasks here.",
                               actionTitle: reviewing ? nil : "Add repository…", actionIcon: "plus") {
                        app.openProfileSettings(.git)
                    }
                }
            }
        }
    }
}

private extension TaskItem {
    var changedFiles: [ChangedFile] {
        thread.flatMap { block in
            if case let .changes(files) = block { return files }
            return []
        }
    }
}

private struct WorkspaceSecurityView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        PageContent {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Security", subtitle: "Workspace permissions and command approvals.")
                PermissionsSettingsView(settings: app.settings)
            }
        }
    }
}
