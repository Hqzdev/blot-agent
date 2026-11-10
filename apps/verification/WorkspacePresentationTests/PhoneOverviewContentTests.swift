import BlotDomain
import Foundation
import XCTest

@MainActor
final class PhoneOverviewContentTests: XCTestCase {
    func testWorkFromDifferentChatsAppearsAndCanceledWorkStaysOut() throws {
        let tasks = try BlotV3.TaskState.allCases.map { state in
            let id = UUID()
            return try BlotV3.Task(metadata: metadata(id: id),
                execution: .init(executorDeviceId: UUID(), originDeviceId: UUID(), taskId: id, revision: 1),
                conversationId: UUID(), goal: state.rawValue, state: state, plan: [])
        }
        var snapshot = WorkspaceSnapshot()
        snapshot.tasks = tasks
        let content = PhoneOverviewContent(snapshot: snapshot, now: .now)
        XCTAssertEqual(Set(content.attention.map(\.state)), [.waiting_approval, .waiting_user, .interrupted, .failed])
        XCTAssertEqual(Set(content.active.map(\.state)), [.draft, .planning, .queued, .running, .paused])
        XCTAssertEqual(content.completed.map(\.state), [.completed])
        XCTAssertEqual(Set((content.attention + content.active + content.completed).map(\.conversationId)).count, tasks.count - 1)
    }

    func testUpcomingRunsRespectTimeZonesAndSkipDisabledOrPastSchedules() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-07T06:00:00Z"))
        var snapshot = WorkspaceSnapshot()
        snapshot.schedules = [
            try schedule("Later", time: "12:00", timezone: "Asia/Yekaterinburg"),
            try schedule("Sooner", time: "09:30", timezone: "Europe/Moscow"),
            try schedule("Disabled", time: "11:15", timezone: "Asia/Yekaterinburg", enabled: false),
            try schedule("Past", time: "11:00", timezone: "Asia/Yekaterinburg", scheduledAt: now.addingTimeInterval(-60))
        ]
        let content = PhoneOverviewContent(snapshot: snapshot, now: now)
        XCTAssertEqual(content.upcoming.map(\.schedule.name), ["Sooner", "Later"])
        XCTAssertEqual(content.upcoming.map { $0.date.timeIntervalSince(now) }, [1800, 3600])
    }

    private func metadata(id: UUID = UUID()) throws -> BlotV3.RecordMetadata {
        try .init(id: id, ownerId: UUID(), version: 1, createdAt: .now, updatedAt: .now)
    }

    private func schedule(_ name: String, time: String, timezone: String, enabled: Bool = true,
                          scheduledAt: Date? = nil) throws -> BlotV3.Automation {
        try .init(metadata: metadata(), kind: .task, name: name, goal: "Prepare report", timezone: timezone,
                  localTime: time, weekdays: [1, 2, 3, 4, 5, 6, 7], missedRunPolicy: .coalesce,
                  enabled: enabled, scheduledAt: scheduledAt)
    }
}
