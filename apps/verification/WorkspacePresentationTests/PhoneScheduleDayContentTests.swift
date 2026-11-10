import BlotDomain
import Foundation
import XCTest

@MainActor
final class PhoneScheduleDayContentTests: XCTestCase {
    func testSelectingAnotherDayChangesRunsAndKeepsPausedSchedulesVisible() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Yekaterinburg"))
        let monday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T06:00:00Z"))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let schedules = try [schedule("Monday", weekdays: [1]), schedule("Tuesday", weekdays: [2], enabled: false)]
        let first = PhoneScheduleDayContent(schedules: schedules, day: monday, calendar: calendar)
        let second = PhoneScheduleDayContent(schedules: schedules, day: tuesday, calendar: calendar)
        XCTAssertEqual(first.runs.map(\.schedule.name), ["Monday"])
        XCTAssertEqual(second.runs.map(\.schedule.name), ["Tuesday"])
        XCTAssertFalse(try XCTUnwrap(second.runs.first).schedule.enabled)
    }

    func testRunBelongsToTheVisibleDayAcrossTimeZones() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Yekaterinburg"))
        let monday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T06:00:00Z"))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let late = try schedule("Late Moscow run", weekdays: [1], time: "23:30", timezone: "Europe/Moscow")
        XCTAssertTrue(PhoneScheduleDayContent(schedules: [late], day: monday, calendar: calendar).runs.isEmpty)
        XCTAssertEqual(PhoneScheduleDayContent(schedules: [late], day: tuesday, calendar: calendar).runs.count, 1)
    }

    private func schedule(_ name: String, weekdays: [Int], enabled: Bool = true, time: String = "08:30",
                          timezone: String = "Asia/Yekaterinburg") throws -> BlotV3.Automation {
        try .init(metadata: .init(id: UUID(), ownerId: UUID(), version: 1, createdAt: .now, updatedAt: .now),
                  kind: .task, name: name, goal: "Report", timezone: timezone, localTime: time,
                  weekdays: weekdays, missedRunPolicy: .coalesce, enabled: enabled)
    }
}
