import Foundation
import Testing
@testable import TodoMDApp

struct SomedayTabViewTests {
    @Test("Descriptor keeps someday list identity and task order")
    func descriptorKeepsSomedayListIdentityAndTaskOrder() {
        let descriptor = SomedayTabDescriptor.make(records: [
            makeRecord(title: "First", path: "/tmp/someday-first.md"),
            makeRecord(title: "Second", path: "/tmp/someday-second.md")
        ])

        #expect(descriptor.listID == BuiltInView.someday.rawValue)
        #expect(descriptor.taskRecordPaths == ["/tmp/someday-first.md", "/tmp/someday-second.md"])
        #expect(descriptor.emptyState == nil)
    }

    @Test("Descriptor shows generic empty state copy when someday is empty")
    func descriptorShowsGenericEmptyStateWhenSomedayIsEmpty() {
        let descriptor = SomedayTabDescriptor.make(records: [])

        #expect(descriptor.listID == "\(BuiltInView.someday.rawValue)-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(
            descriptor.emptyState == SomedayTabEmptyState(
                title: "Nothing here",
                symbol: "checkmark.circle",
                subtitle: "Tap + to add a task."
            )
        )
    }

    private func makeRecord(title: String, path: String) -> TaskRecord {
        let frontmatter = TaskFrontmatterV1(
            title: title,
            status: .todo,
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
