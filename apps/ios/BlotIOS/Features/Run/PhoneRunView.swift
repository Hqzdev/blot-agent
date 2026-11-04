import BlotAPI
import BlotDesign
import SwiftUI

struct PhoneRunView: View {
    let client: BackendClient
    @State var run: BackendEntity<BackendJSON>
    @State private var sessions: [BackendEntity<BackendJSON>] = []
    @State private var tasks: [BackendEntity<BackendJSON>] = []
    @State private var error: String?
    @State private var plan: BackendEntity<BackendJSON>?
    @State private var confirmingStop = false
    @State private var performing = false
    @State private var commandError: String?
    var body: some View {
        let status = run.data.text("status")
        List {
            Section {
                Text(run.data.text("goal")).blotFont(.body).foregroundStyle(BlotColor.text)
                LabeledContent("Status") { PhoneStatusPill(raw: status) }
                if status == "AWAITING_PLAN", plan != nil {
                    Button("Accept plan") { action("run.plan.approve") }.buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                } else if status == "READY_FOR_ACCEPTANCE" {
                    Button("Accept result") { action("run.accept") }.buttonStyle(PhoneButtonStyle(kind: .primary, fullWidth: true))
                } else if ["PAUSED", "INTERRUPTED", "WAITING"].contains(status) {
                    Button { action("run.resume") } label: { BlotLabel("Resume", symbol: "play") }
                        .buttonStyle(PhoneButtonStyle(fullWidth: true))
                } else if status == "RUNNING" {
                    Button { action("run.pause") } label: { BlotLabel("Pause", symbol: "pause") }
                        .buttonStyle(PhoneButtonStyle(fullWidth: true))
                }
                if !["COMPLETED", "CANCELLED", "FAILED"].contains(status) {
                    Button(role: .destructive) { confirmingStop = true } label: { BlotLabel("Stop run…", symbol: "stop") }
                        .buttonStyle(PhoneButtonStyle(kind: .destructive, fullWidth: true))
                }
            } header: { PhoneSectionHeader("Run") }
            .phoneRow()
            .disabled(performing)
            if performing { BlotLoadingState("Updating run…").phoneRow() }
            if let commandError { PhoneErrorText(commandError).phoneRow() }
            if let plan {
                Section {
                    ForEach(Array(plan.data.items("requirements").enumerated()), id: \.offset) { item in
                        Text(item.element.text("content")).blotFont(.body)
                    }
                } header: { PhoneSectionHeader("Requirements") }
                .phoneRow()
                Section {
                    ForEach(Array(plan.data.items("steps").enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: BlotSpace.element) {
                            Text(item.element.text("title")).blotFont(.body, weight: .semibold)
                            ForEach(item.element.strings("criteria"), id: \.self) {
                                Text($0).blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
                            }
                        }
                    }
                } header: { PhoneSectionHeader("Plan") }
                .phoneRow()
            }
            Section {
                ForEach(tasks, id: \.id) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.data.text("title")).blotFont(.body)
                        Spacer(minLength: BlotSpace.s8)
                        PhoneStatusPill(raw: row.data.text("status"))
                    }
                }
            } header: { PhoneSectionHeader("Tasks") }
            .phoneRow()
            Section {
                ForEach(sessions, id: \.id) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(row.data.text("role")).blotFont(.body)
                            Spacer(minLength: BlotSpace.s8)
                            PhoneStatusPill(raw: row.data.text("status"))
                        }
                        if !row.data.text("waitingReason").isEmpty {
                            Text(row.data.text("waitingReason")).blotFont(.caption).foregroundStyle(BlotColor.textSecondary)
                        }
                    }
                }
            } header: { PhoneSectionHeader("Team and Motes") }
            .phoneRow()
            if let error { PhoneErrorText(error).phoneRow() }
        }
        .phoneList()
        .navigationTitle("Code run")
        .refreshable { await refresh() }
        .confirmationDialog("Stop this run?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop run", role: .destructive) { action("run.stop") }
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("The team stops working on it and the run can't be resumed.")
        }
        .task(id: client.baseURL) { while !Task.isCancelled { await refresh(); try? await Task.sleep(for: .seconds(1)) } }
    }
    private func refresh() async {
        do {
            run = try await client.get("v2/records/RUN/\(run.id.uuidString)", as: BackendEntity<BackendJSON>.self)
            tasks = try await client.records("TASK", parentId: run.id, as: BackendJSON.self)
            sessions = try await client.records("AGENT_SESSION", parentId: run.id, as: BackendJSON.self)
            if let planID = UUID(uuidString: run.data.text("planId")) {
                plan = try await client.get("v2/records/PLAN/\(planID.uuidString)", as: BackendEntity<BackendJSON>.self)
            } else { plan = nil }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func action(_ name: String) {
        guard !performing else { return }
        performing = true
        commandError = nil
        Task {
            defer { performing = false }
            do {
                _ = try await client.command(name, payload: ["id": run.id.uuidString], expectedVersion: run.version)
                await refresh()
            } catch {
                commandError = error.localizedDescription
                await refresh()
            }
        }
    }
}
