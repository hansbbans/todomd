import XCTest
@testable import TodoMDCore

final class NotificationPlannerTests: XCTestCase {
    func testNotificationIdentifiersAreDeterministic() throws {
        let planner = NotificationPlanner(calendar: Calendar(identifier: .gregorian), defaultHour: 9, defaultMinute: 0)
        let due = try LocalDate(isoDate: "2025-03-01")
        let frontmatter = TestSupport.sampleFrontmatter(due: due)
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/20250301-0900-task.md"), document: .init(frontmatter: frontmatter, body: ""))

        let plans = planner.planNotifications(for: record)
        XCTAssertEqual(plans.count, 1)
        XCTAssertEqual(plans.first?.identifier, "20250301-0900-task.md#due")
    }

    func testPersistentNagsPlannedWhenEnabled() throws {
        let planner = NotificationPlanner(
            calendar: Calendar(identifier: .gregorian),
            defaultHour: 9,
            defaultMinute: 0,
            persistentRemindersEnabled: true,
            persistentReminderIntervalMinutes: 1,
            maxPersistentNagsPerTask: 3
        )
        var frontmatter = TestSupport.sampleFrontmatter(due: try LocalDate(isoDate: "2027-03-01"))
        frontmatter.dueTime = try LocalTime(hour: 10, minute: 30)
        let record = TaskRecord(identity: TaskFileIdentity(path: "/tmp/20250301-0900-task.md"), document: .init(frontmatter: frontmatter, body: ""))

        let referenceDate = ISO8601DateFormatter().date(from: "2027-02-27T12:00:00Z")!
        let plans = planner.planNotifications(for: record, referenceDate: referenceDate)
        XCTAssertEqual(plans.count, 4)
        XCTAssertEqual(plans.map(\.identifier), [
            "20250301-0900-task.md#due",
            "20250301-0900-task.md#nag-1",
            "20250301-0900-task.md#nag-2",
            "20250301-0900-task.md#nag-3"
        ])
    }
}
