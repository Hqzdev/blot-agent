import BlotAPI
import BlotDesign
import SwiftUI

struct AutomationsView: View {
    @Environment(AppState.self) private var app
    @State private var creating = false
    var body: some View {
        Group {
            if let row = app.workspace.find("AUTOMATION", app.automations.selectedID) {
                PageContent { AutomationDetailView(item: row).id(row.id).transition(.kAppear) }
            } else if app.workspace.loading {
                ContentSkeleton()
            } else {
                EmptyState(icon: "clock",
                           title: app.workspace.rows("AUTOMATION").isEmpty ? "No schedules yet" : "Choose a schedule",
                           detail: "A schedule starts a run on the days and time you choose. It works while Blot and this Mac are running.",
                           actionTitle: "New schedule", actionIcon: "plus") { creating = true }
                    .frame(maxHeight: .infinity)
            }
        }
        .kAnimation(value: app.automations.selectedID)
        .sheet(isPresented: $creating) { AutomationEditorView() }
    }
}

/// Presentation helpers shared by the schedule list and detail.
enum AutomationSchedule {
    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func days(_ row: WorkspaceRow) -> [Int] {
        row.data.items("weekdays").compactMap {
            if case .integer(let day) = $0 { return Int(day) }
            return nil
        }.sorted()
    }

    static func describe(_ row: WorkspaceRow) -> String {
        let days = days(row)
        let label: String
        switch Set(days) {
        case Set(1...7): label = "Every day"
        case Set(1...5): label = "Weekdays"
        case [6, 7]: label = "Weekends"
        default: label = days.compactMap { (1...7).contains($0) ? dayNames[$0 - 1] : nil }.joined(separator: ", ")
        }
        return label + " · " + row.data.text("localTime")
    }
}

extension AppState {
    /// Turns a schedule on or off with the same `automation.save` command the editor uses.
    func setAutomation(_ item: WorkspaceRow, enabled: Bool) {
        guard case .object(var fields) = item.data else { return }
        fields["enabled"] = .bool(enabled)
        let payload = BackendJSON.object(["id": .string(item.id.uuidString), "data": .object(fields)])
        Task {
            do {
                try await workspace.send(
                    "automation.save", payload: payload, row: item, key: "automation.toggle:" + item.id.uuidString)
            } catch {
                toasts.show("Couldn't \(enabled ? "turn on" : "pause") the schedule. \(error.localizedDescription)", tone: .error)
            }
        }
    }
}
