import Foundation
import Testing
@testable import TodoMDApp

struct TodayTabViewTests {
    @Test("Descriptor shows empty Today state with calendar card when there are no records")
    func descriptorShowsEmptyTodayState() {
        let descriptor = TodayTabDescriptor.make(
            records: [],
            sections: [],
            showsCalendarCard: true,
            showsInlineComposer: false,
            isEditing: false
        )

        #expect(descriptor.listID == "\(BuiltInView.today.rawValue)-empty")
        #expect(descriptor.layoutRows == [
            .hero,
            .calendarCard,
            .emptyState(.generic)
        ])
    }

    @Test("Descriptor keeps empty inline Today ordering with composer before calendar")
    func descriptorKeepsEmptyInlineTodayOrdering() {
        let descriptor = TodayTabDescriptor.make(
            records: [],
            sections: [],
            showsCalendarCard: true,
            showsInlineComposer: true,
            isEditing: false
        )

        #expect(descriptor.listID == "\(BuiltInView.today.rawValue)-inline-empty")
        #expect(descriptor.layoutRows == [
            .hero,
            .inlineComposer,
            .calendarCard
        ])
    }

    @Test("Root-state descriptor keeps calendar-backed empty Today state in edit mode when calendar is connected")
    func rootStateDescriptorKeepsCalendarForEmptyTodayInEditMode() {
        let descriptor = TodayTabDescriptor.makeForRootState(
            records: [],
            sections: [],
            isCalendarConnected: true,
            showsInlineComposer: false,
            isEditing: true
        )

        #expect(descriptor.listID == "\(BuiltInView.today.rawValue)-empty")
        #expect(descriptor.layoutRows == [
            .hero,
            .calendarCard,
            .emptyState(.generic)
        ])
    }

    @Test("Descriptor keeps sectioned Today ordering when not editing")
    func descriptorKeepsSectionedTodayOrdering() {
        let overdue = makeRecord(title: "Overdue", path: "/tmp/today-overdue.md")
        let scheduled = makeRecord(title: "Scheduled", path: "/tmp/today-scheduled.md")
        let descriptor = TodayTabDescriptor.make(
            records: [overdue, scheduled],
            sections: [
                TodaySection(group: .overdue, records: [overdue]),
                TodaySection(group: .scheduled, records: [scheduled])
            ],
            showsCalendarCard: true,
            showsInlineComposer: true,
            isEditing: false
        )

        #expect(descriptor.listID == BuiltInView.today.rawValue)
        #expect(descriptor.layoutRows == [
            .hero,
            .calendarCard,
            .inlineComposer,
            .section(TodaySection(group: .overdue, records: [overdue])),
            .section(TodaySection(group: .scheduled, records: [scheduled]))
        ])
    }

    @Test("Descriptor switches Today to editable rows in edit mode")
    func descriptorUsesEditableRowsInEditMode() {
        let record = makeRecord(title: "Editable", path: "/tmp/today-edit.md")
        let descriptor = TodayTabDescriptor.make(
            records: [record],
            sections: [TodaySection(group: .scheduled, records: [record])],
            showsCalendarCard: true,
            showsInlineComposer: true,
            isEditing: true
        )

        #expect(descriptor.listID == BuiltInView.today.rawValue)
        #expect(descriptor.layoutRows == [
            .hero,
            .inlineComposer,
            .editableRows([record])
        ])
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
