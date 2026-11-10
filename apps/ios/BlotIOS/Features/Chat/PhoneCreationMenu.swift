import BlotDesign
import SwiftUI

struct PhoneCreationMenu: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let createAgent: () -> Void
    let createGroup: () -> Void

    var body: some View {
        PhonePage {
            PhoneSettingsGroup(title: "") {
                Button(action: createAgent) {
                    PhoneSettingsRow(title: "Create agent", symbol: "person.badge.plus",
                                     detail: "A specialist for your tasks.")
                }.buttonStyle(.plain).accessibilityIdentifier("workspace.create.agent")
                PhoneSettingsDivider()
                Button(action: createGroup) {
                    PhoneSettingsRow(title: "Create group", symbol: "person.2",
                                     detail: "Bring agents together for a shared task.")
                }.buttonStyle(.plain).accessibilityIdentifier("workspace.create.group")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            PhonePageHeader(title: store.t("Create"), back: { dismiss() })
        }
        .presentationDetents([.medium]).presentationDragIndicator(.visible)
    }
}
