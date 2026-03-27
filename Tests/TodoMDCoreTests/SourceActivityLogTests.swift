import XCTest
@testable import TodoMDCore

final class SourceActivityLogTests: XCTestCase {
    func testRecordGroupsSameSourceAndActionWithinFiveMinutes() throws {
        var log = SourceActivityLog(maximumEntryCount: 10, groupingWindow: 300)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        log.record([
            SourceActivityEvent(action: .created, source: "claude-agent", subject: "Buy milk", timestamp: now),
            SourceActivityEvent(action: .created, source: "claude-agent", subject: "Call dentist", timestamp: now.addingTimeInterval(120)),
            SourceActivityEvent(action: .created, source: "cli", subject: "Review PR", timestamp: now.addingTimeInterval(180)),
        ])

        let claudeEntry = try XCTUnwrap(log.recentEntries().first(where: { $0.source == "claude-agent" }))
        XCTAssertEqual(claudeEntry.action, .created)
        XCTAssertEqual(claudeEntry.subjects, ["Buy milk", "Call dentist"])
        XCTAssertEqual(claudeEntry.itemCount, 2)
        XCTAssertEqual(log.recentEntries().count, 2)
    }

    func testEventsOutsideGroupingWindowAreNotGrouped() {
        var log = SourceActivityLog(maximumEntryCount: 10, groupingWindow: 300)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        log.record([
            SourceActivityEvent(action: .created, source: "cli", subject: "Task 1", timestamp: now),
            SourceActivityEvent(action: .created, source: "cli", subject: "Task 2", timestamp: now.addingTimeInterval(360)),
        ])

        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.subjects), [["Task 2"], ["Task 1"]])
    }

    func testRecordCapsRetainedHistoryToMaximumEntryCount() {
        var log = SourceActivityLog(maximumEntryCount: 2, groupingWindow: 300)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        log.record([
            SourceActivityEvent(action: .created, source: "source-a", subject: "A", timestamp: now),
            SourceActivityEvent(action: .modified, source: "source-b", subject: "B", timestamp: now.addingTimeInterval(10)),
            SourceActivityEvent(action: .deleted, source: "source-c", subject: "C", timestamp: now.addingTimeInterval(20)),
        ])

        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.source), ["source-c", "source-b"])
    }

    func testRecordFromFileWatcherEventsSuppressesBurstDuplicatesAndPreservesTitles() {
        var log = SourceActivityLog(maximumEntryCount: 10, groupingWindow: 300)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let firstPath = "/tmp/a.md"
        let secondPath = "/tmp/b.md"

        let upsertedRecords = [
            makeRecord(path: firstPath, title: "Buy milk", source: "claude-agent"),
            makeRecord(path: secondPath, title: "Call dentist", source: "claude-agent"),
        ]
        let upsertedByPath = Dictionary(uniqueKeysWithValues: upsertedRecords.map { ($0.identity.path, $0) })

        log.record(
            fileWatcherEvents: [
                .created(path: firstPath, source: "claude-agent", timestamp: now),
                .created(path: secondPath, source: "claude-agent", timestamp: now),
                .rateLimitedBatch(paths: [firstPath, secondPath], source: "claude-agent", timestamp: now),
            ],
            upsertedRecordsByPath: upsertedByPath,
            existingRecordsByPath: [:]
        )

        let entries = log.recentEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].source, "claude-agent")
        XCTAssertEqual(entries[0].action, .created)
        XCTAssertEqual(entries[0].subjects, ["Buy milk", "Call dentist"])
        XCTAssertEqual(entries[0].itemCount, 2)
    }

    private func makeRecord(path: String, title: String, source: String) -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            source: source
        )
        return TaskRecord(identity: TaskFileIdentity(path: path), document: TaskDocument(frontmatter: frontmatter, body: ""))
    }
}
