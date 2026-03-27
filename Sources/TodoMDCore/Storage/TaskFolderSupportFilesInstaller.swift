import Foundation

public struct TaskFolderSupportFilesInstaller {
    public static let promptMarkdown = """
    # todo.md - Instructions for AI Agents

    You are working inside a todo.md task folder. The filesystem is the source of truth. Each task is one Markdown file with YAML frontmatter and an optional Markdown body.

    ## Quick Start: Drop a file into .inbox/

    The easiest way to create a task is to drop a Markdown file into `.inbox/`.

        echo "Buy groceries" > .inbox/buy-groceries.md

    The app will ingest it and fill in sensible defaults.

    ## Full Format

        ---
        title: "Buy groceries for meal prep"
        status: todo
        priority: medium
        scheduled: 2026-03-24
        project: Meal Prep
        tags:
          - errands
        source: your-agent-name
        created: 2026-03-24T14:30:00Z
        ---

        Pick up chicken, rice, and broccoli.

    ## Required Fields

    - `title` (string): Task name shown in the app
    - `status` (enum): `todo`, `in-progress`, `done`, `cancelled`, `someday`
    - `source` (string): Your identifier, such as `claude-agent` or `cron-script`
    - `created` (ISO 8601 UTC datetime): When the task was created

    ## Common Optional Fields

    - `priority` (enum): `none`, `low`, `medium`, `high`
    - `due`, `defer`, `scheduled` (date): `YYYY-MM-DD`
    - `due_time`, `scheduled_time` (time): `HH:MM`
    - `project`, `area`, `description`, `assignee` (string)
    - `tags` (string array)
    - `estimated_minutes` (integer)
    - `flagged`, `persistent_reminder` (boolean)
    - `blocked_by` (manual block, one ref, or an array of refs)
    - `location_*` fields for location reminders
    - `url` (string) for a stable app link when present

    ## Common Patterns

    - Schedule for today: set `scheduled` to today's date
    - Add to a project: set `project` to the exact project name
    - Set a deadline: set `due`, and optionally `due_time`
    - Add notes or a checklist: put long-form notes in the Markdown body, not in frontmatter

    ## Rules

    - Set `source` to your own identifier
    - Preserve unknown frontmatter keys when updating an existing task
    - Keep checklist items in the body under the managed checklist marker if one already exists
    - Use `.inbox/` when you only have loose text and not full frontmatter

    ## Do Not

    - Do NOT modify `.order.json`, `.perspectives.json`, or other app metadata files
    - Do NOT delete task files to complete work; change the task status instead
    - Do NOT add free-form notes after the managed checklist marker
    - Do NOT modify tasks with status `done` or `cancelled` unless the user asked

    ## Validation

    Check your files against `.schema.json` in this folder for the full field list and validation rules.
    """

    public var fileIO: TaskFileIO

    public init(fileIO: TaskFileIO = TaskFileIO()) {
        self.fileIO = fileIO
    }

    public func install(at rootURL: URL) throws {
        try fileIO.fileManager.createDirectory(at: inboxURL(rootURL: rootURL), withIntermediateDirectories: true)
        try fileIO.writeData(path: schemaURL(rootURL: rootURL).path, data: TaskSchemaExporter.exportJSONSchema())
        try fileIO.write(path: promptURL(rootURL: rootURL).path, content: Self.promptMarkdown)
    }

    public func inboxURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".inbox", isDirectory: true)
    }

    public func schemaURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".schema.json", isDirectory: false)
    }

    public func promptURL(rootURL: URL) -> URL {
        rootURL.appendingPathComponent(".prompt.md", isDirectory: false)
    }
}
