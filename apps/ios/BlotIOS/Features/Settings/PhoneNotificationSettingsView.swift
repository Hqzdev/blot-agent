import BlotDesign
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct PhoneNotificationSettingsView: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var requesting = false
    @State private var denied = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 28) {
                PhoneSettingsGroup(title: "Notifications") {
                    Toggle(store.t("Allow notifications"), isOn: enabled)
                        .padding(.horizontal, 18).frame(minHeight: 54).disabled(requesting)
                }
                PhoneSettingsGroup(title: "Notify me about") {
                    option("Agent replies", detail: "When an agent finishes replying", selection: $store.notificationPreferences.agentReplies)
                    PhoneSettingsDivider()
                    option("Completed tasks", detail: "When an agent finishes a task", selection: $store.notificationPreferences.taskCompletion)
                    PhoneSettingsDivider()
                    option("Approval requests", detail: "When an action needs your confirmation", selection: $store.notificationPreferences.approvalRequests)
                    PhoneSettingsDivider()
                    option("Scheduled tasks", detail: "Reminders and scheduled task updates", selection: $store.notificationPreferences.schedules)
                    PhoneSettingsDivider()
                    option("Connection changes", detail: "When a computer or service needs attention", selection: $store.notificationPreferences.connections)
                }.disabled(!store.notificationPreferences.enabled)
                if denied {
                    Text(store.t("Notifications are disabled in iOS Settings."))
                        .font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
                    Button(store.t("Open iOS Settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.buttonStyle(.plain)
                }
                WorkspaceFeedback()
            }.padding(20)
        }
        .background(PhoneSettingsStyle.canvas.ignoresSafeArea())
        .task { denied = await store.notifications.authorizationStatus() == .denied }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                _Concurrency.Task { denied = await store.notifications.authorizationStatus() == .denied }
            }
        }
    }

    private var enabled: Binding<Bool> {
        Binding(get: { store.notificationPreferences.enabled }, set: { value in
            if !value { store.notificationPreferences.enabled = false; return }
            requesting = true
            _Concurrency.Task {
                let allowed = await store.notifications.requestAccess()
                store.notificationPreferences.enabled = allowed
                denied = !allowed
                requesting = false
            }
        })
    }

    private func option(_ title: String, detail: String, selection: Binding<Bool>) -> some View {
        Toggle(isOn: selection) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.t(title)).font(.body)
                Text(store.t(detail)).font(.footnote).foregroundStyle(WorkspaceStyle.secondary)
            }
        }.padding(.horizontal, 18).padding(.vertical, 12).frame(minHeight: 64)
    }
}
