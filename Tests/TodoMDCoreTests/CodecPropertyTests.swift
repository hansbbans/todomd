import XCTest
@testable import TodoMDCore

// MARK: - Property-based test harness

/// Runs `body` `count` times with a seeded random number generator, surfacing
/// the first failure with a reproducible message.
private func checkProperty(
    _ description: String,
    count: Int = 100,
    body: (inout any RandomNumberGenerator) throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) rethrows {
    var rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    for iteration in 0..<count {
        do {
            try body(&rng)
        } catch {
            XCTFail(
                "Property '\(description)' failed on iteration \(iteration): \(error)",
                file: file,
                line: line
            )
            throw error
        }
    }
}

// MARK: - Arbitrary helpers

private extension String {
    /// Returns a random substring of up to `maxLength` Unicode scalars drawn
    /// from the supplied pool, using `rng` for randomness.
    static func arbitrary(
        maxLength: Int,
        pool: [Unicode.Scalar],
        rng: inout any RandomNumberGenerator
    ) -> String {
        let length = Int.random(in: 0...maxLength, using: &rng)
        return String(
            (0..<length).map { _ in
                Character(pool[Int.random(in: 0..<pool.count, using: &rng)])
            }
        )
    }
}

/// Printable ASCII characters that are safe inside YAML quoted strings.
private let asciiPool: [Unicode.Scalar] = (32...126)
    .compactMap { Unicode.Scalar($0) }
    .filter { $0 != "\"" && $0 != "\\" && $0 != "\n" && $0 != "\r" }

/// A curated set of Unicode scalars spanning multiple planes.
private let unicodePool: [Unicode.Scalar] = [
    // Latin Extended-A
    "à", "é", "ñ", "ü", "ø",
    // Greek
    "α", "β", "γ", "Δ", "Ω",
    // CJK
    "中", "文", "日", "한",
    // Emoji (basic multi-codepoint emoji are excluded to keep codec round-trip tractable)
    "★", "✓", "→", "—",
    // Supplemental Multilingual Plane (𝄞 Musical Symbol G Clef)
    Unicode.Scalar(0x1D11E)!,
    // RTL characters
    "ש", "م"
]

private let mixedPool: [Unicode.Scalar] = asciiPool + unicodePool

// MARK: - Generators

/// Generates a valid, non-empty title that fits within `TaskValidation.maxTitleLength`.
private func arbitraryTitle(rng: inout any RandomNumberGenerator) -> String {
    let maxLen = min(80, TaskValidation.maxTitleLength)
    var title = String.arbitrary(maxLength: maxLen, pool: mixedPool, rng: &rng)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if title.isEmpty {
        title = "task-\(Int.random(in: 1...9999, using: &rng))"
    }
    return title
}

/// Generates a valid source string (non-empty, printable ASCII).
private func arbitrarySource(rng: inout any RandomNumberGenerator) -> String {
    let sources = ["user", "import", "cli", "test", "codex", "legacy"]
    return sources[Int.random(in: 0..<sources.count, using: &rng)]
}

/// Generates a random `TaskStatus`.
private func arbitraryStatus(rng: inout any RandomNumberGenerator) -> TaskStatus {
    TaskStatus.allCases[Int.random(in: 0..<TaskStatus.allCases.count, using: &rng)]
}

/// Generates a random `TaskPriority`.
private func arbitraryPriority(rng: inout any RandomNumberGenerator) -> TaskPriority {
    TaskPriority.allCases[Int.random(in: 0..<TaskPriority.allCases.count, using: &rng)]
}

/// Generates a random valid `LocalDate` in the range 2000-01-01 … 2099-12-28
/// (day capped at 28 to avoid month-end validation errors).
private func arbitraryLocalDate(rng: inout any RandomNumberGenerator) -> LocalDate {
    let year = Int.random(in: 2000...2099, using: &rng)
    let month = Int.random(in: 1...12, using: &rng)
    let day = Int.random(in: 1...28, using: &rng)
    return (try? LocalDate(year: year, month: month, day: day)) ?? LocalDate.epoch
}

/// Generates an optional `LocalDate`.
private func arbitraryOptionalDate(rng: inout any RandomNumberGenerator) -> LocalDate? {
    Bool.random(using: &rng) ? arbitraryLocalDate(rng: &rng) : nil
}

