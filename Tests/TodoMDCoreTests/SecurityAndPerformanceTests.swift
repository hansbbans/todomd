import XCTest
@testable import TodoMDCore

final class SecurityAndPerformanceTests: XCTestCase {
    func testFiftyMegabyteBodyRejectedSafely() {
        let frontmatter = TestSupport.sampleFrontmatter()
        let body = String(repeating: "x", count: 50 * 1024 * 1024)
        let document = TaskDocument(frontmatter: frontmatter, body: body)

        XCTAssertThrowsError(try TaskValidation.validate(document: document)) { error in
            guard case TaskValidationError.fieldTooLong(let field, _) = error else {
                return XCTFail("Unexpected error for oversized body: \(error)")
            }
            XCTAssertEqual(field, "body")
        }
    }

    func testDeeplyNestedFrontmatterRejectedSafely() {
        var lines: [String] = [
            "---",
            "title: \"Deeply Nested\"",
            "status: \"todo\"",
            "created: \"2025-02-26T00:00:00Z\"",
            "source: \"external\"",
            "payload:"
        ]

        for depth in 0..<30 {
            let indent = String(repeating: "  ", count: depth + 1)
            lines.append("\(indent)level_\(depth):")
        }

        lines.append("\(String(repeating: "  ", count: 31))leaf: \"end\"")
        lines.append("---")
        lines.append("body")

        let markdown = lines.joined(separator: "\n")
        let codec = TaskMarkdownCodec()
        XCTAssertThrowsError(try codec.parse(markdown: markdown))
    }

    func testColdSync500FilesStaysWithinPerformanceBudget() throws {
        let root = try TestSupport.tempDirectory(prefix: "PerfCold")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)

        _ = try createTasks(count: 500, repository: repository)

        let start = Date()
        _ = try watcher.synchronize(now: start)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 3.0, "Cold sync for 500 files exceeded budget: \(elapsed)s")
    }

    func testIncrementalSyncTenFilesStaysWithinPerformanceBudget() throws {
        let root = try TestSupport.tempDirectory(prefix: "PerfIncremental")
        let repository = FileTaskRepository(rootURL: root)
        let watcher = FileWatcherService(rootURL: root, repository: repository)

        let paths = try createTasks(count: 500, repository: repository)
        _ = try watcher.synchronize(now: Date())

        for path in paths.prefix(10) {
            _ = try repository.update(path: path) { document in
                document.frontmatter.title = "\(document.frontmatter.title) updated"
                document.frontmatter.modified = Date()
            }
        }

        let start = Date()
        _ = try watcher.synchronize(now: start.addingTimeInterval(1))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 1.0, "Incremental sync for 10 files exceeded budget: \(elapsed)s")
    }

    private func createTasks(count: Int, repository: FileTaskRepository) throws -> [String] {
        var paths: [String] = []
        paths.reserveCapacity(count)

        for index in 0..<count {
            var frontmatter = TestSupport.sampleFrontmatter(title: "Perf \(index)", source: "perf")
            frontmatter.modified = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            let record = try repository.create(
                document: TaskDocument(frontmatter: frontmatter, body: "body-\(index)"),
                preferredFilename: String(format: "perf-%04d.md", index)
            )
            paths.append(record.identity.path)
        }

        return paths
    }
}
