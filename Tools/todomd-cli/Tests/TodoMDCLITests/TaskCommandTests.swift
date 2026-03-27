import Foundation
import Testing
import TodoMDCore
@testable import TodoMDCLI

struct TaskCommandTests {
    @Test("Add creates a task with provided fields and natural language due date")
    func addCreatesTaskWithNaturalLanguageDueDate() throws {
        let root = try tempDirectory(named: "add-natural-language")
        defer { try? FileManager.default.removeItem(at: root) }

        let now = fixedDate("2026-03-26T12:00:00.000Z")
        let service = makeService(defaultFolder: root, now: now)

        let result = try service.add(
            .init(
                title: "Buy milk",
                due: "tomorrow",
                project: "Errands",
                priority: "high",
                source: "cli-test",
                folder: root.path
            )
        )

        #expect(result.title == "Buy milk")
        #expect(result.ref.hasPrefix("t-"))
        #expect(AddOutputFormatter.makeLine(for: result) == "Created \(result.ref) Buy milk")

        let created = try parseTask(atPath: result.path)
        #expect(created.document.frontmatter.due?.isoString == "2026-03-27")
        #expect(created.document.frontmatter.project == "Errands")
        #expect(created.document.frontmatter.priority == .high)
        #expect(created.document.frontmatter.source == "cli-test")
    }

    @Test("Add uses TaskFolderLocator when folder is omitted")
    func addUsesDefaultFolderResolution() throws {
        let root = try tempDirectory(named: "add-default-folder")
        defer { try? FileManager.default.removeItem(at: root) }

        let now = fixedDate("2026-03-26T12:00:00.000Z")
        final class Counter: @unchecked Sendable {
            var count = 0
        }
        let counter = Counter()

        let service = TaskCLIService(
            environment: .init(
                fileManager: .default,
                calendar: fixedCalendar(),
                now: { now },
                resolveDefaultFolder: {
                    counter.count += 1
                    return root
                }
            )
        )

        let result = try service.add(.init(title: "Use default folder"))

        #expect(counter.count == 1)
        #expect(FileManager.default.fileExists(atPath: result.path))
    }

    @Test("List supports today inbox upcoming and all views with refs in output")
    func listSupportsCoreViews() throws {
        let root = try tempDirectory(named: "list-views")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTask(
            at: root.appendingPathComponent("today.md"),
            ref: "t-1000",
            title: "Today task",
            status: .todo,
            due: "2026-03-26",
            project: "Work"
        )
        try writeTask(
            at: root.appendingPathComponent("upcoming.md"),
            ref: "t-1001",
            title: "Upcoming task",
            status: .todo,
            due: "2026-03-28",
            project: "Work"
        )
        try writeTask(
            at: root.appendingPathComponent("inbox.md"),
            ref: "t-1002",
            title: "Inbox task",
            status: .todo
        )
        try writeTask(
            at: root.appendingPathComponent("done.md"),
            ref: "t-1003",
            title: "Done task",
            status: .done
        )

        let service = makeService(defaultFolder: root, now: fixedDate("2026-03-26T12:00:00.000Z"))

        let defaultToday = try service.list(.init(folder: root.path))
        let inbox = try service.list(.init(view: "inbox", folder: root.path))
        let upcoming = try service.list(.init(view: "upcoming", folder: root.path))
        let all = try service.list(.init(view: "all", folder: root.path))

        #expect(defaultToday.view == .today)
        #expect(defaultToday.tasks.map(\.ref) == ["t-1000"])
        #expect(inbox.tasks.map(\.ref) == ["t-1002"])
        #expect(upcoming.tasks.map(\.ref) == ["t-1001"])
        #expect(Set(all.tasks.map(\.ref)) == ["t-1000", "t-1001", "t-1002", "t-1003"])

        let todayLines = TaskListOutputFormatter.makeLines(for: defaultToday)
        #expect(todayLines.contains(where: { $0.contains("t-1000") && $0.contains("Today task") }))
    }

