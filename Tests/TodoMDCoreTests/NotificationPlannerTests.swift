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
}
