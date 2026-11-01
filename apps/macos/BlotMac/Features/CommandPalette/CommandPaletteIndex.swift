import BlotDesign
import Foundation

enum PaletteAction: Hashable {
    case task(projectID: String, taskID: String)
    case file(projectID: String, taskID: String, path: String)
    case newTask(String), settings, automations, skills, graph
}

struct PaletteEntry: Identifiable {
    let id: String
    let group: String
    let title: String
    let detail: String
    let icon: String
    let action: PaletteAction
}

/// Поиск использует загруженные серверные записи и не сканирует файловую систему.
enum CommandPaletteIndex {
    static func entries(projects: [ProjectItem], query: String) -> [PaletteEntry] {
        var tasks: [PaletteEntry] = []
        var files: [PaletteEntry] = []
        var paths: Set<String> = []
        for project in projects {
            for task in project.tasks {
                tasks.append(PaletteEntry(id: "task:\(project.id):\(task.id)", group: "Tasks", title: task.title,
                    detail: "\(project.name) · \(BackendStatus(task.age).label.lowercased())", icon: "bubble.left",
                    action: .task(projectID: project.id, taskID: task.id)))
                let taskPaths = task.thread.flatMap { block -> [String] in
                    switch block {
                    case .changes(let changed): return changed.map(\.path)
                    case .steps(let steps): return steps.filter { $0.verb == "Read" && $0.target.contains("/") }.map(\.target)
                    default: return []
                    }
                }
                for path in taskPaths where paths.insert(project.id + ":" + path).inserted {
                    files.append(PaletteEntry(id: "file:\(project.id):\(path)", group: "Files", title: path,
                        detail: project.name, icon: "doc.text", action: .file(projectID: project.id, taskID: task.id, path: path)))
                }
            }
        }
        let actions = [
            PaletteEntry(id: "action:new", group: "Actions", title: query.isEmpty ? "New task" : "New task about “\(query)”",
                detail: "⌘N", icon: "square.and.pencil", action: .newTask(query)),
            PaletteEntry(id: "action:settings", group: "Actions", title: "Settings", detail: "⌘,", icon: "gearshape", action: .settings),
            PaletteEntry(id: "action:automations", group: "Actions", title: "Open Automations", detail: "", icon: "clock", action: .automations),
            PaletteEntry(id: "action:skills", group: "Actions", title: "Open Skills", detail: "", icon: "puzzlepiece.extension", action: .skills),
            PaletteEntry(id: "action:graph", group: "Actions", title: "Motes graph", detail: "⌘3", icon: "person.2", action: .graph)
        ]
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return (tasks + files + actions).filter {
            search.isEmpty || $0.id == "action:new" || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(search)
        }
    }
}