    @Test("List rejects a missing explicit folder path")
    func listRejectsMissingExplicitFolder() {
        let missingFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-missing-folder-\(UUID().uuidString)", isDirectory: true)

        let service = makeService(defaultFolder: missingFolder, now: fixedDate("2026-03-26T12:00:00.000Z"))

        do {
            _ = try service.list(.init(folder: missingFolder.path))
            Issue.record("Expected list to reject a missing folder path")
        } catch {
            #expect(error.localizedDescription.contains("Folder does not exist"))
        }
    }

    @Test("List fails when an explicit folder path does not exist")
    func listFailsForMissingExplicitFolder() throws {
        let missingFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-missing-list-\(UUID().uuidString)", isDirectory: true)
        let service = makeService(defaultFolder: missingFolder, now: fixedDate("2026-03-26T12:00:00.000Z"))

        do {
            _ = try service.list(.init(view: "today", folder: missingFolder.path))
            Issue.record("Expected list to fail for a missing explicit folder path")
        } catch {
            #expect(error.localizedDescription.contains("does not exist"))
        }
    }

    @Test("Done completes a task by ref and reports it")
    func doneCompletesTaskByReference() throws {
        let root = try tempDirectory(named: "done-task")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTask(
            at: root.appendingPathComponent("finish-report.md"),
            ref: "t-2000",
            title: "Finish report",
            status: .todo
        )

        let service = makeService(defaultFolder: root, now: fixedDate("2026-03-26T18:30:00.000Z"))
        let result = try service.done(.init(ref: "t-2000", folder: root.path))

        #expect(result.completed.ref == "t-2000")
        #expect(result.next == nil)
        #expect(DoneOutputFormatter.makeLine(for: result) == "Completed t-2000 Finish report")

        let completed = try parseTask(atPath: root.appendingPathComponent("finish-report.md").path)
        #expect(completed.document.frontmatter.status == .done)
        #expect(completed.document.frontmatter.completedBy == "todomd-cli")
        #expect(completed.document.frontmatter.completed != nil)
    }

    @Test("Done fails when an explicit folder path does not exist")
    func doneFailsForMissingExplicitFolder() throws {
        let missingFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-missing-done-\(UUID().uuidString)", isDirectory: true)
        let service = makeService(defaultFolder: missingFolder, now: fixedDate("2026-03-26T18:30:00.000Z"))

        do {
            _ = try service.done(.init(ref: "t-9999", folder: missingFolder.path))
            Issue.record("Expected done to fail for a missing explicit folder path")
        } catch {
            #expect(error.localizedDescription.contains("does not exist"))
        }
    }

    @Test("Done uses repeating completion when recurrence exists")
    func doneCompletesRepeatingTask() throws {
        let root = try tempDirectory(named: "done-repeating")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeTask(
            at: root.appendingPathComponent("water-plants.md"),
            ref: "t-2001",
            title: "Water plants",
            status: .todo,
            due: "2026-03-26",
            recurrence: "FREQ=DAILY"
        )

        let service = makeService(defaultFolder: root, now: fixedDate("2026-03-26T18:30:00.000Z"))
        let result = try service.done(.init(ref: "t-2001", folder: root.path))

        #expect(result.completed.ref == "t-2001")
        #expect(result.next != nil)
        #expect(DoneOutputFormatter.makeLine(for: result).contains("next"))

        let records = try loadTasks(in: root)
        #expect(records.count == 2)

        let completed = try #require(records.first(where: { $0.document.frontmatter.ref == "t-2001" }))
        #expect(completed.document.frontmatter.status == .done)
        #expect(completed.document.frontmatter.recurrence == nil)

        let next = try #require(records.first(where: { $0.document.frontmatter.ref != "t-2001" }))
        #expect(next.document.frontmatter.status == .todo)
        #expect(next.document.frontmatter.recurrence == "FREQ=DAILY")
        #expect(next.document.frontmatter.due?.isoString == "2026-03-27")
    }

