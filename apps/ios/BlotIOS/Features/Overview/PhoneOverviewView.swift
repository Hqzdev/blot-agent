import BlotDesign
import BlotDomain
import SwiftUI

struct PhoneOverviewView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.locale) private var locale

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let content = PhoneOverviewContent(snapshot: store.snapshot, now: context.date)
            PhonePage {
                if !content.attention.isEmpty {
                    taskSection("Needs your attention", tasks: content.attention)
                }
                PhoneSettingsGroup(title: "In progress") {
                    if content.active.isEmpty {
                        PhoneSettingsRow(title: "No tasks in progress", detail: "Start a task in any chat.", showsChevron: false)
                    } else { taskRows(content.active) }
                }
                PhoneSettingsGroup(title: "Upcoming") {
                    if content.upcoming.isEmpty {
                        PhoneSettingsRow(title: "No upcoming runs", showsChevron: false)
                    }
                    ForEach(Array(content.upcoming.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { PhoneSettingsDivider() }
                        Button {
                            store.selectTab(.schedules)
                            store.navigation.scheduleDate = item.date
                        } label: {
                            PhoneSettingsRow(title: store.t(item.schedule.name), symbol: "calendar",
                                             detail: dateText(item.date))
                        }.buttonStyle(.plain)
                    }
                    PhoneSettingsDivider()
                    Button { store.navigate(.createSchedule) } label: {
                        PhoneSettingsRow(title: "New schedule", symbol: "plus")
                    }.buttonStyle(.plain)
                }
                PhoneSettingsGroup(title: "Recent results") {
                    if content.completed.isEmpty && content.files.isEmpty {
                        PhoneSettingsRow(title: "No results yet", detail: "Completed tasks and saved files will appear here.", showsChevron: false)
                    }
                    taskRows(content.completed)
                    ForEach(Array(content.files.enumerated()), id: \.element.metadata.id) { index, file in
                        if index > 0 || !content.completed.isEmpty { PhoneSettingsDivider() }
                        Button { store.selectedRecordID = file.metadata.id; store.navigate(.file) } label: {
                            PhoneSettingsRow(title: file.name, symbol: "doc",
                                             detail: dateText(file.metadata.updatedAt))
                        }.buttonStyle(.plain)
                    }
                    PhoneSettingsDivider()
                    Button { store.navigate(.files) } label: {
                        PhoneSettingsRow(title: "All files", symbol: "folder")
                    }.buttonStyle(.plain)
                }
                WorkspaceFeedback()
            }
            .refreshable { await store.synchronizeAccount() }
        }
    }

    private func taskSection(_ title: String, tasks: [BlotV3.Task]) -> some View {
        PhoneSettingsGroup(title: title) { taskRows(tasks) }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    private func taskRows(_ tasks: [BlotV3.Task]) -> some View {
        ForEach(Array(tasks.enumerated()), id: \.element.metadata.id) { index, task in
            if index > 0 { PhoneSettingsDivider() }
            Button {
                store.openConversation(task.conversationId)
                store.selectedRecordID = task.metadata.id
                store.navigate(.running)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.goal).font(.subheadline).lineLimit(2)
                        WorkspaceTaskStateLabel(state: task.state).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    BlotIcon(.chevronRight, size: 11).foregroundStyle(WorkspaceStyle.secondary)
                }.padding(PhonePageLayout.rowInset).frame(minHeight: 56).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
}
