import Foundation
import Testing
@testable import TodoMDApp

@Suite
@MainActor
struct TaskEditPresenterTests {
    @Test("makeEditState uses the stored reminder default and formats location fields")
    func makeEditStateUsesStoredReminderDefaultAndFormatsLocationFields() throws {
        let presenter = TaskEditPresenter(
            persistentReminderDefault: true,
            quickEntryParser: NaturalLanguageTaskParser(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let record = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/task.md"),
            document: TaskDocument(
                frontmatter: TaskFrontmatterV1(
                    ref: "t-abcd",
                    title: "Plan trip",
                    status: .todo,
                    due: try LocalDate(isoDate: "2026-03-20"),
                    dueTime: try LocalTime(isoTime: "08:30"),
                    priority: .medium,
                    flagged: true,
                    tags: ["travel", "packing"],
                    locationReminder: .init(
                        name: "Airport",
                        latitude: 40.7128,
                        longitude: -74.0060,
                        radiusMeters: 150,
                        trigger: .onDeparture
                    ),
                    created: Date(timeIntervalSince1970: 1_700_000_000),
                    modified: Date(timeIntervalSince1970: 1_700_000_500),
                    source: "user"
                ),
                body: "Notes"
            )
        )

        let editState = presenter.makeEditState(record: record)

        #expect(editState.ref == "t-abcd")
        #expect(editState.title == "Plan trip")
        #expect(editState.hasDue)
        #expect(editState.hasDueTime)
        #expect(editState.persistentReminderEnabled)
        #expect(editState.tagsText == "travel, packing")
        #expect(editState.hasLocationReminder)
        #expect(editState.locationName == "Airport")
        #expect(editState.locationLatitude == "40.712800")
        #expect(editState.locationLongitude == "-74.006000")
        #expect(editState.locationRadiusMeters == 150)
        #expect(editState.locationTrigger == TaskLocationReminderTrigger.onDeparture)
    }

    @Test("resolvedEditState keeps the edited title while applying a parsed due date")
    func resolvedEditStateAppliesParsedDueDate() throws {
        let presenter = TaskEditPresenter(
            persistentReminderDefault: false,
            quickEntryParser: NaturalLanguageTaskParser(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let currentRecord = TaskRecord(
            identity: TaskFileIdentity(path: "/tmp/task.md"),
            document: TaskDocument(
                frontmatter: TaskFrontmatterV1(
                    title: "Buy gum",
                    status: .todo,
                    priority: .none,
                    flagged: false,
                    created: Date(timeIntervalSince1970: 1_700_000_000),
                    source: "user"
                ),
                body: ""
            )
        )
        var editState = presenter.makeEditState(record: currentRecord)
        editState.title = "Buy gum due on march 20 2026"

        let resolved = presenter.resolvedEditState(editState, for: currentRecord)

        #expect(resolved.title == "Buy gum due on march 20 2026")
        #expect(resolved.hasDue)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: resolved.dueDate).year == 2026)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: resolved.dueDate).month == 3)
        #expect(Calendar.current.dateComponents([.year, .month, .day], from: resolved.dueDate).day == 20)
    }

    @Test("apply trims fields, parses refs and sets completion metadata when status closes")
    func applySetsCompletionMetadataAndNormalizesFields() throws {
        let completionDate = Date(timeIntervalSince1970: 1_800_000_000)
        let presenter = TaskEditPresenter(
            persistentReminderDefault: false,
            quickEntryParser: NaturalLanguageTaskParser(),
            now: { completionDate }
        )
        var document = TaskDocument(
            frontmatter: TaskFrontmatterV1(
                title: "Old title",
                status: .todo,
                priority: .none,
                flagged: false,
                created: Date(timeIntervalSince1970: 1_700_000_000),
                source: "user"
            ),
            body: ""
        )
        let editState = TaskEditState(
            ref: "  ",
            title: "  Updated title  ",
            subtitle: "  Short note  ",
            status: .done,
            flagged: true,
            priority: .high,
            assignee: "  Hans  ",
            blockedByManual: false,
            blockedByRefsText: " t-abcd, t-beef ",
            completedBy: "",
            hasDue: true,
            dueDate: try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 2))),
            hasDueTime: true,
            dueTime: try #require(Calendar.current.date(from: DateComponents(hour: 9, minute: 45))),
            persistentReminderEnabled: true,
            hasDefer: false,
            deferDate: Date(timeIntervalSince1970: 0),
            hasScheduled: true,
            scheduledDate: try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 1))),
            hasScheduledTime: true,
            scheduledTime: try #require(Calendar.current.date(from: DateComponents(hour: 13, minute: 15))),
            hasEstimatedMinutes: true,
            estimatedMinutes: 30,
            area: "  Work  ",
            project: "  Launch  ",
            tagsText: " ops, ship ",
            recurrence: "  FREQ=WEEKLY  ",
            body: "Updated body",
            hasLocationReminder: true,
            locationName: "  Office  ",
            locationLatitude: "40.0",
            locationLongitude: "-73.0",
            locationRadiusMeters: 25,
            locationTrigger: .onArrival,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            modifiedAt: nil,
            completedAt: nil,
            source: "user"
        )

        presenter.apply(editState: editState, to: &document)

        #expect(document.frontmatter.ref == nil)
        #expect(document.frontmatter.title == "Updated title")
        #expect(document.frontmatter.description == "Short note")
        #expect(document.frontmatter.status == .done)
        #expect(document.frontmatter.flagged)
        #expect(document.frontmatter.priority == .high)
        #expect(document.frontmatter.assignee == "Hans")
        #expect(document.frontmatter.blockedBy == .refs(["t-abcd", "t-beef"]))
        #expect(document.frontmatter.due?.isoString == "2026-04-02")
        #expect(document.frontmatter.dueTime?.isoString == "09:45")
        #expect(document.frontmatter.persistentReminder == true)
        #expect(document.frontmatter.scheduled?.isoString == "2026-04-01")
        #expect(document.frontmatter.scheduledTime?.isoString == "13:15")
        #expect(document.frontmatter.estimatedMinutes == 30)
        #expect(document.frontmatter.area == "Work")
        #expect(document.frontmatter.project == "Launch")
        #expect(document.frontmatter.tags == ["ops", "ship"])
        #expect(document.frontmatter.recurrence == "FREQ=WEEKLY")
        #expect(document.frontmatter.locationReminder?.name == "Office")
        #expect(document.frontmatter.locationReminder?.radiusMeters == 50)
        #expect(document.frontmatter.completed == completionDate)
        #expect(document.frontmatter.completedBy == "user")
        #expect(document.body == "Updated body")
    }

    @Test("duplicatedTaskDocument clears scheduling and completion fields but keeps other content")
    func duplicatedTaskDocumentClearsScheduledFields() throws {
        let presenter = TaskEditPresenter(
            persistentReminderDefault: false,
            quickEntryParser: NaturalLanguageTaskParser(),
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let source = TaskDocument(
            frontmatter: TaskFrontmatterV1(
                ref: "t-abcd",
                title: "Renew passport",
                status: .done,
                due: try LocalDate(isoDate: "2026-03-20"),
                dueTime: try LocalTime(isoTime: "08:30"),
                persistentReminder: true,
                defer: try LocalDate(isoDate: "2026-03-21"),
                scheduled: try LocalDate(isoDate: "2026-03-22"),
                scheduledTime: try LocalTime(isoTime: "19:15"),
                priority: .high,
                flagged: true,
                tags: ["travel"],
                recurrence: "FREQ=WEEKLY",
                created: Date(timeIntervalSince1970: 1_700_000_000),
                modified: Date(timeIntervalSince1970: 1_700_000_500),
                completed: Date(timeIntervalSince1970: 1_700_001_000),
                completedBy: "user",
                source: "user"
            ),
            body: "Body",
            unknownFrontmatter: ["custom": .string("keep")]
        )
        let duplicationDate = Date(timeIntervalSince1970: 1_800_000_000)

        let duplicate = presenter.duplicatedTaskDocument(from: source, now: duplicationDate)

        #expect(duplicate.frontmatter.ref == nil)
        #expect(duplicate.frontmatter.title == "Renew passport")
        #expect(duplicate.frontmatter.status == TaskStatus.todo)
        #expect(duplicate.frontmatter.due == nil)
        #expect(duplicate.frontmatter.dueTime == nil)
        #expect(duplicate.frontmatter.persistentReminder == nil)
        #expect(duplicate.frontmatter.defer == nil)
        #expect(duplicate.frontmatter.scheduled == nil)
        #expect(duplicate.frontmatter.scheduledTime == nil)
        #expect(duplicate.frontmatter.recurrence == nil)
        #expect(duplicate.frontmatter.completed == nil)
        #expect(duplicate.frontmatter.completedBy == nil)
        #expect(duplicate.frontmatter.created == duplicationDate)
        #expect(duplicate.frontmatter.modified == duplicationDate)
        #expect(duplicate.frontmatter.priority == .high)
        #expect(duplicate.body == "Body")
        #expect(duplicate.unknownFrontmatter["custom"] == YAMLValue.string("keep"))
    }
}
