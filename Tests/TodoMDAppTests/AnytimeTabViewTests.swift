import Foundation
import Testing
@testable import TodoMDApp

struct AnytimeTabViewTests {
    @Test("Descriptor keeps anytime list identity and task order")
    func descriptorKeepsAnytimeListIdentityAndTaskOrder() {
        let descriptor = AnytimeTabDescriptor.make(records: [
            makeRecord(title: "First", path: "/tmp/first.md"),
            makeRecord(title: "Second", path: "/tmp/second.md")
        ])

        #expect(descriptor.listID == BuiltInView.anytime.rawValue)
        #expect(descriptor.taskRecordPaths == ["/tmp/first.md", "/tmp/second.md"])
        #expect(descriptor.emptyState == nil)
    }

    @Test("Descriptor shows generic empty state copy when anytime is empty")
    func descriptorShowsGenericEmptyStateWhenAnytimeIsEmpty() {
        let descriptor = AnytimeTabDescriptor.make(records: [])

        #expect(descriptor.listID == "\(BuiltInView.anytime.rawValue)-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(
            descriptor.emptyState == AnytimeTabEmptyState(
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
