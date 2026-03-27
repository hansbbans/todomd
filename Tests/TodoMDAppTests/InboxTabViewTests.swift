import Foundation
import Testing
@testable import TodoMDApp

struct InboxTabViewTests {
    @Test("Descriptor shows inbox empty state when there are no records and no inline composer")
    func descriptorShowsInboxEmptyState() {
        let descriptor = InboxTabDescriptor.make(records: [], showsInlineComposer: false)

        #expect(descriptor.listID == "\(BuiltInView.inbox.rawValue)-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer == false)
        #expect(descriptor.contentOrder == [.hero, .importPanel, .emptyState])
        #expect(
            descriptor.emptyState == InboxTabEmptyState(
                title: "Inbox is clear",
                symbol: "tray.fill",
                subtitle: "New tasks land here first."
            )
        )
    }

    @Test("Descriptor keeps the inline composer state for an empty inbox")
    func descriptorKeepsInlineComposerStateForEmptyInbox() {
        let descriptor = InboxTabDescriptor.make(records: [], showsInlineComposer: true)

        #expect(descriptor.listID == "\(BuiltInView.inbox.rawValue)-inline-empty")
        #expect(descriptor.taskRecordPaths.isEmpty)
        #expect(descriptor.showsInlineComposer)
        #expect(descriptor.contentOrder == [.hero, .inlineComposer, .importPanel])
        #expect(descriptor.emptyState == nil)
    }

    @Test("Descriptor keeps inbox list identity and task order when populated")
    func descriptorKeepsInboxTaskOrder() {
        let descriptor = InboxTabDescriptor.make(
            records: [
                makeRecord(title: "First", path: "/tmp/inbox-first.md"),
                makeRecord(title: "Second", path: "/tmp/inbox-second.md")
            ],
            showsInlineComposer: true
        )

        #expect(descriptor.listID == BuiltInView.inbox.rawValue)
        #expect(descriptor.taskRecordPaths == ["/tmp/inbox-first.md", "/tmp/inbox-second.md"])
        #expect(descriptor.showsInlineComposer)
        #expect(descriptor.contentOrder == [.hero, .importPanel, .inlineComposer, .taskRows])
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
