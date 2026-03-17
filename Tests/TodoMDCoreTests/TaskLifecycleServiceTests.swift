import XCTest
@testable import TodoMDCore

final class TaskLifecycleServiceTests: XCTestCase {
    func testCompleteRepeating_preserves_scheduledTime() throws {
        var fm = TestSupport.sampleFrontmatter()
        fm.recurrence = "FREQ=WEEKLY"
        fm.scheduled = try LocalDate(isoDate: "2026-03-17")
        fm.scheduledTime = try LocalTime(isoTime: "20:00")
        let doc = TaskDocument(frontmatter: fm, body: "")

        let service = TaskLifecycleService()
        let (_, next) = try service.completeRepeating(doc, at: Date())

        XCTAssertEqual(next.frontmatter.scheduledTime?.isoString, "20:00",
                       "scheduledTime should survive completeRepeating")
    }
}
