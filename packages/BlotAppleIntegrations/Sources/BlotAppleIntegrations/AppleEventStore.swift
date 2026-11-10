@preconcurrency import EventKit
import BlotWorkspace
import Foundation

@MainActor
final class AppleEventStore {
    private let store = EKEventStore()
    func authorize(_ plugin: ApplePluginID) async throws {
        let granted = try await plugin == .calendar ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders()
        guard granted else { throw AppleIntegrationError.permissionDenied }
    }
    func authorized(_ plugin: ApplePluginID) -> Bool {
        EKEventStore.authorizationStatus(for: plugin == .calendar ? .event : .reminder) == .fullAccess
    }
    func resources(_ plugin: ApplePluginID) -> [AppleResource] {
        store.calendars(for: plugin == .calendar ? .event : .reminder).map {
            .init(id: $0.calendarIdentifier, name: $0.title + " · " + $0.source.title + ($0.allowsContentModifications ? "" : " · Только чтение"))
        }
    }
    func preview(_ tool: AppleTool, arguments a: AppleArguments) throws -> ChatJSON {
        let resource = try a.required("resource_id")
        if tool.plugin == .calendar {
            return eventJSON(try resolveEvent(a, resource: resource))
        }
        guard let reminder = store.calendarItem(withIdentifier: try a.required("id")) as? EKReminder, reminder.calendar.calendarIdentifier == resource else { throw AppleIntegrationError.missingResource }
        return Self.reminderJSON(reminder)
    }
    func execute(_ tool: AppleTool, arguments a: AppleArguments) async throws -> ChatJSON {
        guard authorized(tool.plugin), let calendar = store.calendar(withIdentifier: try a.required("resource_id")) else {
            throw AppleIntegrationError.permissionDenied
        }
        if tool.writes && !calendar.allowsContentModifications { throw AppleIntegrationError.permissionDenied }
        if tool.plugin == .calendar { return try event(tool.operation, calendar: calendar, a: a) }
        if tool.operation == "list" {
            let predicate = store.predicateForReminders(in: [calendar])
            let query = a["query"] ?? ""
            let values: [ChatJSON] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { items in
                    let result = (items ?? []).filter { query.isEmpty || (($0.title ?? "") + " " + ($0.notes ?? "")).localizedCaseInsensitiveContains(query) }
                        .prefix(100).map(Self.reminderJSON)
                    continuation.resume(returning: result)
                }
            }
            return .array(values)
        }
        let reminder: EKReminder
        if tool.operation == "create" { reminder = EKReminder(eventStore: store); reminder.calendar = calendar }
        else {
            guard let item = store.calendarItem(withIdentifier: try a.required("id")) as? EKReminder,
                  item.calendar.calendarIdentifier == calendar.calendarIdentifier else { throw AppleIntegrationError.missingResource }
            reminder = item
        }
        if tool.operation == "delete" { try store.remove(reminder, commit: true); return appleObject(["state": "deleted"]) }
        if let title = a["title"] { reminder.title = title }
        if let notes = a["notes"] { reminder.notes = notes }
        if a["due"] != nil { reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .timeZone], from: try a.date("due")) }
        if let completed = a["completed"] {
            guard ["true", "false"].contains(completed) else { throw AppleIntegrationError.invalidArguments }
            reminder.isCompleted = completed == "true"
        }
        try store.save(reminder, commit: true)
        return Self.reminderJSON(reminder)
    }
    private func event(_ operation: String, calendar: EKCalendar, a: AppleArguments) throws -> ChatJSON {
        if operation == "list" {
            let start = try a.date("start"), end = try a.date("end")
            guard end > start, end.timeIntervalSince(start) <= 366 * 86400 else { throw AppleIntegrationError.invalidArguments }
            let query = a["query"] ?? ""
            return .array(store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: [calendar]))
                .filter { query.isEmpty || (($0.title ?? "") + " " + ($0.notes ?? "")).localizedCaseInsensitiveContains(query) }.prefix(100).map(eventJSON))
        }
        let event: EKEvent
        if operation == "create" { event = EKEvent(eventStore: store); event.calendar = calendar }
        else {
            event = try resolveEvent(a, resource: calendar.calendarIdentifier)
        }
        if operation == "delete" { try store.remove(event, span: .thisEvent, commit: true); return appleObject(["state": "deleted"]) }
        if let title = a["title"] { event.title = title }
        if a["start"] != nil { event.startDate = try a.date("start") }
        if a["end"] != nil { event.endDate = try a.date("end") }
        guard let start = event.startDate, let end = event.endDate, end > start else { throw AppleIntegrationError.invalidArguments }
        if let notes = a["notes"] { event.notes = notes }
        if let location = a["location"] { event.location = location }
        try store.save(event, span: .thisEvent, commit: true)
        return eventJSON(event)
    }
    private func resolveEvent(_ a: AppleArguments, resource: String) throws -> EKEvent {
        let id = try a.required("id")
        if a["occurrence_start"] != nil {
            let start = try a.date("occurrence_start")
            guard let calendar = store.calendar(withIdentifier: resource),
                  let occurrence = store.events(matching: store.predicateForEvents(withStart: start.addingTimeInterval(-1), end: start.addingTimeInterval(86400), calendars: [calendar]))
                    .first(where: { $0.eventIdentifier == id && abs($0.startDate.timeIntervalSince(start)) < 1 }) else { throw AppleIntegrationError.missingResource }
            return occurrence
        }
        guard let event = store.event(withIdentifier: id), event.calendar.calendarIdentifier == resource else { throw AppleIntegrationError.missingResource }
        guard !event.hasRecurrenceRules else { throw AppleIntegrationError.system("Для повторяющегося события укажите occurrence_start из результатов поиска.") }
        return event
    }
    private func eventJSON(_ event: EKEvent) -> ChatJSON {
        appleObject(["id": event.eventIdentifier ?? "", "resource_id": event.calendar.calendarIdentifier,
            "title": event.title ?? "", "start": ISO8601DateFormatter().string(from: event.startDate),
            "occurrence_start": ISO8601DateFormatter().string(from: event.startDate),
            "end": ISO8601DateFormatter().string(from: event.endDate), "notes": event.notes ?? "", "location": event.location ?? ""])
    }
    nonisolated private static func reminderJSON(_ reminder: EKReminder) -> ChatJSON {
        appleObject(["id": reminder.calendarItemIdentifier, "resource_id": reminder.calendar.calendarIdentifier,
            "title": reminder.title ?? "", "notes": reminder.notes ?? "", "completed": String(reminder.isCompleted),
            "due": reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { ISO8601DateFormatter().string(from: $0) } ?? ""])
    }
}
