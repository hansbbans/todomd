import Foundation
import Testing
@testable import TodoMDApp

struct LogbookTabViewTests {
    @Test("Descriptor shows generic empty state when logbook has no records")
    func descriptorShowsGenericEmptyStateWhenLogbookIsEmpty() {
        let descriptor = LogbookTabDescriptor.make(records: [], filteredRecords: [])

        #expect(descriptor.listID == "\(BuiltInView.logbook.rawValue)-empty")
        #expect(descriptor.filteredRecordPaths.isEmpty)
        #expect(descriptor.state == .genericEmpty)
        #expect(descriptor.searchEmptyState == nil)
    }

    @Test("Descriptor shows search-empty state when logbook query matches nothing")
    func descriptorShowsSearchEmptyStateWhenQueryMatchesNothing() {
        let descriptor = LogbookTabDescriptor.make(
            records: [
                makeRecord(title: "Completed", path: "/tmp/logbook-first.md"),
                makeRecord(title: "Cancelled", path: "/tmp/logbook-second.md")
            ],
            filteredRecords: []
        )

        #expect(descriptor.listID == "\(BuiltInView.logbook.rawValue)-search-empty")
        #expect(descriptor.filteredRecordPaths.isEmpty)
        #expect(descriptor.state == .searchEmpty)
        #expect(
            descriptor.searchEmptyState == LogbookSearchEmptyState(
                title: "No logbook matches",
                symbol: "magnifyingglass",
                subtitle: "Try a broader search or filters like project:, tag:, status:, before:, or after:.",
                exampleQuery: "Examples: `project:Work`, `tag:errands`, `status:cancelled`, `before:2026-03-01`"
            )
        )
    }

    @Test("Descriptor keeps populated logbook list identity and filtered task order")
    func descriptorKeepsPopulatedLogbookStructure() {
        let record = makeRecord(title: "Completed", path: "/tmp/logbook-second.md")
        let descriptor = LogbookTabDescriptor.make(
            records: [
                makeRecord(title: "Archived", path: "/tmp/logbook-first.md"),
                record
            ],
            filteredRecords: [record]
        )

        #expect(descriptor.listID == BuiltInView.logbook.rawValue)
        #expect(descriptor.filteredRecordPaths == ["/tmp/logbook-second.md"])
        #expect(descriptor.state == .populated)
        #expect(descriptor.searchEmptyState == nil)
    }

    private func makeRecord(title: String, path: String) -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .done,
            priority: .none,
            flagged: false,
            created: Date(timeIntervalSince1970: 1_700_000_000),
            modified: Date(timeIntervalSince1970: 1_700_000_000),
            source: "test"
        )

        return TaskRecord(
            identity: TaskFileIdentity(path: path),
            document: TaskDocument(frontmatter: frontmatter, body: "")
        )
    }
}
