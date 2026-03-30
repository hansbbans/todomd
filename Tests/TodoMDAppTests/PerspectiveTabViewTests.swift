import Foundation
import Testing
@testable import TodoMDApp

struct PerspectiveTabViewTests {
    @Test("Descriptor shows generic empty state when a perspective is empty")
    func descriptorShowsGenericEmptyState() {
        let descriptor = PerspectiveTabDescriptor.make(
            view: .custom("perspective:focus"),
            records: [],
            showsInlineComposer: false
        )

        #expect(descriptor.listID == "perspective:focus-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer == false)
        #expect(descriptor.emptyState == .generic)
    }

    @Test("Descriptor keeps inline composer state for an empty perspective")
    func descriptorKeepsInlineComposerState() {
        let descriptor = PerspectiveTabDescriptor.make(
            view: .custom("perspective:deep-work"),
            records: [],
            showsInlineComposer: true
        )

        #expect(descriptor.listID == "perspective:deep-work-inline-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer)
        #expect(descriptor.emptyState == nil)
    }

    @Test("Descriptor keeps populated perspective list identity and task order")
    func descriptorKeepsPopulatedTaskOrder() {
        let first = makeRecord(title: "Alpha", path: "/tmp/perspective-alpha.md")
        let second = makeRecord(title: "Beta", path: "/tmp/perspective-beta.md")

        let descriptor = PerspectiveTabDescriptor.make(
            view: .custom("perspective:focus"),
            records: [first, second],
            showsInlineComposer: false
        )

        #expect(descriptor.listID == "perspective:focus")
        #expect(descriptor.taskRecordPaths == [first.identity.path, second.identity.path])
        #expect(descriptor.emptyState == nil)
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
