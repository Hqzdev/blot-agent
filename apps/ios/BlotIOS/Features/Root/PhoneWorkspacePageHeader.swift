import BlotDomain
import BlotDesign
import SwiftUI

struct PhoneWorkspacePageHeader: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store

    static func isUsed(on route: WorkspaceRoute) -> Bool {
        !route.isAuthentication && ![WorkspaceRoute.chats, .archivedChats, .agents, .chat, .search,
                                     .newChat, .createAgent, .editAgent, .connections].contains(route)
    }

    static func title(for route: WorkspaceRoute, store: WorkspaceStore) -> String {
        switch route {
        case .settings: store.t("Settings")
        case .file: store.selectedFile?.name ?? store.t("Files")
        case .running: store.t("Tasks")
        case .approval: store.t("Review prepared action")
        case .result: store.t("Result")
        case .offline: store.t("Computer offline")
        default: PhoneSettingsCatalog.title(for: route).map { store.settingsText($0) } ?? store.t(route.title)
        }
    }

    var body: some View {
        PhonePageHeader(title: Self.title(for: route, store: store),
                        back: store.history.isEmpty ? nil : { store.back() }) {
            if route == .settings {
                Button { store.navigate(.settingsProfile) } label: {
                    PhoneProfileAvatar(data: store.profile.avatar, size: 36).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(store.settingsText("Profile"))
            } else if route == .schedules {
                PhoneGlassCircleButton(symbol: "plus", title: store.t("New schedule")) { store.navigate(.createSchedule) }
            } else if [.running, .result].contains(route) {
                Menu {
                    Button(store.t("Task details")) { store.navigate(.running) }
                    Button(store.t("Review prepared action")) { store.navigate(.approval) }
                    Button(store.t("Result")) { store.navigate(.result) }
                    Button(store.t("View browser")) { store.navigate(.browser) }
                } label: {
                    BlotIcon(symbol: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel(store.t("More options"))
            }
        }
    }
}
