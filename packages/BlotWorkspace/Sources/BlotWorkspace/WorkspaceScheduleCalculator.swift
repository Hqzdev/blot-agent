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
        let parts = schedule.localTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]),
              !schedule.weekdays.isEmpty, schedule.weekdays.allSatisfy({ (1...7).contains($0) }) else { throw WorkspaceStorageError.invalidParameters }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let candidates = schedule.weekdays.compactMap { day -> Date? in
            let components = DateComponents(hour: parts[0], minute: parts[1], second: 0, weekday: day % 7 + 1)
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime,
                repeatedTimePolicy: .first, direction: direction)
        }
        return direction == .forward ? candidates.min() : candidates.max()
    }
}