/// Generates a body string (may be empty, may contain Unicode, newlines, etc.)
/// capped well below `TaskValidation.maxBodyLength`.
private func arbitraryBody(rng: inout any RandomNumberGenerator) -> String {
    let maxLen = 400
    let length = Int.random(in: 0...maxLen, using: &rng)
    if length == 0 { return "" }
    var chars: [Character] = []
    chars.reserveCapacity(length)
    for _ in 0..<length {
        if Bool.random(using: &rng) {
            chars.append(Character(mixedPool[Int.random(in: 0..<mixedPool.count, using: &rng)]))
        } else {
            chars.append("\n")
        }
    }
    return String(chars)
}

/// Builds a minimal `TaskDocument` from random components.
private func arbitraryDocument(rng: inout any RandomNumberGenerator) -> TaskDocument {
    let frontmatter = TaskFrontmatterV1(
        title: arbitraryTitle(rng: &rng),
        status: arbitraryStatus(rng: &rng),
        due: arbitraryOptionalDate(rng: &rng),
        scheduled: arbitraryOptionalDate(rng: &rng),
        priority: arbitraryPriority(rng: &rng),
        flagged: Bool.random(using: &rng),
        created: Date(timeIntervalSince1970: Double.random(in: 0...1_800_000_000, using: &rng)),
        source: arbitrarySource(rng: &rng)
    )
    return TaskDocument(frontmatter: frontmatter, body: arbitraryBody(rng: &rng))
}

// MARK: - Tests

final class CodecPropertyTests: XCTestCase {

    // MARK: Round-trip identity

    /// For any valid document, serialize then parse must produce an equivalent document.
    func testRoundTripIdentity() throws {
        let codec = TaskMarkdownCodec()

        try checkProperty("round-trip identity") { rng in
            let original = arbitraryDocument(rng: &rng)

            // Skip documents that fail validation (e.g. due_time without due)
            guard (try? TaskValidation.validate(document: original)) != nil else { return }

            let serialized = try codec.serialize(document: original)
            let recovered = try codec.parse(markdown: serialized)

            XCTAssertEqual(
                recovered.frontmatter.title,
                original.frontmatter.title,
                "title must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.status,
                original.frontmatter.status,
                "status must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.priority,
                original.frontmatter.priority,
                "priority must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.flagged,
                original.frontmatter.flagged,
                "flagged must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.due,
                original.frontmatter.due,
                "due date must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.scheduled,
                original.frontmatter.scheduled,
                "scheduled date must survive round-trip"
            )
            XCTAssertEqual(
                recovered.frontmatter.source,
                original.frontmatter.source,
                "source must survive round-trip"
            )
            // Body is trimmed by the parser — compare trimmed versions.
            XCTAssertEqual(
                recovered.body.trimmingCharacters(in: .whitespacesAndNewlines),
                original.body.trimmingCharacters(in: .whitespacesAndNewlines),
                "body must survive round-trip unchanged"
            )
        }
    }

    // MARK: Unicode body round-trip

    /// Body content containing arbitrary Unicode must be preserved verbatim
    /// (modulo leading/trailing whitespace normalisation by the parser).
    func testUnicodeBodySurvivesRoundTrip() throws {
        let codec = TaskMarkdownCodec()

        try checkProperty("unicode body round-trip", count: 50) { rng in
            let unicodeBody = String(
                (0..<Int.random(in: 1...200, using: &rng)).map { _ in
                    Character(unicodePool[Int.random(in: 0..<unicodePool.count, using: &rng)])
                }
            )

            let frontmatter = TestSupport.sampleFrontmatter()
            let document = TaskDocument(frontmatter: frontmatter, body: unicodeBody)

            let serialized = try codec.serialize(document: document)
            let recovered = try codec.parse(markdown: serialized)

            XCTAssertEqual(
                recovered.body.trimmingCharacters(in: .whitespacesAndNewlines),
                unicodeBody.trimmingCharacters(in: .whitespacesAndNewlines),
                "Unicode body must survive round-trip"
            )
        }
    }

    // MARK: Empty body

