import Foundation
import UIKit
import UserNotifications

@MainActor
final class PhoneNotifications: NSObject, UNUserNotificationCenterDelegate {
    private var onOpen: ((UUID) -> Void)?
    var accountActive = false

    func clear() {
        accountActive = false
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func install(onOpen: @escaping (UUID) -> Void) {
        self.onOpen = onOpen
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAccess() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func replyReady(conversationID: UUID, messageID: UUID, title: String, text: String,
                    preferences: PhoneNotificationPreferences) async {
        guard accountActive, preferences.enabled, preferences.agentReplies, UIApplication.shared.applicationState != .active else { return }
        let status = await authorizationStatus()
        guard accountActive, status == .authorized || status == .provisional || status == .ephemeral else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = String(text.replacingOccurrences(of: "**", with: "").prefix(180))
        content.sound = .default
        content.threadIdentifier = conversationID.uuidString
        content.userInfo = ["conversationID": conversationID.uuidString]
        try? await UNUserNotificationCenter.current().add(.init(identifier: messageID.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        guard let value = response.notification.request.content.userInfo["conversationID"] as? String,
              let id = UUID(uuidString: value) else { return }
        await MainActor.run { self.onOpen?(id) }
    }
}
