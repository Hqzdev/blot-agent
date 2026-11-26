import BlotDesign
import BlotWorkspace
import SwiftUI

struct WorkspacePluginPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let endpoint: String
    static let all: [Self] = [
        .init(id: "notion", name: "Notion", endpoint: "https://mcp.notion.com/mcp"),
        .init(id: "github", name: "GitHub", endpoint: "https://api.githubcopilot.com/mcp/"),
        .init(id: "airtable", name: "Airtable", endpoint: "https://mcp.airtable.com/mcp"),
        .init(id: "asana", name: "Asana", endpoint: "https://mcp.asana.com/v2/mcp"),
        .init(id: "granola", name: "Granola", endpoint: "https://mcp.granola.ai/mcp")
    ]
    static func find(_ id: String) -> Self? { all.first { $0.id == id } }
}

struct WorkspacePluginConnectView: View {
    let preset: WorkspacePluginPreset
    @Environment(WorkspaceStore.self) private var store
    @State private var entries: [MCPAccess] = []
    @State private var editor = false
    @State private var selected: MCPAccess?
    @State private var failure: String?
    private var ru: Bool { store.language == "ru" }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            BlotLabel(preset.name, symbol: "puzzlepiece.extension").font(.title2)
            Text(ru ? "Официальный MCP-сервер сервиса. Войдите через OAuth или используйте поддерживаемый сервисом токен, затем выберите инструменты." : "The service’s official MCP server. Sign in with OAuth or use a token supported by the service, then choose tools.")
                .foregroundStyle(.secondary)
            ForEach(entries) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.name)
                        Text(entry.enabled ? (ru ? "Подключено на этом устройстве" : "Connected on this device") : (ru ? "Нужно настроить доступ" : "Review access"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(ru ? "Управлять" : "Manage") { selected = entry; editor = true }
                }
            }
            Button(ru ? "Подключить аккаунт" : "Connect account") { selected = nil; editor = true }
                .buttonStyle(WorkspaceButtonStyle()).disabled(store.mcpCommands == nil)
            if let failure { Text(failure).foregroundStyle(.red) }
        }
        .padding(24)
        .task { await reload() }
        .workspacePanelSheet(isPresented: $editor, onDismiss: { _Concurrency.Task { await reload(); try? await store.refreshMCP() } }) {
            WorkspaceMCPEditor(initial: selected, russian: ru, commands: store.mcpCommands, preset: preset)
        }
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 320)
        #endif
    }
    private func reload() async {
        do { entries = try await store.mcpCommands?.mcpService().access().filter { $0.pluginID == preset.id || $0.pluginID == nil && $0.name == preset.name } ?? []; failure = nil }
        catch { failure = WorkspaceFailureCopy.message(error) }
    }
}
