import BlotDomain
import Foundation

public struct WorkspaceScheduleCalculator: Sendable {
    public init() {}

    public func nextRun(for schedule: BlotV3.Automation, after date: Date) throws -> Date? {
        try occurrence(for: schedule, relativeTo: date, direction: .forward)
    }

    public func dueRuns(for schedule: BlotV3.Automation, after watermark: Date, through now: Date) throws -> [Date] {
        guard schedule.enabled, now > watermark else { return [] }
        let limit = schedule.missedRunPolicy == .catch_up ? schedule.maxCatchUpRuns ?? 1 : 1
        guard (1...100).contains(limit) else { throw WorkspaceStorageError.invalidParameters }
        var cursor = now.addingTimeInterval(0.001)
        var result: [Date] = []
        for _ in 0..<limit {
            guard let previous = try occurrence(for: schedule, relativeTo: cursor, direction: .backward), previous > watermark else { break }
            if schedule.missedRunPolicy == .skip && now.timeIntervalSince(previous) > 60 { break }
            result.append(previous)
            cursor = previous
        }
        return result.reversed()
    }

    private func occurrence(for schedule: BlotV3.Automation, relativeTo date: Date, direction: Calendar.SearchDirection) throws -> Date? {
        guard schedule.enabled else { return nil }
        guard let timezone = TimeZone(identifier: schedule.timezone) else { throw WorkspaceStorageError.invalidParameters }
        if let scheduledAt = schedule.scheduledAt {
            return direction == .forward ? (scheduledAt > date ? scheduledAt : nil) : (scheduledAt < date ? scheduledAt : nil)
        }
        let components = schedule.localTime.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2, let hour = Int(components[0]), let minute = Int(components[1]),
              (0...23).contains(hour), (0...59).contains(minute),
              !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }) else { throw WorkspaceStorageError.invalidParameters }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let candidates = schedule.weekdays.compactMap { day -> Date? in
            let components = DateComponents(hour: hour, minute: minute, second: 0, weekday: day % 7 + 1)
            var cursor = date
            for _ in 0..<2 {
                guard let candidate = calendar.nextDate(after: cursor, matching: components, matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first, direction: direction) else { return nil }
                let start = calendar.startOfDay(for: candidate)
                // A backward search may return the second occurrence in a repeated hour.
                guard let canonical = calendar.nextDate(after: start.addingTimeInterval(-0.001),
                    matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime,
                    repeatedTimePolicy: .first, direction: .forward) else { return nil }
                if direction == .forward ? canonical > date : canonical < date { return canonical }
                if direction == .backward { cursor = start }
                else {
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
                    cursor = nextDay.addingTimeInterval(-0.001)
                }
            }
            return nil
        }
        return direction == .forward ? candidates.min() : candidates.max()
    }
}
