import XCTest
@testable import TodoMDCore

final class TaskFilenameGeneratorTests: XCTestCase {
    func testSlugAndCollisionHandling() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let generator = TaskFilenameGenerator(nowProvider: { fixedDate })
        let first = generator.generate(title: "Review PR for Auth!!!", existingFilenames: [])
        XCTAssertTrue(first.hasSuffix("review-pr-for-auth.md"))

        let second = generator.generate(title: "Review PR for Auth!!!", existingFilenames: [first])
        XCTAssertTrue(second.hasSuffix("review-pr-for-auth-2.md"))
    }

    func testSlugLengthLimit() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let generator = TaskFilenameGenerator(nowProvider: { fixedDate })
        let title = String(repeating: "abc", count: 100)
        let result = generator.generate(title: title, existingFilenames: [])
        XCTAssertLessThanOrEqual(result.count, 4 + 13 + 1 + 60 + 3)
    }
}
