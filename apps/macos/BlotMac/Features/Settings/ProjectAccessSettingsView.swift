import BlotDesign
import SwiftUI
import AppKit
import BlotAPI

struct ProjectAccessSettingsView: View {
    @State private var projects: [BackendEntity<ProjectValue>] = []
    @State private var busy = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        SettingsGroup(title: "Repositories",
                      detail: "Agents work in separate workspaces of these repositories. Commits and pushes need separate approval.",
                      action: {
                          KButton(title: "Add repository…", icon: "plus", kind: .primary, loading: busy) { chooseFolder() }
                      }) {
            if projects.isEmpty && !busy && !loaded {
                LoadingState(label: "Loading repositories…")
            } else if projects.isEmpty {
                EmptyState(icon: "git-branch", title: "No repositories connected",
                           detail: "Choose a Git repository on this Mac to start tasks in it.")
            }
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                if index > 0 { SettingsDivider() }
                ListRow(title: project.data.name, subtitle: project.data.repositoryPath) {
                    IconTile(icon: "folder")
                } trailing: {
                    StatusBadge(project.data.archived ? "Archived" : "Connected", tone: project.data.archived ? .neutral : .success)
                    KButton(title: "Reconnect…", kind: .ghost, height: 28) { chooseFolder(existing: project) }
                        .disabled(busy)
                        .help("Choose the same folder again to restore access")
                }
                .padding(.horizontal, 4)
            }
            if let error { GroupContent { InlineFeedback(text: error, tone: .error) } }
        }
        .task { await load() }
    }

    private func chooseFolder(existing: BackendEntity<ProjectValue>? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let path = try ProjectBookmarks.shared.remember(url)
            guard existing == nil || existing?.data.repositoryPath == path else {
                throw NSError(domain: "BlotProject", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose the same repository folder."])
            }
            busy = true; error = nil
            Task {
                defer { busy = false }
                do {
                    if existing == nil {
                        _ = try await BackendRuntime.shared.client.command("project.create", payload: ["name": url.lastPathComponent, "repositoryPath": path])
                    } else {
                        if let existing { _ = try await BackendRuntime.shared.client.command("project.access", payload: ["id": existing.id.uuidString]) }
                    }
                    await load()
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func load() async {
        defer { loaded = true }
        do { projects = try await BackendRuntime.shared.client.records("PROJECT", as: ProjectValue.self) }
        catch { self.error = error.localizedDescription }
    }

    nonisolated private struct ProjectValue: Codable, Sendable {
        let name: String
        let repositoryPath: String
        let archived: Bool
    }
}
