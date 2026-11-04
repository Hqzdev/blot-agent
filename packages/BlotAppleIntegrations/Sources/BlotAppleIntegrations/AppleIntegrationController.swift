import BlotDomain
import BlotWorkspace
import Foundation
import Observation
#if os(iOS)
import MessageUI
#endif

@MainActor
public protocol AppleIntegrationExecuting: Sendable {
    var interactions: AppleInteractionCenter { get }
    func resources(_ plugin: ApplePluginID, selected: [String]) async throws -> [AppleResource]
    func accessible(_ plugin: ApplePluginID, resources: [String]) async -> Bool
    func execute(_ tool: AppleTool, arguments: ChatJSON) async throws -> ChatJSON
    func preview(_ tool: AppleTool, arguments: ChatJSON) async throws -> ChatJSON?
}

@MainActor @Observable
public final class AppleIntegrationController: AppleIntegrationExecuting {
    public let interactions = AppleInteractionCenter()
    public private(set) var revision = 0
    private let events = AppleEventStore()
    private let contacts = AppleContactStore()
    private let folders: AppleFolderStore
    private let shortcuts: AppleShortcutStore
    #if os(macOS)
    private let automation = AppleAutomation()
    #endif
    public init(bookmarkFile: URL) throws {
        folders = try AppleFolderStore(file: bookmarkFile)
        shortcuts = try AppleShortcutStore(file: bookmarkFile.deletingLastPathComponent().appendingPathComponent("AppleShortcuts.plist"))
    }
    public func verifyShortcut(_ name: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.utf8.count <= 500 else { throw AppleIntegrationError.invalidArguments }
        try shortcuts.invalidate(name); revision += 1
        _ = try await interactions.runShortcut(name: name, input: "")
        try shortcuts.verified(name)
        revision += 1
    }
    public func resources(_ plugin: ApplePluginID, selected: [String]) async throws -> [AppleResource] {
        let available: [AppleResource]
        switch plugin {
        case .calendar, .reminders: available = events.resources(plugin)
        case .contacts: available = [.init(id: "contacts", name: contacts.limited ? "Выбранные контакты" : "Доступные контакты")]
        case .files: available = folders.resources
        case .shortcuts: available = shortcuts.resources
        case .mail, .notes:
            #if os(macOS)
            available = try automation.resources(plugin)
            #else
            available = plugin == .mail ? [.init(id: "compose", name: "Системный редактор письма")] : []
            #endif
        }
        return available.filter { selected.contains($0.id) }
    }
    public func requestResources(_ plugin: ApplePluginID) async throws -> [AppleResource] {
        guard plugin.available else { throw AppleIntegrationError.unavailable }
        switch plugin {
        case .calendar, .reminders: try await events.authorize(plugin); return events.resources(plugin)
        case .contacts: try await contacts.authorize(); return [.init(id: "contacts", name: contacts.limited ? "Выбранные контакты" : "Доступные контакты")]
        case .files: return folders.resources
        case .shortcuts: return shortcuts.resources
        case .mail, .notes:
            #if os(macOS)
            guard automation.authorized(plugin, request: true) else { throw AppleIntegrationError.permissionDenied }
            return try automation.resources(plugin)
            #else
            guard plugin == .mail, MFMailComposeViewController.canSendMail() else { throw AppleIntegrationError.unavailable }
            return [.init(id: "compose", name: "Системный редактор письма")]
            #endif
        }
    }
    public func addFolder(_ url: URL) throws -> AppleResource { let resource = try folders.add(url); revision += 1; return resource }
    public func status(_ plugin: ApplePluginID, resources: [String]) async -> String {
        guard plugin.available else { return "Доступно на Mac" }
        guard !resources.isEmpty else { return "Нужна настройка" }
        let authorized: Bool
        switch plugin {
        case .calendar, .reminders:
            authorized = events.authorized(plugin) && Set(resources).isSubset(of: Set(events.resources(plugin).map(\.id)))
        case .contacts:
            if contacts.limited { return "Доступ ограничен" }
            authorized = contacts.authorized
        case .files: authorized = folders.accessible(resources)
        case .shortcuts: return shortcuts.contains(resources) ? "Подключено" : "Нужна настройка"
        case .mail, .notes:
            #if os(macOS)
            authorized = automation.authorized(plugin)
            #else
            authorized = plugin == .mail && MFMailComposeViewController.canSendMail()
            #endif
        }
        return authorized ? "Подключено" : "Нужно разрешение"
    }
    public func accessible(_ plugin: ApplePluginID, resources: [String]) async -> Bool {
        let value = await status(plugin, resources: resources)
        return value == "Подключено" || value == "Доступ ограничен"
    }
    public func execute(_ tool: AppleTool, arguments json: ChatJSON) async throws -> ChatJSON {
        let arguments = try AppleArguments(json)
        return try await executeArguments(tool, arguments: arguments)
    }
    private func executeArguments(_ tool: AppleTool, arguments: AppleArguments) async throws -> ChatJSON {
        switch tool.plugin {
        case .calendar, .reminders: return try await events.execute(tool, arguments: arguments)
        case .contacts: return try contacts.execute(tool, arguments: arguments)
        case .files: return try folders.execute(tool, arguments: arguments)
        case .shortcuts:
            let name = try arguments.required("resource_id")
            do { return try await interactions.runShortcut(name: name, input: arguments["input"] ?? "") }
            catch { try? shortcuts.invalidate(name); revision += 1; throw error }
        case .mail, .notes:
            #if os(macOS)
            return try automation.execute(tool, arguments: arguments)
            #else
            return try await interactions.compose(arguments)
            #endif
        }
    }
    public func preview(_ tool: AppleTool, arguments json: ChatJSON) async throws -> ChatJSON? {
        let arguments = try AppleArguments(json)
        guard tool.needsConfirmation else { return nil }
        switch tool.plugin {
        case .calendar, .reminders: return try events.preview(tool, arguments: arguments)
        case .contacts: return try contacts.preview(arguments)
        case .files: return try folders.preview(arguments)
        case .mail, .notes:
            #if os(macOS)
            return try automation.execute(tool, arguments: arguments, preview: true)
            #else
            return nil
            #endif
        case .shortcuts: return nil
        }
    }

    public func changed() { revision += 1 }
}
