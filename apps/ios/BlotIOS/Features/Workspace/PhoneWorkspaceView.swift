import BlotAPI
import BlotDesign
import SwiftUI

struct PhoneWorkspaceView: View {
    let client: BackendClient
    let disconnect: () -> Void
    @State private var model: PhoneWorkspaceModel
    @State private var confirmingDisconnect = false
    @AppStorage(ThemeStore.defaultsKey) private var theme: ThemePreference = .system

    init(client: BackendClient, disconnect: @escaping () -> Void) {
        self.client = client
        self.disconnect = disconnect
        _model = State(initialValue: PhoneWorkspaceModel(client: client))
    }

    var body: some View {
        TabView {
            Tab {
                NavigationStack { chats }
            } label: { BlotLabel("Chats", symbol: "bubble.left.and.bubble.right") }
            Tab {
                NavigationStack { code }
            } label: { BlotLabel("Code", symbol: "terminal") }
            Tab {
                NavigationStack { PhoneApprovalsView(client: client) }
            } label: { BlotLabel("Decisions", symbol: "checkmark.shield") }
            Tab {
                NavigationStack { connection }
            } label: { BlotLabel("Connection", symbol: "network") }
        }
        .toolbarBackground(BlotColor.canvas, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
        .task(id: client.baseURL) { await model.refresh() }
    }

    private var chats: some View {
        @Bindable var model = model
        return List {
            loadStatus
            Section {
                TextField("Conversation title", text: $model.title)
                    .blotFont(.body)
                    .frame(minHeight: BlotLayout.minimumTapTarget)
                    .disabled(model.busy || model.chatPending)
                Button {
                    Task { await model.createChat() }
                } label: {
                    BlotLabel(model.chatPending ? "Retry creating chat" : "Create chat",
                          symbol: model.chatPending ? "arrow.clockwise" : "square.and.pencil")
                }
                .buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                .disabled(!model.canCreateChat)
                if let error = model.chatError { PhoneErrorText(error) }
            } header: { PhoneSectionHeader("New conversation") }
            .phoneRow()
            Section {
                ForEach(model.chats, id: \.id) { row in
                    let title = row.data.text("title")
                    NavigationLink {
                        PhoneChatView(client: client, conversation: row.id, title: title)
                    } label: {
                        WorkspaceLocalizedText(title.isEmpty ? "Untitled conversation" : title)
                            .blotFont(.body)
                            .foregroundStyle(BlotColor.text)
                            .frame(minHeight: BlotLayout.minimumTapTarget, alignment: .leading)
                    }
                }
                if !model.loading && model.loadError == nil && model.chats.isEmpty {
                    BlotEmptyState(symbol: "bubble.left.and.bubble.right", title: "No conversations yet",
                                   message: "Create a chat above to start working with Blot.")
                }
            } header: { PhoneSectionHeader("Conversations") }
            .phoneRow()
        }
        .phoneList()
        .navigationTitle("Chats")
        .refreshable { await model.refresh() }
    }

    private var code: some View {
        @Bindable var model = model
        return List {
            loadStatus
            Section {
                if model.projects.isEmpty {
                    BlotStatusLabel("Add a project in Blot on your Mac to create a run.", status: .info, role: .body)
                } else {
                    Picker("Project", selection: $model.selectedProject) {
                        ForEach(model.projects, id: \.id) { Text($0.data.text("name")).tag(Optional($0.id)) }
                    }
                    .frame(minHeight: BlotLayout.minimumTapTarget)
                    .disabled(model.busy || model.runPending)
                }
                TextField("What should Blot do?", text: $model.goal, axis: .vertical)
                    .blotFont(.body)
                    .lineLimit(3...8)
                    .disabled(model.busy || model.runPending)
                Button {
                    Task { await model.createRun() }
                } label: {
                    BlotLabel(model.runPending ? "Retry creating plan" : "Create plan",
                          symbol: model.runPending ? "arrow.clockwise" : "list.bullet.clipboard")
                }
                .buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                .disabled(!model.canCreateRun)
                if let error = model.runError { PhoneErrorText(error) }
            } header: { PhoneSectionHeader("New run") } footer: {
                Text("Review the plan before the team starts working.")
                    .blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
            }
            .phoneRow()
            Section {
                ForEach(model.runs, id: \.id) { row in
                    NavigationLink { PhoneRunView(client: client, run: row) } label: {
                        VStack(alignment: .leading, spacing: BlotSpace.element) {
                            Text(row.data.text("goal")).blotFont(.body, weight: .medium).foregroundStyle(BlotColor.text)
                                .lineLimit(3)
                            PhoneStatusPill(raw: row.data.text("status"))
                        }
                        .padding(.vertical, 4)
                    }
                }
                if !model.loading && model.loadError == nil && model.runs.isEmpty {
                    BlotEmptyState(symbol: "terminal", title: "No runs yet",
                                   message: "Runs from your Mac appear here. You can also create a plan above.")
                }
            } header: { PhoneSectionHeader("Runs") }
            .phoneRow()
        }
        .phoneList()
        .navigationTitle("Code")
        .refreshable { await model.refresh() }
    }

    @ViewBuilder private var loadStatus: some View {
        if model.loading {
            BlotLoadingState("Loading workspace…").phoneRow()
        }
        if let error = model.loadError {
            BlotErrorState(error) { Task { await model.refresh() } }
                .disabled(model.busy)
                .listRowBackground(Color.clear)
        }
        if model.busy {
            BlotLoadingState("Saving…").phoneRow()
        }
    }

    private var connection: some View {
        Form {
            Section {
                BlotStatusLabel("Connected to your Mac", status: .success, role: .body)
            } footer: {
                Text("Keep Blot open on your Mac to receive updates and respond to decisions.")
                    .blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
            }
            .phoneRow()
            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(ThemePreference.allCases) { option in
                        BlotLabel(option.title, symbol: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minHeight: BlotLayout.minimumTapTarget)
                .accessibilityLabel("Theme")
            } header: { PhoneSectionHeader("Appearance") } footer: {
                Text("System follows your iPhone. Light and Dark apply to Blot on this iPhone only.")
                    .blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
            }
            .phoneRow()
            Section {
                Button(role: .destructive) { confirmingDisconnect = true } label: {
                    BlotLabel("Disconnect…", symbol: "xmark.circle")
                }
                .buttonStyle(PhoneButtonStyle(kind: .destructive, fullWidth: true))
            }
            .phoneRow()
        }
        .phoneList()
        .navigationTitle("Connection")
        .confirmationDialog("Disconnect from your Mac?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive, action: disconnect)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can reconnect to your saved Mac from the connection screen.")
        }
    }
}
