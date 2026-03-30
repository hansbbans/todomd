import Foundation
import Testing
@testable import TodoMDApp

struct AreasTabViewTests {
    @Test("Descriptor shows generic empty state when an area list is empty")
    func descriptorShowsGenericEmptyState() {
        let descriptor = AreasTabDescriptor.make(
            view: .area("Work"),
            records: [],
            showsInlineComposer: false
        )

        #expect(descriptor.listID == "area:Work-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer == false)
        #expect(descriptor.emptyState == .generic)
    }

    @Test("Descriptor keeps inline composer state for an empty project list")
    func descriptorKeepsInlineComposerState() {
        let descriptor = AreasTabDescriptor.make(
            view: .project("TL"),
            records: [],
            showsInlineComposer: true
        )

        #expect(descriptor.listID == "project:TL-inline-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer)
        #expect(descriptor.emptyState == nil)
    }

    @Test("Descriptor keeps populated tag list identity and task order")
    func descriptorKeepsPopulatedTaskOrder() {
        let first = makeRecord(title: "Alpha", path: "/tmp/tag-alpha.md")
        let second = makeRecord(title: "Beta", path: "/tmp/tag-beta.md")

        let descriptor = AreasTabDescriptor.make(
            view: .tag("errands"),
            records: [first, second],
            showsInlineComposer: false
        )

        #expect(descriptor.listID == "tag:errands")
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
