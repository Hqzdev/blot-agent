import BlotDomain
import BlotDesign
import SwiftUI

struct PhonePrivacySettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "Data and privacy") {
                PhoneSettingsRow(title: "Credentials", detail: "Sign-in keys and tokens are stored in the system Keychain.", showsChevron: false)
                PhoneSettingsDivider()
                PhoneSettingsRow(title: "Model context", detail: "Replies use agent instructions, conversation context and results of permitted tools.", showsChevron: false)
            }
            PhoneSettingsGroup(title: "Agent permissions") {
                if store.snapshot.agents.isEmpty { PhoneSettingsRow(title: "No agents yet", showsChevron: false) }
                ForEach(Array(store.snapshot.agents.enumerated()), id: \.element.metadata.id) { index, agent in
                    if index > 0 { PhoneSettingsDivider() }
                    Button { store.selectAgent(agent.metadata.id, destination: .editAgent) } label: {
                        PhoneSettingsRow(title: agent.name, value: store.t(agent.accessMode.rawValue))
                    }.buttonStyle(.plain)
                }
            }
            WorkspaceFeedback()
        }
    }
}

struct PhoneMemorySettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var editingID: UUID?
    @State private var deletingID: UUID?
    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            if store.snapshot.memories.isEmpty {
                PhoneSettingsGroup(title: "No memories saved yet", detail: "Choose Remember in a message's actions.") { EmptyView() }
            }
            ForEach(store.snapshot.memories, id: \.metadata.id) { memory in
                PhoneSettingsGroup(title: "") {
                    VStack(alignment: .leading, spacing: 16) {
                        if editingID == memory.metadata.id {
                            TextField(store.t("Memory text"), text: $store.form.memory.content, axis: .vertical).lineLimit(3...10)
                            WorkspaceV3ActionButton(title: "Save", action: .saveMemory)
                            Button(store.t("Cancel")) { editingID = nil }
                        } else {
                            Text(memory.content).font(.subheadline).textSelection(.enabled)
                            HStack {
                                Button(store.t("Edit")) {
                                    editingID = memory.metadata.id; store.selectedRecordID = memory.metadata.id
                                    store.form.memory.content = memory.content
                                }
                                Spacer()
                                if store.mode == .live { Button(store.t("Delete"), role: .destructive) { deletingID = memory.metadata.id } }
                            }.font(.subheadline)
                        }
                    }.padding(16)
                }
            }
            WorkspaceFeedback()
        }
        .confirmationDialog(store.t("Delete"), isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } }), titleVisibility: .visible) {
            Button(store.t("Delete"), role: .destructive) {
                if let id = deletingID { store.deleteMemory(id) }; deletingID = nil
            }
            Button(store.t("Cancel"), role: .cancel) { deletingID = nil }
        }
    }
}

struct PhoneMcpSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    var body: some View {
        @Bindable var store = store
        PhoneSettingsPage {
            PhoneSettingsGroup(title: "MCP servers") {
                if store.snapshot.mcpConnections.isEmpty { PhoneSettingsRow(title: "No connected MCP servers", showsChevron: false) }
                ForEach(Array(store.snapshot.mcpConnections.enumerated()), id: \.element.metadata.id) { index, connection in
                    if index > 0 { PhoneSettingsDivider() }
                    PhoneSettingsRow(title: connection.name, detail: connection.endpoint,
                        value: store.t(connection.state == .connected ? "Connected" : connection.state == .error ? "Reconnect" : "Not connected"), showsChevron: false)
                    ForEach(connection.toolIds, id: \.self) { tool in
                        PhoneSettingsRow(title: tool, symbol: "checkmark.shield", showsChevron: false)
                    }
                }
            }
            PhoneSettingsGroup(title: "Add MCP server") {
                VStack(alignment: .leading, spacing: 18) {
                    WorkspaceField(title: "Server name", text: $store.form.mcp.name)
                    WorkspaceField(title: "Server URL", text: $store.form.mcp.endpoint)
                    PhoneSettingsValueRow(title: "Transport") {
                        Picker(store.t("Transport"), selection: $store.form.mcp.transport) {
                            Text("Streamable HTTP").tag("STREAMABLE_HTTP")
                            Text("stdio").tag("STDIO")
                        }.labelsHidden()
                    }
                    Text(store.t("Transports: stdio on computer · Streamable HTTP")).font(.footnote).foregroundStyle(.secondary)
                    Text(store.t("Secrets belong in protected settings and never in prompts.")).font(.footnote).foregroundStyle(.secondary)
                    WorkspaceV3ActionButton(title: "Add server", action: .addMcp)
                }.padding(16)
            }
            WorkspaceFeedback()
        }
    }
}
