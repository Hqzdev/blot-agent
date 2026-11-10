import BlotDesign
import Foundation
import SwiftUI

typealias MacTeamAgent = MacDemoAgent
typealias MacTeamRoutine = MacDemoRoutine

extension MacDemoAgent {
    var shape: WorkspaceAvatar.ShapeKind {
        get { WorkspaceAvatar.ShapeKind(rawValue: avatarShape) ?? .round }
        set { avatarShape = newValue.rawValue }
    }
    init(
        id: String, name: String, role: String, instructions: String, color: String,
        shape: WorkspaceAvatar.ShapeKind, preview: String, unread: Bool = false,
        notifications: Bool = true, avatarData: Data? = nil
    ) {
        self.init(
            id: id, name: name, role: role, instructions: instructions, color: color,
            avatarShape: shape.rawValue, preview: preview, unread: unread,
            notifications: notifications, avatarData: avatarData)
    }
}

struct MacTeamPlugin: Identifiable, Hashable {
    let id: String
    let name: String
    let assetName: String
    let category: String
    let summary: String
    var accounts: [String] = []
    var connectionStatus: String? = nil
}

enum MacTeamDestination: String, Hashable {
    case marketplace, routines, skills, memory, files
    var title: String {
        switch self {
        case .marketplace: "Приложения и шаблоны"
        case .routines: "Расписания"
        case .skills: "Навыки"
        case .memory: "Память"
        case .files: "Файлы"
        }
    }

}

enum MacTeamSelection: Hashable {
    case agent(String)
    case group(String)
    case library(MacTeamDestination)
}

enum MacTeamSheet: Identifiable {
    case newAgent, editAgent
    case agentProfile(String)
    case group(String?)
    case addPlugin
    case plugin(MacTeamPlugin)
    case template(String)
    case routine(String?)
    case skill, memory, email, attachment, transactions, document, billing
    var id: String {
        switch self {
        case .newAgent: "new-agent"
        case .editAgent: "edit-agent"
        case .agentProfile(let id): "agent-profile-" + id
        case .group(let id): "group-" + (id ?? "new")
        case .addPlugin: "add-plugin"
        case .plugin(let plugin): "plugin-" + plugin.id
        case .template(let name): "template-" + name
        case .routine(let id): "routine-" + (id ?? "new")
        case .skill: "skill"
        case .memory: "memory"
        case .email: "email"
        case .attachment: "attachment"
        case .transactions: "transactions"
        case .document: "document"
        case .billing: "billing"
        }
    }
}
