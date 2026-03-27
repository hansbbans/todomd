import Foundation
import Testing
import TodoMDCore
@testable import TodoMDCLI

struct ValidateCommandTests {
    @Test("Single valid file is counted as valid")
    func validFilePasses() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "valid-file")
        defer { try? fileManager.removeItem(at: root) }

        let validURL = root.appendingPathComponent("task.md")
        try """
        ---
        title: "Buy milk"
        status: todo
        priority: none
        flagged: false
        created: "2026-03-26T12:00:00.000Z"
        source: cli-test
        ---
        Body
        """.write(to: validURL, atomically: true, encoding: .utf8)

        let summary = ValidationService().validate(inputs: [validURL.path])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 1)
        #expect(summary.invalidCount == 0)
        #expect(summary.results.count == 1)
        #expect(summary.results[0].path == validURL.path)
        #expect(summary.results[0].outcome == .valid)
    }

    @Test("Single invalid file is reported as invalid")
    func invalidFileFails() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "invalid-file")
        defer { try? fileManager.removeItem(at: root) }

        let invalidURL = root.appendingPathComponent("bad.md")
        try "not yaml at all".write(to: invalidURL, atomically: true, encoding: .utf8)

        let summary = ValidationService().validate(inputs: [invalidURL.path])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 0)
        #expect(summary.invalidCount == 1)
        #expect(summary.results[0].path == invalidURL.path)
        #expect(summary.results[0].outcome == .invalid)
        #expect(summary.results[0].message?.contains("frontmatter") == true)
    }

    @Test("Parsed but semantically invalid tasks still fail validation")
    func semanticallyInvalidFileFails() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "semantic-invalid-file")
        defer { try? fileManager.removeItem(at: root) }

        let invalidURL = root.appendingPathComponent("bad-fields.md")
        try """
        ---
        title: "Bad fields"
        status: todo
        priority: none
        flagged: false
        due_time: "09:00"
        created: "2026-03-26T12:00:00.000Z"
        source: cli-test
        ---
        """.write(to: invalidURL, atomically: true, encoding: .utf8)

        let summary = ValidationService().validate(inputs: [invalidURL.path])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 0)
        #expect(summary.invalidCount == 1)
        #expect(summary.results[0].outcome == .invalid)
        #expect(summary.results[0].message?.contains("due_time") == true)
    }

    @Test("Validation reads file contents through the injected file IO path")
    func validationUsesConfiguredReadPath() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "read-path")
        defer { try? fileManager.removeItem(at: root) }

        let taskURL = root.appendingPathComponent("task.md")
        try "".write(to: taskURL, atomically: true, encoding: .utf8)

        let expectedContent = """
        ---
        title: "Read via file IO"
        status: todo
        priority: none
        flagged: false
        created: "2026-03-26T12:00:00.000Z"
        source: cli-test
        ---
        """

        var readPaths: [String] = []
        let service = ValidationService(
            readFile: { path in
                readPaths.append(path)
                return expectedContent
            }
        )

        let summary = service.validate(inputs: [taskURL.path])

        #expect(readPaths == [taskURL.path])
        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 1)
        #expect(summary.invalidCount == 0)
    }

    @Test("Validation enforces task rules after parsing")
    func validationAppliesTaskValidationAfterParsing() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "post-parse-validation")
        defer { try? fileManager.removeItem(at: root) }

        let taskURL = root.appendingPathComponent("task.md")
        try "".write(to: taskURL, atomically: true, encoding: .utf8)

        let invalidDocument = TaskDocument(
            frontmatter: TaskFrontmatterV1(
                title: "Invalid task",
                status: .todo,
                dueTime: try LocalTime(isoTime: "08:30"),
                created: Date(),
                source: "cli-test"
            ),
            body: ""
        )

        let service = ValidationService(
            parseDocument: { _, _ in invalidDocument }
        )

        let summary = service.validate(inputs: [taskURL.path])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 0)
        #expect(summary.invalidCount == 1)
        #expect(summary.results[0].outcome == ValidationOutcome.invalid)
        #expect(summary.results[0].message?.contains("due_time") == true)
    }

    @Test("Directory input recurses and ignores AGENTS files")
    func directoryInputRecursesUsingCoreRules() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "directory-input")
        defer { try? fileManager.removeItem(at: root) }

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)

        let validURL = nested.appendingPathComponent("task.md")
        try """
        ---
        title: "Nested task"
        status: todo
        priority: none
        flagged: false
        created: "2026-03-26T12:00:00.000Z"
        source: cli-test
        ---
        """.write(to: validURL, atomically: true, encoding: .utf8)

        let agentsURL = root.appendingPathComponent("AGENTS.md")
        try "# Not a task".write(to: agentsURL, atomically: true, encoding: .utf8)

        let summary = ValidationService().validate(inputs: [root.path])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 1)
        #expect(summary.invalidCount == 0)
        #expect(summary.results.map(\.path) == [validURL.path])
    }

    @Test("Explicit AGENTS file input is ignored like directory scans ignore it")
    func explicitAgentsFileIsIgnored() throws {
        let fileManager = FileManager.default
        let root = try tempDirectory(named: "explicit-agents")
        defer { try? fileManager.removeItem(at: root) }

        let agentsURL = root.appendingPathComponent("AGENTS.md")
        try "# Not a task".write(to: agentsURL, atomically: true, encoding: .utf8)

        let summary = ValidationService().validate(inputs: [agentsURL.path])

        #expect(summary.checkedCount == 0)
        #expect(summary.validCount == 0)
        #expect(summary.invalidCount == 0)
        #expect(summary.results.isEmpty)
    }

    @Test("Formatter omits success lines unless verbose")
    func formatterHonorsVerboseFlag() {
        let summary = ValidationSummary(
            results: [
                .init(path: "/tmp/good.md", outcome: .valid, message: nil),
                .init(path: "/tmp/bad.md", outcome: .invalid, message: "Bad file")
            ]
        )

        let quietLines = ValidationOutputFormatter.makeLines(for: summary, verbose: false)
        let verboseLines = ValidationOutputFormatter.makeLines(for: summary, verbose: true)

        #expect(quietLines.contains("FAIL  /tmp/bad.md"))
        #expect(quietLines.contains("  OK  /tmp/good.md") == false)
        #expect(verboseLines.contains("FAIL  /tmp/bad.md"))
        #expect(verboseLines.contains("  OK  /tmp/good.md"))
    }

    @Test("Missing input path is reported as invalid")
    func missingPathFails() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-missing-\(UUID().uuidString).md")
            .path

        let summary = ValidationService().validate(inputs: [missingPath])

        #expect(summary.checkedCount == 1)
        #expect(summary.validCount == 0)
        #expect(summary.invalidCount == 1)
        #expect(summary.results[0].path == missingPath)
        #expect(summary.results[0].outcome == .invalid)
        #expect(summary.results[0].message == "Path does not exist")
    }

    @Test("Validate command requires at least one path before running")
    func validateCommandRequiresInputPaths() {
        #expect(throws: Error.self) {
            try ValidateCommand.validateInputPaths([])
        }
    }

    private func tempDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
