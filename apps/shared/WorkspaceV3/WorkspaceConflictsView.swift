import BlotDesign
import BlotDomain
import SwiftUI

struct WorkspaceConflictsView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private var groups: [[BlotV3.ConflictingRevision]] {
        Dictionary(grouping: store.unresolvedConflicts, by: { $0.recordKind + $0.recordId.uuidString })
            .sorted { $0.key < $1.key }.map { $0.value.sorted { $0.metadata.id.uuidString < $1.metadata.id.uuidString } }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(store.t("Choose the version to use. All versions remain in history."))
                        .foregroundStyle(WorkspaceStyle.secondary)
                    ForEach(groups, id: \.first?.recordId) { versions in
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(versions, id: \.metadata.id) { version in
                                WorkspaceCard {
                                    Text(details(version)).textSelection(.enabled)
                                    Text(version.metadata.createdAt, format: .dateTime.year().month().day().hour().minute())
                                        .font(.caption).foregroundStyle(WorkspaceStyle.secondary)
                                    Button(store.t("Use this version")) {
                                        _Concurrency.Task {
                                            _ = await store.resolveConflict(version.metadata.id, displayedIDs: Set(versions.map(\.metadata.id)))
                                        }
                                    }.buttonStyle(WorkspaceButtonStyle(.secondary)).disabled(store.busy)
                                }
                            }
                        }
                    }
                    if groups.isEmpty { Text(store.t("All changes are resolved")) }
                    WorkspaceFeedback()
                }.padding(24)
            }
            .navigationTitle(store.t("Conflicting changes"))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("Done")) { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 440)
        #endif
    }
    private func details(_ version: BlotV3.ConflictingRevision) -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(version.payloadJSON.utf8)
        if version.recordKind == "AgentProfile", let agent = try? decoder.decode(BlotV3.AgentProfile.self, from: data) {
            return agent.name + "\n" + agent.modelId + "\n\n" + agent.instructions
        }
        if let schedule = try? decoder.decode(BlotV3.Automation.self, from: data) {
            return schedule.name + "\n" + schedule.localTime + " · " + schedule.timezone + "\n\n" + schedule.goal
        }
        return store.t("This version cannot be displayed")
    }
}
