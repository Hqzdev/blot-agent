import Foundation

struct PhoneNotificationPreferences: Codable {
    var enabled = false
    var agentReplies = true
    var taskCompletion = true
    var approvalRequests = true
    var schedules = true
    var connections = true
}