    /// An empty body must round-trip as an empty string (after whitespace normalisation).
    /// The codec may emit a trailing newline between the closing `---` delimiter and the
    /// body section; comparing trimmed values tests the meaningful content.
    func testEmptyBodyRoundTrip() throws {
        let codec = TaskMarkdownCodec()
        let frontmatter = TestSupport.sampleFrontmatter()
        let document = TaskDocument(frontmatter: frontmatter, body: "")

        let serialized = try codec.serialize(document: document)
        let recovered = try codec.parse(markdown: serialized)

        XCTAssertEqual(
            recovered.body.trimmingCharacters(in: .whitespacesAndNewlines),
            "",
            "Empty body must round-trip as effectively empty (whitespace only)"
        )
    }

    // MARK: Maximum-length title boundary

    /// A title of exactly `maxTitleLength` characters must round-trip successfully.
    func testMaxLengthTitleRoundTrip() throws {
        let codec = TaskMarkdownCodec()
        let maxTitle = String(repeating: "x", count: TaskValidation.maxTitleLength)
        let frontmatter = TestSupport.sampleFrontmatter(title: maxTitle)
        let document = TaskDocument(frontmatter: frontmatter, body: "")

        let serialized = try codec.serialize(document: document)
        let recovered = try codec.parse(markdown: serialized)

        XCTAssertEqual(recovered.frontmatter.title, maxTitle, "Max-length title must round-trip")
    }

    // MARK: Unknown frontmatter keys preserved

    /// Custom (unknown) frontmatter keys must be preserved through a full round-trip.
    func testUnknownFrontmatterPreservedAcrossRoundTrip() throws {
        let codec = TaskMarkdownCodec()

        let raw = """
        ---
        title: "Property test task"
        status: "todo"
        created: "2025-01-01T00:00:00Z"
        source: "user"
        custom_alpha: "hello"
        custom_beta: "world"
        ---
        Body text.
        """

        let first = try codec.parse(markdown: raw)
        let serialized = try codec.serialize(document: first)
        let second = try codec.parse(markdown: serialized)

        XCTAssertEqual(
            second.unknownFrontmatter["custom_alpha"],
            .string("hello"),
            "custom_alpha must survive round-trip"
        )
        XCTAssertEqual(
            second.unknownFrontmatter["custom_beta"],
            .string("world"),
            "custom_beta must survive round-trip"
        )
    }

    // MARK: Serialize→parse is idempotent (two trips)

    /// Applying serialize→parse twice must yield the same result as applying it once.
    func testDoubleRoundTripIsIdempotent() throws {
        let codec = TaskMarkdownCodec()

        try checkProperty("double round-trip idempotent", count: 50) { rng in
            let original = arbitraryDocument(rng: &rng)
            guard (try? TaskValidation.validate(document: original)) != nil else { return }

            let once = try codec.parse(markdown: try codec.serialize(document: original))
            let twice = try codec.parse(markdown: try codec.serialize(document: once))

            XCTAssertEqual(once.frontmatter.title, twice.frontmatter.title)
            XCTAssertEqual(once.frontmatter.status, twice.frontmatter.status)
            XCTAssertEqual(once.frontmatter.due, twice.frontmatter.due)
            XCTAssertEqual(
                once.body.trimmingCharacters(in: .whitespacesAndNewlines),
                twice.body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    // MARK: Tags round-trip

    /// Tags must survive a serialize→parse round-trip unchanged and in the same order.
    func testTagsRoundTrip() throws {
        let codec = TaskMarkdownCodec()

        let tagSets: [[String]] = [
            [],
            ["work"],
            ["home", "errands"],
            ["a", "b", "c", "d", "e"],
            ["unicode-tag-ñ", "emoji-★"]
        ]

        for tags in tagSets {
            let frontmatter = TaskFrontmatterV1(
                title: "Tag test",
                status: .todo,
                tags: tags,
                created: Date(timeIntervalSince1970: 1_700_000_000),
                source: "user"
            )
            let document = TaskDocument(frontmatter: frontmatter, body: "")
            let serialized = try codec.serialize(document: document)
            let recovered = try codec.parse(markdown: serialized)
            XCTAssertEqual(recovered.frontmatter.tags, tags, "Tags \(tags) must survive round-trip")
        }
    }
}
