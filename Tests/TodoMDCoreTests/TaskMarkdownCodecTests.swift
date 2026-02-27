import XCTest
@testable import TodoMDCore

final class TaskMarkdownCodecTests: XCTestCase {
    func testRoundTripPreservesUnknownFrontmatter() throws {
        let raw = """
        ---
        title: \"Buy groceries\"
        status: \"todo\"
        created: \"2025-02-26T14:30:00Z\"
        source: \"user\"
        custom_field: \"keep-me\"
        ---
        Notes
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw)
        XCTAssertEqual(parsed.unknownFrontmatter["custom_field"], .string("keep-me"))

        let serialized = try codec.serialize(document: parsed)
        let parsedAgain = try codec.parse(markdown: serialized)
        XCTAssertEqual(parsedAgain.unknownFrontmatter["custom_field"], .string("keep-me"))
        XCTAssertEqual(parsedAgain.frontmatter.title, "Buy groceries")
    }

    func testMissingRequiredFieldThrows() {
        let raw = """
        ---
        status: \"todo\"
        created: \"2025-02-26T14:30:00Z\"
        source: \"user\"
        ---
        """

        let codec = TaskMarkdownCodec()
        XCTAssertThrowsError(try codec.parse(markdown: raw))
    }

    func testValidationMaxLengths() throws {
        let frontmatter = TestSupport.sampleFrontmatter(title: String(repeating: "a", count: 501))
        let document = TaskDocument(frontmatter: frontmatter, body: "")
        XCTAssertThrowsError(try TaskValidation.validate(document: document))
    }

    func testBodyLengthExceededThrows() {
        let frontmatter = TestSupport.sampleFrontmatter()
        let body = String(repeating: "x", count: TaskValidation.maxBodyLength + 1)
        let document = TaskDocument(frontmatter: frontmatter, body: body)
        XCTAssertThrowsError(try TaskValidation.validate(document: document))
    }

    func testLegacyFrontmatterDefaultsAndFlexibleDateParsing() throws {
        let raw = """
        ---
        title: Buy milk
        created: 2026-02-26T20:57:16Z
        due: 2026-02-27
        tags: home, errands
        ---
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw)
        XCTAssertEqual(parsed.frontmatter.title, "Buy milk")
        XCTAssertEqual(parsed.frontmatter.status, .todo)
        XCTAssertEqual(parsed.frontmatter.source, "unknown")
        XCTAssertEqual(parsed.frontmatter.tags, ["home", "errands"])
        XCTAssertEqual(parsed.frontmatter.due, try LocalDate(isoDate: "2026-02-27"))
        XCTAssertNotEqual(parsed.frontmatter.created, .distantPast)
    }

    func testFrontmatterCanEndAtEOF() throws {
        let raw = """
        ---
        title: "Inbox task"
        status: "todo"
        created: "2025-02-26T14:30:00Z"
        source: "user"
        ---
        """
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw)
        XCTAssertEqual(parsed.frontmatter.title, "Inbox task")
        XCTAssertEqual(parsed.body, "")
    }

    func testCaseInsensitiveKeysAndLegacyStatusPriorityAliases() throws {
        let raw = """
        ---
        Title: "Legacy task"
        Status: "open"
        Priority: "p2"
        Created: "2026-02-26T20:57:16Z"
        Source: "legacy-import"
        ---
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw)
        XCTAssertEqual(parsed.frontmatter.title, "Legacy task")
        XCTAssertEqual(parsed.frontmatter.status, .todo)
        XCTAssertEqual(parsed.frontmatter.priority, .medium)
        XCTAssertEqual(parsed.frontmatter.source, "legacy-import")
    }

    func testFallbackTitleAndDateAliasKeys() throws {
        let raw = """
        ---
        status: open
        priority: normal
        due: 2025-12-25
        scheduled:
        dateCreated: 2025-12-24T16:54:45.308-05:00
        dateModified: 2025-12-24T16:54:45.308-05:00
        completedDate:
        tags:
          - task
        ---
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw, fallbackTitle: "return brook brothers")
        XCTAssertEqual(parsed.frontmatter.title, "return brook brothers")
        XCTAssertEqual(parsed.frontmatter.status, .todo)
        XCTAssertEqual(parsed.frontmatter.priority, .medium)
        XCTAssertEqual(parsed.frontmatter.due, try LocalDate(isoDate: "2025-12-25"))
        XCTAssertNil(parsed.frontmatter.scheduled)
        XCTAssertEqual(parsed.frontmatter.tags, ["task"])
        XCTAssertNotEqual(parsed.frontmatter.created, .distantPast)
    }

    func testRedundantSecondOpeningDelimiterIsAccepted() throws {
        let raw = """
        ---
        ---
        status: done
        priority: normal
        due: 2025-12-24
        scheduled: 2025-12-24
        dateCreated: 2025-12-24T17:56:58.398-05:00
        dateModified: 2025-12-24T18:32:22.192-05:00
        tags:
          - task
        completedDate: 2025-12-24
        ---
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw, fallbackTitle: "set up my new task system")
        XCTAssertEqual(parsed.frontmatter.title, "set up my new task system")
        XCTAssertEqual(parsed.frontmatter.status, .done)
        XCTAssertEqual(parsed.frontmatter.priority, .medium)
        XCTAssertEqual(parsed.frontmatter.scheduled, try LocalDate(isoDate: "2025-12-24"))
        XCTAssertEqual(parsed.frontmatter.tags, ["task"])
    }

    func testDueTimeParsesAndSerializes() throws {
        let raw = """
        ---
        title: "Timed task"
        status: "todo"
        due: "2025-12-24"
        due_time: "08:30"
        created: "2025-02-26T14:30:00Z"
        source: "user"
        ---
        """

        let codec = TaskMarkdownCodec()
        let parsed = try codec.parse(markdown: raw)
        XCTAssertEqual(parsed.frontmatter.due?.isoString, "2025-12-24")
        XCTAssertEqual(parsed.frontmatter.dueTime?.isoString, "08:30")

        let serialized = try codec.serialize(document: parsed)
        XCTAssertTrue(serialized.contains("due_time"))
        XCTAssertTrue(serialized.contains("08:30"))
    }
}
