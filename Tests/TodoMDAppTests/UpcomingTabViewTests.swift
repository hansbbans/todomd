import Foundation
import Testing
@testable import TodoMDApp

struct UpcomingTabViewTests {
    @Test("Root-state descriptor preserves Upcoming section order and content details")
    func rootStateDescriptorPreservesUpcomingSections() {
        let firstTask = makeRecord(title: "First", path: "/tmp/upcoming-first.md")
        let secondTask = makeRecord(title: "Second", path: "/tmp/upcoming-second.md")
        let firstEvent = makeEvent(id: "evt-1", title: "Standup", hour: 9)
        let secondEvent = makeAllDayEvent(id: "evt-2", title: "Review")
        let firstDate = Date(timeIntervalSince1970: 1_700_100_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_186_400)

        let descriptor = UpcomingTabDescriptor.makeForRootState(
            sections: [
                UpcomingAgendaSection(date: firstDate, events: [firstEvent], records: [firstTask]),
                UpcomingAgendaSection(date: secondDate, events: [secondEvent], records: [secondTask])
            ]
        )

        #expect(descriptor.listID == BuiltInView.upcoming.rawValue)
        #expect(descriptor.sections.count == 2)
        #expect(descriptor.sections.map(\.id) == [
            UpcomingAgendaSection(date: firstDate, events: [firstEvent], records: [firstTask]).id,
            UpcomingAgendaSection(date: secondDate, events: [secondEvent], records: [secondTask]).id
        ])
        #expect(descriptor.sections[0].records == [firstTask])
        #expect(descriptor.sections[1].records == [secondTask])
        #expect(descriptor.sections.map(\.taskRecordPaths) == [
            ["/tmp/upcoming-first.md"],
            ["/tmp/upcoming-second.md"]
        ])
        #expect(descriptor.sections.map(\.eventIDs) == [
            ["evt-1"],
            ["evt-2"]
        ])
        #expect(descriptor.sections[0].events.count == 1)
        #expect(descriptor.sections[0].events[0].title == "Standup")
        #expect(descriptor.sections[0].events[0].calendarColorHex == "#FF6600")
        #expect(descriptor.sections[0].events[0].isAllDay == false)
        #expect(descriptor.sections[0].events[0].timeText != nil)
        #expect(descriptor.sections[1].events == [
            UpcomingTabEventDescriptor(
                id: "evt-2",
                title: "Review",
                calendarColorHex: "#0066FF",
                isAllDay: true,
                timeText: nil
            )
        ])
    }

    @Test("Root-state descriptor keeps empty Upcoming days intact")
    func rootStateDescriptorKeepsEmptyUpcomingDays() {
        let date = Date(timeIntervalSince1970: 1_700_272_800)

        let descriptor = UpcomingTabDescriptor.makeForRootState(
            sections: [
                UpcomingAgendaSection(date: date, events: [], records: [])
            ]
        )

        #expect(descriptor.listID == BuiltInView.upcoming.rawValue)
        #expect(descriptor.sections.count == 1)
        #expect(
            descriptor.sections[0].dayNumberText
                == String(Calendar.current.component(.day, from: date))
        )
        #expect(descriptor.sections[0].taskRecordPaths.isEmpty)
        #expect(descriptor.sections[0].eventIDs.isEmpty)
        #expect(descriptor.sections[0].records.isEmpty)
        #expect(descriptor.sections[0].events.isEmpty)
        #expect(descriptor.sections[0].showsEmptyState)
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

    private func makeEvent(id: String, title: String, hour: Int) -> CalendarEventItem {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(hour * 3600))

        return CalendarEventItem(
            id: id,
            calendarID: "calendar-\(id)",
            calendarName: "Calendar \(id)",
            calendarColorHex: "#FF6600",
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            isAllDay: false
        )
    }

    private func makeAllDayEvent(id: String, title: String) -> CalendarEventItem {
        let startDate = Date(timeIntervalSince1970: 1_700_000_000)

        return CalendarEventItem(
            id: id,
            calendarID: "calendar-\(id)",
            calendarName: "Calendar \(id)",
            calendarColorHex: "#0066FF",
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            isAllDay: true
        )
    }
}
