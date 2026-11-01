import BlotDesign
import BlotAPI
import Foundation

extension AppState {
    var projects: [ProjectItem] {
        workspace.rows("PROJECT").filter {
            !$0.data.flag("archived") && !$0.data.text("repositoryPath").isEmpty
        }.map { project in
            ProjectItem(
                id: project.id.uuidString, name: project.data.text("name"),
                tasks:
                    workspace.rows("RUN", projectID: project.id).reversed().map { run in
                        TaskItem(
                            id: run.id.uuidString, title: String(run.data.text("goal").prefix(80)),
                            age: run.data.text("status"),
                            phase: run.data.text("status") == "COMPLETED"
                                ? .done : Self.isRunActive(run) ? .working : .stopped,
                            branch: "", elapsedSeconds: 0,
                            thread: run.id.uuidString == selectedRunID ? transcriptBlocks(run.id) : [])
                    })
        }
    }
    var workProjects: [WorkProject] {
        projects.map { project in
            WorkProject(
                id: project.id, name: project.name,
                runs: project.tasks.map {
                    WorkRun(id: $0.id, title: $0.title, age: $0.age, running: $0.isRunning)
                })
        }
    }
    var currentWorkSession: WorkSession? {
        guard let run = workspace.find("RUN", selectedRunID) else { return nil }
        return WorkSession(
            id: run.id.uuidString, title: String(run.data.text("goal").prefix(80)),
            projectID: run.projectId?.uuidString ?? "",
            status: Self.isRunActive(run)
                ? .running : run.data.text("status") == "PAUSED" ? .paused : .stopped)
    }
    var team: [TeamMember] {
        workspace.rows("AGENT_SESSION", parentID: UUID(uuidString: selectedRunID)).filter {
            $0.parentId?.uuidString == selectedRunID
        }.map {
            TeamMember(
                role: AgentRole.backendRole($0.data.text("role")), name: $0.data.text("role"),
                state: WorkState.persisted($0.data.text("status")), stateLabel: $0.data.text("status"))
        }
    }
    var currentTask: TaskItem? {
        guard product == .code, case .task(let projectID, let taskID) = codeRoute else { return nil }
        return task(projectID: projectID, taskID: taskID)
    }
    func task(projectID: String, taskID: String) -> TaskItem? {
        projects.first { $0.id == projectID }?.tasks.first { $0.id == taskID }
    }
    func transcriptBlocks(_ runID: UUID) -> [ThreadBlock] {
        let conversations = Set(
            workspace.rows("CONVERSATION").filter { $0.data.uuid("runId") == runID }.map(\.id))
        return workspace.rows("MESSAGE").filter { $0.parentId.map(conversations.contains) == true }.map {
            $0.data.text("role") == "user" ? .user($0.data.text("content")) : .agent($0.data.text("content"))
        }
    }
    static func isRunActive(_ run: WorkspaceRow) -> Bool {
        ["PLANNING", "RUNNING"].contains(run.data.text("status"))
    }
}

extension AgentRole {
    /// Title for a backend role string; roles without a portrait are shown humanised («DATA_ENGINEER» → «Data engineer»).
    static func displayName(_ role: String) -> String {
        let known = backendRole(role)
        if known != .blot || role.uppercased() == "BLOT" { return known.title }
        let words = role.replacingOccurrences(of: "_", with: " ").lowercased()
        return words.isEmpty ? "Specialist" : words.prefix(1).uppercased() + words.dropFirst()
    }

    static func backendRole(_ role: String) -> AgentRole {
        switch role {
        case "BACKEND": .backend
        case "FRONTEND": .nativeFrontend
        case "REVIEWER": .reviewer
        case "QA": .qa
        case "SECURITY": .security
        case "INTEGRATOR": .integrator
        case "TECH_LEAD": .techLead
        case "DESIGN_LEAD": .productLead
        default: .blot
        }
    }
}
extension WorkState {
    static func persisted(_ status: String) -> WorkState {
        switch status {
        case "RUNNING": .running
        case "COMPLETED": .done
        case "BLOCKED", "WAITING": .blocked
        default: .idle
        }
    }
}
