import BlotAPI
import BlotDesign
import SwiftUI

struct AutomationEditorView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: WorkspaceRow?
    @State private var name: String
    @State private var goal: String
    @State private var project: String
    @State private var timezone: String
    @State private var time: String
    @State private var weekdays: Set<Int>
    @State private var budget: String
    @State private var enabled: Bool
    @State private var error: String?
    private var key: String { "automation.editor:" + (item?.id.uuidString ?? "new") }
    init(
        item: WorkspaceRow? = nil, initialTitle: String = "", initialInstructions: String = "",
        initialProject: String = ""
    ) {
        self.item = item
        _name = State(initialValue: item?.data.text("name") ?? initialTitle)
        _goal = State(initialValue: item?.data.text("goal") ?? initialInstructions)
        _project = State(initialValue: item?.projectId?.uuidString ?? initialProject)
        _timezone = State(initialValue: item?.data.text("timezone") ?? TimeZone.current.identifier)
        _time = State(initialValue: item?.data.text("localTime") ?? "09:00")
        _weekdays = State(
            initialValue: item.map {
                Set(
                    $0.data.items("weekdays").compactMap {
                        if case .integer(let day) = $0 { return Int(day) }
                        return nil
                    })
            } ?? Set(1...5))
        _budget = State(initialValue: item.map { String($0.data.integer("tokenBudget")) } ?? "100000")
        _enabled = State(initialValue: item?.data.flag("enabled") ?? true)
    }
    var body: some View {
        let saving = app.workspace.commands.active.contains(key)
        let retrying = app.workspace.commands.pending[key] != nil && !saving
        KSheet(item == nil ? "New schedule" : "Edit schedule",
               subtitle: "Blot starts a run on these days. It works while the app and this Mac are running.", width: 640) {
            VStack(alignment: .leading, spacing: KSpace.lg) {
                HStack(alignment: .top, spacing: KSpace.md) {
                    KTextField("Name", text: $name, placeholder: "Triage new issues", required: true, autofocus: item == nil)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project").font(KFont.caption(.medium)).foregroundStyle(K.text2)
                        ChoiceMenu(selection: $project, options: app.projects.map { ChoiceOption(id: $0.id, title: $0.name) },
                                   placeholder: "Choose project", accessibilityTitle: "Project")
                            .disabled(item != nil)
                            .help(item != nil ? "A schedule stays in its project" : "")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Days").font(KFont.caption(.medium)).foregroundStyle(K.text2)
                    HStack(spacing: 6) {
                        ForEach(Array(AutomationSchedule.dayNames.enumerated()), id: \.offset) { day in
                            KToggleChip(title: day.element, isOn: Binding(
                                get: { weekdays.contains(day.offset + 1) },
                                set: { if $0 { weekdays.insert(day.offset + 1) } else { weekdays.remove(day.offset + 1) } }))
                        }
                    }
                    if weekdays.isEmpty { InlineFeedback(text: "Choose at least one day.", tone: .error) }
                }
                HStack(alignment: .top, spacing: KSpace.md) {
                    KTextField("Time", text: $time, placeholder: "09:00", mono: true,
                               error: timeValid || time.isEmpty ? nil : "Use 24-hour HH:mm.").frame(width: 120)
                    KTextField("Time zone", text: $timezone, placeholder: "Europe/Moscow", mono: true,
                               error: TimeZone(identifier: timezone) == nil && !timezone.isEmpty ? "Unknown time zone." : nil)
                    KTextField("Token budget per run", text: $budget, mono: true,
                               error: (Int64(budget) ?? 0) >= 8192 || budget.isEmpty ? nil : "At least 8,192.").frame(width: 180)
                }
                KTextArea("Instructions", text: $goal, placeholder: "What should Blot do on every run?", minHeight: 150, maxHeight: 240)
                HStack(spacing: KSpace.md) {
                    KToggle(isOn: $enabled).accessibilityLabel("Schedule enabled")
                    Text("Run on schedule").font(KFont.ui(13)).foregroundStyle(K.text)
                    Spacer()
                }
            }
            .disabled(app.workspace.commands.pending[key] != nil)
            if retrying {
                InlineFeedback(text: "The server has not confirmed the last save. Send it again unchanged.", tone: .warning)
            }
            if let error { InlineFeedback(text: error, tone: .error) }
        } footer: {
            KButton(title: "Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            KButton(title: retrying ? "Send save again" : "Save", kind: .primary, loading: saving) { save() }
                .disabled(!valid)
                .keyboardShortcut(.defaultAction)
        }
        .onAppear { if project.isEmpty { project = app.projects.first?.id ?? "" } }
    }
    private var timeValid: Bool {
        time.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && UUID(uuidString: project) != nil && !weekdays.isEmpty && (Int64(budget) ?? 0) >= 8192
            && TimeZone(identifier: timezone) != nil && timeValid
    }
    private func save() {
        let data = BackendJSON.object([
            "name": .string(name), "goal": .string(goal), "timezone": .string(timezone),
            "localTime": .string(time), "weekdays": .array(weekdays.sorted().map { .integer(Int64($0)) }),
            "enabled": .bool(enabled), "tokenBudget": .integer(Int64(budget) ?? 0),
        ])
        let payload = BackendJSON.object([
            "id": item.map { .string($0.id.uuidString) } ?? .null, "data": data,
        ])
        Task {
            do {
                let receipt = try await app.workspace.send(
                    "automation.save", payload: payload, row: item, projectID: UUID(uuidString: project),
                    key: key)
                app.automations.selectedID = receipt.operationId
                app.toasts.show(item == nil ? "Schedule created" : "Schedule saved")
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
