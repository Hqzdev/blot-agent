import BlotDesign
import SwiftUI

struct PhoneWorkspaceScreen: View {
    let route: WorkspaceRoute
    @Environment(WorkspaceStore.self) private var store

    static func usesFloatingControls(_ route: WorkspaceRoute) -> Bool {
        [.welcome, .signIn, .createAccount, .firstAgent, .createAgent, .editAgent, .chats, .archivedChats, .chat, .agents, .connections, .search, .newChat, .settings].contains(route)
    }

    var body: some View {
        Group {
            if store.screenState != .normal { WorkspacePage(route: route) }
            else {
                switch route {
                case .welcome: PhoneWelcomeView()
                case .signIn, .createAccount: PhoneAuthenticationView(initialRoute: route)
                case .firstAgent: PhoneFirstAgentView()
                case .createAgent: PhoneAgentCreationView()
                case .editAgent: PhoneAgentCreationView(isEditing: true)
                case .chats: PhoneChatsView()
                case .archivedChats: PhoneChatsView(showsArchive: true)
                case .agents: PhoneChatsView(showsAgents: true)
                case .connections: PhonePluginsView()
                case .chat: PhoneConversationView()
                case .search: PhoneSearchView()
                case .newChat: PhoneNewChatView()
                case .settings: PhoneSettingsMenuView()
                case .overview: PhoneOverviewView()
                case .schedules: PhoneSchedulesView()
                case .appSettings, .language: PhoneGeneralSettingsView()
                case .appearance: PhoneAppearanceSettingsView()
                case .settingsProfile, .account, .usage: PhoneSettingsProfileView()
                case .settingsStorage: PhoneStorageSettingsView()
                case .settingsUpdates: PhoneUpdatesSettingsView()
                case .permissions: PhonePrivacySettingsView()
                case .mcp: PhoneMcpSettingsView()
                case .models, .devices, .pair, .permissionRules, .browserSettings:
                    PhoneSettingsPage { WorkspaceSettingsView(route: route) }
                case .personalization: PhonePersonalizationView()
                case .memory: PhoneMemorySettingsView()
                case .notifications: PhoneNotificationSettingsView()
                case .createSchedule: PhoneScheduleEditor()
                case .file:
                    if store.mode == .live { WorkspaceLocalFileView() }
                    else { PhoneWorkspaceFileView() }
                default: WorkspacePage(route: route)
                }
            }
        }
        .background(WorkspaceStyle.canvas).foregroundStyle(WorkspaceStyle.ink)
        .accessibilityIdentifier("workspace.screen.\(route.rawValue)")
    }
}
