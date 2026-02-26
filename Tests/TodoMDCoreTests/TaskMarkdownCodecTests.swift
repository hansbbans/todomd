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
}