    @Test("Done rejects a missing explicit folder path")
    func doneRejectsMissingExplicitFolder() {
        let missingFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-missing-done-folder-\(UUID().uuidString)", isDirectory: true)

        let service = makeService(defaultFolder: missingFolder, now: fixedDate("2026-03-26T12:00:00.000Z"))

        do {
            _ = try service.done(.init(ref: "t-9999", folder: missingFolder.path))
            Issue.record("Expected done to reject a missing folder path")
        } catch {
            #expect(error.localizedDescription.contains("Folder does not exist"))
        }
    }

    @Test("Inbox ingests dropped markdown files and reports the count")
    func inboxProcessesDroppedFiles() throws {
        let root = try tempDirectory(named: "inbox")
        defer { try? FileManager.default.removeItem(at: root) }

        let inboxURL = root.appendingPathComponent(".inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        try "Buy milk".write(
            to: inboxURL.appendingPathComponent("buy-milk.md"),
            atomically: true,
            encoding: .utf8
        )
        try "Call dentist".write(
            to: inboxURL.appendingPathComponent("call-dentist.md"),
            atomically: true,
            encoding: .utf8
        )

        let service = makeService(defaultFolder: root, now: fixedDate("2026-03-26T12:00:00.000Z"))
        let result = try service.inbox(.init(folder: root.path))

        #expect(result.ingestedCount == 2)
        #expect(InboxOutputFormatter.makeLine(for: result) == "Ingested 2 files")

        let records = try loadTasks(in: root)
        #expect(records.count == 2)
        #expect(Set(records.map(\.document.frontmatter.title)) == ["buy-milk", "call-dentist"])
        #expect(Set(records.map(\.document.frontmatter.source)) == ["inbox-drop"])
    }

    @Test("CLI registers add list done inbox and validate subcommands")
    func rootCommandRegistersExpectedSubcommands() {
        var subcommands = Set<String>()
        for subcommand in TodoMDCLI.configuration.subcommands {
            if let commandName = subcommand.configuration.commandName {
                subcommands.insert(commandName)
            }
        }
        #expect(subcommands == ["add", "list", "done", "inbox", "validate"])
    }

    private func makeService(defaultFolder: URL, now: Date) -> TaskCLIService {
        TaskCLIService(
            environment: .init(
                fileManager: .default,
                calendar: fixedCalendar(),
                now: { now },
                resolveDefaultFolder: { defaultFolder }
            )
        )
    }

    private func tempDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDCLI-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixedDate(_ iso8601: String) -> Date {
        DateCoding.decode(iso8601) ?? Date(timeIntervalSince1970: 0)
    }

    private func fixedCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        return calendar
    }

    private func writeTask(
        at url: URL,
        ref: String,
        title: String,
        status: TaskStatus,
        due: String? = nil,
        project: String? = nil,
        recurrence: String? = nil
    ) throws {
        var lines = [
            "---",
            "ref: \(ref)",
            "title: \"\(title)\"",
            "status: \(status.rawValue)",
            "priority: none",
            "flagged: false",
            "created: \"2026-03-26T12:00:00.000Z\"",
            "source: cli-test"
        ]

        if let due {
            lines.append("due: \(due)")
        }

        if let project {
            lines.append("project: \"\(project)\"")
        }

        if let recurrence {
            lines.append("recurrence: \"\(recurrence)\"")
        }

        lines.append("---")
        lines.append("")

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func parseTask(atPath path: String) throws -> TaskRecord {
        let url = URL(fileURLWithPath: path)
        let markdown = try String(contentsOf: url, encoding: .utf8)
        let document = try TaskMarkdownCodec().parse(
            markdown: markdown,
            fallbackTitle: url.deletingPathExtension().lastPathComponent
        )
        return TaskRecord(identity: .init(path: path), document: document)
    }

    private func loadTasks(in root: URL) throws -> [TaskRecord] {
        try FileTaskRepository(rootURL: root).loadAll()
    }
}
