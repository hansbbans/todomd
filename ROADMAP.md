# Ecosystem-First Roadmap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform todo.md from "Things 3 but open files" into "the task layer everything writes to" by building the external contract, ecosystem tools, and in-app visibility for multi-source task management.

**Architecture:** The filesystem-as-API thesis needs three layers: (1) a formal contract so external tools know how to write valid tasks, (2) ecosystem tools that make writing tasks trivial (magic inbox, CLI, AI prompt), and (3) in-app visibility so the user can see what external tools are doing. A prerequisite decomposition of RootView/AppContainer unblocks all UI work.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Yams, JSON Schema Draft 2020-12, Swift Argument Parser (CLI), swift-markdown (body rendering)

**Origin:** CEO-mode product review (2026-03-24). Decisions: interop-first audience, personal use launch target, scope expansion.

---

## Dependency Graph

```
Phase 0: Foundation
  Task 1: Decompose RootView ──────────────────────┐
  Task 2: Decompose AppContainer ──────────────────┤
                                                     │
Phase 1: External Contract                           │
  Task 3: todomd:// URL in frontmatter (adds url   │
          to knownKeys + frontmatter)               │
  Task 4: .schema.json (needs Task 3 — includes     │
          url field)  ─────────────┐                │
  Task 5: Schema-code sync test ───┤ (needs Task 4) │
  Task 6: Validator CLI ───────────┘ (needs Task 4) │
                                                     │
Phase 2: Ecosystem Tools                             │
  Task 7: .inbox/ magic folder (needs Task 4)       │
  Task 8: .prompt.md AI agent template (needs Task 4)│
  Task 9: todomd CLI tool (needs Tasks 6, 7)        │
                                                     │
Phase 3: In-App Visibility (needs Phase 0) ─────────┘
  Task 10: Source badges on task rows
  Task 11: Source activity feed
  Task 12: Markdown body rendering
```

## File Structure

### New Files

```
Sources/TodoMDCore/
  Contracts/
    TaskSchemaExporter.swift        # Generates JSON Schema from Swift types
  Storage/
    InboxFolderService.swift        # Watches .inbox/, ingests with defaults
    InboxIngestResult.swift         # Result type for inbox processing
  Observability/
    SourceActivityLog.swift         # Tracks per-source file events

Sources/TodoMDApp/
  Features/
    TodayTabView.swift              # Extracted from RootView
    InboxTabView.swift              # Extracted from RootView
    UpcomingTabView.swift           # Extracted from RootView
    AnytimeTabView.swift            # Extracted from RootView
    SomedayTabView.swift            # Extracted from RootView
    LogbookTabView.swift            # Extracted from RootView
    AreasTabView.swift              # Extracted from RootView
    ReviewTabView.swift             # Extracted from RootView
    PerspectiveTabView.swift        # Extracted from RootView
    TaskRowSourceBadge.swift        # Source origin indicator on task rows
    SourceActivityFeedView.swift    # Activity feed in Diagnostics
    MarkdownBodyView.swift          # Renders task body as markdown
  App/
    TaskEditPresenter.swift         # Extracted from AppContainer
    FileConflictCoordinator.swift   # Extracted from AppContainer
    CalendarCoordinator.swift       # Extracted from AppContainer
    NotificationCoordinator.swift   # Extracted from AppContainer

Tools/
  todomd-cli/
    Package.swift                   # Swift Package for CLI
    Sources/
      TodoMDCLI/
        main.swift                  # Entry point
        AddCommand.swift            # todomd add "title"
        ListCommand.swift           # todomd list [view]
        DoneCommand.swift           # todomd done <ref>
        ValidateCommand.swift       # todomd validate *.md
        InboxCommand.swift          # todomd inbox

Tests/TodoMDCoreTests/
  TaskSchemaExporterTests.swift     # Schema-code sync validation
  InboxFolderServiceTests.swift     # Magic inbox ingest tests
  SourceActivityLogTests.swift      # Activity log tests

Root of user's task folder (runtime):
  .schema.json                      # Machine-readable JSON Schema
  .prompt.md                        # AI agent instructions
  .inbox/                           # Magic ingest folder
```

### Modified Files

```
Sources/TodoMDCore/
  Contracts/TaskFrontmatterV1.swift     # Add url field
  Parsing/TaskMarkdownCodec.swift       # Parse/serialize url field
  Storage/FileTaskRepository.swift      # Write url on create, watch .inbox/
  Storage/FileWatcherService.swift      # Add .inbox/ monitoring

Sources/TodoMDApp/
  Features/RootView.swift               # Decompose into tab views (~6700→~800 lines)
  App/AppContainer.swift                # Decompose into coordinators (~4500→~1500 lines)
  Shared/TaskSourceAttribution.swift    # Add badge icon mapping
  Detail/TaskDetailView.swift           # Use MarkdownBodyView for body

Tests/TodoMDCoreTests/
  TaskMarkdownCodecTests.swift          # Add url field round-trip tests
  FileTaskRepositoryAndWatcherTests.swift # Add .inbox/ tests
```

---

## Phase 0: Foundation (Decomposition)

### Task 1: Decompose RootView into focused tab views

**Why:** RootView.swift is 6,721 lines mixing tab navigation, task display, editing, and sheet management. Every UI ticket touches this file. Splitting first makes each future change a clean, focused PR.

**Strategy:** Extract each tab's content into its own SwiftUI view file. RootView becomes a thin router that holds navigation state and delegates to tab views. No behavior changes — pure extraction refactor.

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift`
- Create: `Sources/TodoMDApp/Features/TodayTabView.swift`
- Create: `Sources/TodoMDApp/Features/InboxTabView.swift`
- Create: `Sources/TodoMDApp/Features/UpcomingTabView.swift`
- Create: `Sources/TodoMDApp/Features/AnytimeTabView.swift`
- Create: `Sources/TodoMDApp/Features/SomedayTabView.swift`
- Create: `Sources/TodoMDApp/Features/LogbookTabView.swift`
- Create: `Sources/TodoMDApp/Features/AreasTabView.swift`
- Create: `Sources/TodoMDApp/Features/ReviewTabView.swift`
- Create: `Sources/TodoMDApp/Features/PerspectiveTabView.swift`

**Approach:**
1. Read RootView.swift fully and map which code blocks correspond to which tabs
2. For each tab, identify the `@State`/`@Binding` properties it uses
3. Extract the view body and its helpers into a new file, passing dependencies as init params or `@Environment`
4. RootView retains navigation state and tab switching logic only
5. Verify compilation after each extraction

- [ ] **Step 1: Read RootView.swift completely and create an extraction map**

Document which line ranges correspond to which tab views. Identify shared state that multiple tabs reference. This map guides all subsequent extractions.

- [ ] **Step 2: Extract InboxTabView**

Start with Inbox because it's typically the simplest tab. Find the view body section that renders the Inbox task list. Extract it into `InboxTabView.swift` with the required bindings. Update RootView to use `InboxTabView(...)`.

Run: `swift build` to verify compilation.

- [ ] **Step 3: Extract TodayTabView**

Today is the most complex tab (calendar overlay, sections, hero header). Extract the Today body, its section grouping logic, and its helper views. Pass `TodaySection` groupings from the parent.

Run: `swift build` to verify compilation.

- [ ] **Step 4: Extract UpcomingTabView**

Extract the Upcoming view with its date-grouped sections and calendar integration.

Run: `swift build` to verify compilation.

- [ ] **Step 5: Extract remaining tab views (Anytime, Someday, Logbook, Areas, Review, Perspective)**

Extract each remaining tab. These are typically simpler than Today/Upcoming. Each gets its own file.

Run: `swift build` after each extraction.

- [ ] **Step 6: Verify RootView is now a thin router**

RootView should be ~800 lines or less: tab bar, navigation state, sheet presentation, and delegation to tab views. No task rendering logic should remain.

Run: `swift build && swift test` to verify no regressions.

- [ ] **Step 7: Commit**

```bash
git add Sources/TodoMDApp/Features/
git commit -m "refactor: decompose RootView into focused tab views

Extract InboxTabView, TodayTabView, UpcomingTabView, AnytimeTabView,
SomedayTabView, LogbookTabView, AreasTabView, ReviewTabView, and
PerspectiveTabView from RootView. RootView is now a thin router
holding navigation state and tab switching."
```

---

### Task 2: Decompose AppContainer into focused coordinators

**Why:** AppContainer.swift is 4,553 lines managing file coordination, task editing, calendar, conflicts, notifications, and UI state. Splitting makes each concern independently testable and navigable.

**Strategy:** Extract logical groups into coordinator/presenter objects. AppContainer becomes a composition root that owns and wires the coordinators.

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift`
- Create: `Sources/TodoMDApp/App/TaskEditPresenter.swift`
- Create: `Sources/TodoMDApp/App/FileConflictCoordinator.swift`
- Create: `Sources/TodoMDApp/App/CalendarCoordinator.swift`
- Create: `Sources/TodoMDApp/App/NotificationCoordinator.swift`

- [ ] **Step 1: Read AppContainer.swift completely and identify concern boundaries**

Map which methods/properties belong to which concern: task editing state, conflict resolution, calendar integration, notification scheduling, settings, diagnostics. Document dependencies between concerns.

- [ ] **Step 2: Extract TaskEditPresenter**

Search for `TaskEditState` by symbol name in AppContainer.swift (do not rely on line numbers — this file is 4,553 lines and line references are volatile). Move `TaskEditState` and all task editing methods (create, update, complete, delete, move) into `TaskEditPresenter`. This is an `@Observable` class that AppContainer owns.

Run: `swift build` to verify compilation.

- [ ] **Step 3: Extract FileConflictCoordinator**

Search for `ConflictSummary` and `ConflictVersionSummary` by symbol name. Move these types and all conflict detection/resolution logic into `FileConflictCoordinator`.

Run: `swift build` to verify compilation.

- [ ] **Step 4: Extract CalendarCoordinator**

Move EventKit integration, calendar event fetching, and calendar overlay logic into `CalendarCoordinator`.

Run: `swift build` to verify compilation.

- [ ] **Step 5: Extract NotificationCoordinator**

Move notification scheduling, permission handling, and nag notification logic into `NotificationCoordinator`.

Run: `swift build` to verify compilation.

- [ ] **Step 6: Verify AppContainer is now a composition root**

AppContainer should be ~1,500 lines or less: initialization, coordinator wiring, file watcher setup, and published state aggregation. No business logic should remain inline.

Run: `swift build && swift test` to verify no regressions.

- [ ] **Step 7: Commit**

```bash
git add Sources/TodoMDApp/App/
git commit -m "refactor: decompose AppContainer into focused coordinators

Extract TaskEditPresenter, FileConflictCoordinator, CalendarCoordinator,
and NotificationCoordinator. AppContainer is now a composition root."
```

---

## Phase 1: External Contract

### Task 3: Generate .schema.json from Swift types

**Why:** The filesystem-as-API has no formal contract. External tools (AI agents, Obsidian, scripts) must reverse-engineer the format from the spec doc. A machine-readable JSON Schema in the task folder means any tool can validate tasks before writing them.

**Files:**
- Create: `Sources/TodoMDCore/Contracts/TaskSchemaExporter.swift`
- Create: `Tests/TodoMDCoreTests/TaskSchemaExporterTests.swift`

**Dependency note:** Task 8 (URL in frontmatter) adds a `url` field to both `TaskFrontmatterV1` and `TaskMarkdownCodec.knownKeys`. The schema must include `url` from the start so the Task 4 sync test doesn't break when Task 8 ships. **Therefore, Task 8 (add url field to codec + frontmatter) must be done BEFORE Task 3, or the url field must be added to knownKeys as part of Task 3.** The simplest approach: include `url` in the schema and knownKeys from the start, even before the app writes it. External tools reading the schema will see that `url` is an optional string field.

**Reference:** The schema must match these existing definitions exactly:
- `TaskFrontmatterV1` (`Sources/TodoMDCore/Contracts/TaskFrontmatterV1.swift` lines 44-132)
- `TaskStatus` enum: todo, inProgress, done, cancelled, someday (`Sources/TodoMDCore/Contracts/ScalarTypes.swift` line 3)
- `TaskPriority` enum: none, low, medium, high (`Sources/TodoMDCore/Contracts/ScalarTypes.swift` line 11)
- `TaskMarkdownCodec.knownKeys` (`Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` lines 16-22) — must include `url` after Task 8
- Source defaults to "unknown" (`Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` line 248)

- [ ] **Step 1: Write the failing test — schema contains all known frontmatter keys**

```swift
// Tests/TodoMDCoreTests/TaskSchemaExporterTests.swift
import XCTest
@testable import TodoMDCore

final class TaskSchemaExporterTests: XCTestCase {

    func testSchemaContainsAllKnownKeys() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
        let properties = json["properties"] as! [String: Any]

        // Every key from TaskMarkdownCodec.knownKeys must appear
        let expectedKeys: Set<String> = [
            "ref", "title", "status", "due", "due_time",
            "persistent_reminder", "defer", "scheduled", "scheduled_time",
            "priority", "flagged", "area", "project", "tags",
            "recurrence", "estimated_minutes", "description",
            "location_name", "location_latitude", "location_longitude",
            "location_radius_meters", "location_trigger",
            "created", "modified", "completed",
            "assignee", "completed_by", "blocked_by", "source"
        ]
        let actualKeys = Set(properties.keys)
        XCTAssertEqual(expectedKeys, actualKeys,
            "Schema keys must match TaskMarkdownCodec known keys exactly")
    }

    func testSchemaStatusEnumMatchesTaskStatus() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
        let properties = json["properties"] as! [String: Any]
        let status = properties["status"] as! [String: Any]
        let enumValues = status["enum"] as! [String]

        // Must match TaskStatus cases
        let expected = ["todo", "in-progress", "done", "cancelled", "someday"]
        XCTAssertEqual(Set(enumValues), Set(expected))
    }

    func testSchemaPriorityEnumMatchesTaskPriority() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
        let properties = json["properties"] as! [String: Any]
        let priority = properties["priority"] as! [String: Any]
        let enumValues = priority["enum"] as! [String]

        let expected = ["none", "low", "medium", "high"]
        XCTAssertEqual(Set(enumValues), Set(expected))
    }

    func testSchemaRequiredFieldsMatchCodec() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
        let required = json["required"] as! [String]

        // title, status, created, source are required per codec
        XCTAssertTrue(required.contains("title"))
        XCTAssertTrue(required.contains("status"))
        XCTAssertTrue(required.contains("created"))
        XCTAssertTrue(required.contains("source"))
    }

    func testSchemaIsValidJSONSchema() throws {
        let schema = TaskSchemaExporter.exportJSONSchema()
        let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]

        XCTAssertEqual(json["$schema"] as? String,
            "https://json-schema.org/draft/2020-12/schema")
        XCTAssertEqual(json["type"] as? String, "object")
        XCTAssertNotNil(json["properties"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TaskSchemaExporterTests`
Expected: Compilation error — `TaskSchemaExporter` does not exist.

- [ ] **Step 3: Implement TaskSchemaExporter**

Create `Sources/TodoMDCore/Contracts/TaskSchemaExporter.swift`. Build the JSON Schema programmatically from the Swift types. Use `JSONSerialization` to produce the output (no new dependencies).

The exporter must:
- Reference `TaskStatus.allCases` and `TaskPriority.allCases` for enum values
- Use the same raw string values as `TaskMarkdownCodec` (e.g., `"in-progress"` not `"inProgress"`)
- Mark `title`, `status`, `created`, `source` as required
- Use `"type": "string"` with `"format": "date"` for date fields
- Use `"type": "string"` with `"format": "date-time"` for datetime fields
- Use `"type": "array", "items": {"type": "string"}` for tags
- Use `"type": "boolean"` for flagged
- Use `"type": "integer"` for estimated_minutes
- Use `"type": "number"` for location coordinates
- Set `"additionalProperties": true` to allow user-defined fields (spec says preserve unknown keys)

```swift
// Sources/TodoMDCore/Contracts/TaskSchemaExporter.swift
import Foundation

public enum TaskSchemaExporter {
    public static func exportJSONSchema() -> Data {
        let schema: [String: Any] = [
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://todomd.app/schema/task-v1.json",
            "title": "todo.md Task",
            "description": "A todo.md task file frontmatter schema",
            "type": "object",
            "required": ["title", "status", "created", "source"],
            "additionalProperties": true,
            "properties": buildProperties()
        ]
        return try! JSONSerialization.data(
            withJSONObject: schema,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func buildProperties() -> [String: Any] {
        // Build from TaskMarkdownCodec.knownKeys. Each key maps to its JSON Schema type.
        // Use TaskStatus.allCases and TaskPriority.allCases for enum values (raw strings).
        // Field → type mapping (derive from TaskFrontmatterV1):
        //   ref: string
        //   title: string
        //   status: string enum [todo, in-progress, done, cancelled, someday]
        //   due, defer, scheduled: string format:date (YYYY-MM-DD)
        //   due_time, scheduled_time: string (HH:MM)
        //   persistent_reminder: string format:date-time
        //   priority: string enum [none, low, medium, high]
        //   flagged: boolean
        //   area, project, description, assignee, completed_by, source: string
        //   tags: array of strings
        //   recurrence: string (RRULE format)
        //   estimated_minutes: integer
        //   location_name: string
        //   location_latitude, location_longitude: number
        //   location_radius_meters: number
        //   location_trigger: string enum [arrive, leave]
        //   blocked_by: string (ref or "ref:t-xxxx" format)
        //   created, modified, completed: string format:date-time
        //   url: string (todomd:// deep link, auto-generated)
        var props: [String: Any] = [:]
        // ... build each entry as ["type": ..., "description": ...]
        return props
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter TaskSchemaExporterTests`
Expected: All 5 tests PASS.

- [ ] **Step 5: Add runtime schema export — write .schema.json to task folder on app launch**

Modify `AppContainer` (or the appropriate coordinator) to call `TaskSchemaExporter.exportJSONSchema()` and write the result to `.schema.json` in the task folder root on each launch. This keeps the schema in sync with the app version.

**Reference:** The task folder root path is obtained from `FileTaskRepository`'s base URL.

- [ ] **Step 6: Commit**

```bash
git add Sources/TodoMDCore/Contracts/TaskSchemaExporter.swift
git add Tests/TodoMDCoreTests/TaskSchemaExporterTests.swift
git commit -m "feat: generate .schema.json from Swift types

Machine-readable JSON Schema for task frontmatter, exported from
the same Swift types the codec uses. Written to the task folder
on app launch so external tools can validate before writing."
```

---

### Task 4: Schema-code sync test

**Why:** If `TaskMarkdownCodec` adds a new field but `TaskSchemaExporter` isn't updated, external tools will reject valid files. This test catches drift.

**Files:**
- Modify: `Tests/TodoMDCoreTests/TaskSchemaExporterTests.swift`

- [ ] **Step 1: Extract knownKeys as a public static property on TaskMarkdownCodec**

**REQUIRED prerequisite.** Currently, `knownKeys` is a local `let` constant inside the `parse` method body at `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` lines 16-22. It must be extracted to a `public static let knownKeys: Set<String>` on `TaskMarkdownCodec` so both the sync test and the schema exporter can reference it as the single source of truth.

```swift
// In Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift, add at struct level:
public static let knownKeys: Set<String> = [
    "ref",
    "title", "status", "due", "due_time", "persistent_reminder", "defer", "scheduled", "scheduled_time", "priority", "flagged", "area", "project", "tags",
    "recurrence", "estimated_minutes", "description",
    "location_name", "location_latitude", "location_longitude", "location_radius_meters", "location_trigger",
    "created", "modified", "completed", "assignee", "completed_by", "blocked_by", "source"
]
```

Then update the `parse` method to reference `Self.knownKeys` instead of the local `let`.

Run: `swift build && swift test` to verify no regressions.

- [ ] **Step 2: Write the sync test**

```swift
func testSchemaKeysMatchCodecKnownKeys() throws {
    // Get keys from schema
    let schema = TaskSchemaExporter.exportJSONSchema()
    let json = try JSONSerialization.jsonObject(with: schema) as! [String: Any]
    let schemaKeys = Set((json["properties"] as! [String: Any]).keys)

    // Get keys from codec — now a public static property
    let codecKeys = TaskMarkdownCodec.knownKeys

    // They must be identical
    let inSchemaNotCodec = schemaKeys.subtracting(codecKeys)
    let inCodecNotSchema = codecKeys.subtracting(schemaKeys)

    XCTAssertTrue(inSchemaNotCodec.isEmpty,
        "Keys in schema but not codec: \(inSchemaNotCodec)")
    XCTAssertTrue(inCodecNotSchema.isEmpty,
        "Keys in codec but not schema: \(inCodecNotSchema) — add these to TaskSchemaExporter")
}
```

- [ ] **Step 2: Run test, verify it passes (or fix if knownKeys needs to be exposed)**

Run: `swift test --filter testSchemaKeysMatchCodecKnownKeys`

- [ ] **Step 3: Commit**

```bash
git add Tests/TodoMDCoreTests/TaskSchemaExporterTests.swift
git add Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift
git commit -m "test: add schema-code sync test to prevent drift

Validates that .schema.json properties match TaskMarkdownCodec.knownKeys
exactly. Fails if either side adds a field without updating the other."
```

---

### Task 5: Validator CLI

**Why:** `todomd validate *.md` gives developers a way to check their files without running the app. Foundation for CI pipelines and editor integrations.

**Files:**
- Create: `Tools/todomd-cli/Package.swift`
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/main.swift`
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/ValidateCommand.swift`

**Dependencies:** Swift Argument Parser for CLI argument handling. The CLI imports TodoMDCore as a local package dependency.

- [ ] **Step 1: Set up the Swift package**

The CLI needs access to `TaskMarkdownCodec` and related TodoMDCore types. **Use a symlink approach:** create a symlink from `Tools/todomd-cli/Sources/TodoMDCore` pointing to `../../Sources/TodoMDCore`. This lets the CLI compile TodoMDCore sources directly without restructuring the Xcode project.

```bash
# Run once during setup:
cd Tools/todomd-cli/Sources
ln -s ../../../Sources/TodoMDCore TodoMDCore
```

```swift
// Tools/todomd-cli/Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "todomd-cli",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "6.0.1"),
    ],
    targets: [
        .target(
            name: "TodoMDCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/TodoMDCore"
        ),
        .executableTarget(
            name: "todomd",
            dependencies: [
                "TodoMDCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/TodoMDCLI"
        ),
    ]
)
```

**Important:** The symlink means TodoMDCore is compiled twice (once for app, once for CLI) but from the same source files. Any changes to TodoMDCore are immediately available to both. If TodoMDCore imports UIKit or other iOS-only frameworks anywhere, those imports will need `#if canImport(UIKit)` guards — check during implementation.

- [ ] **Step 2: Implement the validate command**

```swift
// Tools/todomd-cli/Sources/TodoMDCLI/ValidateCommand.swift
import ArgumentParser
import Foundation

struct ValidateCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate todo.md task files against the schema"
    )

    @Argument(help: "Paths to .md files or directories to validate")
    var paths: [String]

    @Flag(help: "Show detailed error information")
    var verbose = false

    mutating func run() throws {
        var totalFiles = 0
        var validFiles = 0
        var invalidFiles = 0

        for path in expandedPaths(paths) {
            totalFiles += 1
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                let filename = URL(fileURLWithPath: path).lastPathComponent
                let codec = TaskMarkdownCodec()
                _ = try codec.parse(
                    markdown: content,
                    fallbackTitle: filename
                )
                validFiles += 1
                if verbose { print("  OK  \(path)") }
            } catch {
                invalidFiles += 1
                print("FAIL  \(path)")
                if verbose { print("      \(error)") }
            }
        }

        print("\n\(totalFiles) files checked: \(validFiles) valid, \(invalidFiles) invalid")
        if invalidFiles > 0 {
            throw ExitCode.failure
        }
    }
}
```

- [ ] **Step 3: Implement the main entry point**

```swift
// Tools/todomd-cli/Sources/TodoMDCLI/main.swift
import ArgumentParser

@main
struct TodoMDCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "todomd",
        abstract: "Command-line tools for todo.md task files",
        subcommands: [ValidateCommand.self]
    )
}
```

- [ ] **Step 4: Build and test manually**

Run: `cd Tools/todomd-cli && swift build`
Run: `swift run todomd validate ../../Tests/TodoMDCoreTests/Fixtures/*.md` (if test fixtures exist)
Run: `echo '---\ntitle: Test\nstatus: todo\nsource: cli-test\ncreated: 2026-03-24T00:00:00Z\n---\nBody' > /tmp/test-task.md && swift run todomd validate /tmp/test-task.md`

Expected: Valid file prints OK, exit code 0.

- [ ] **Step 5: Test with an invalid file**

Run: `echo 'not yaml at all' > /tmp/bad-task.md && swift run todomd validate /tmp/bad-task.md`

Expected: FAIL printed, exit code 1.

- [ ] **Step 6: Commit**

```bash
git add Tools/todomd-cli/
git commit -m "feat: add todomd CLI with validate command

todomd validate *.md checks task files against the schema.
Uses the same TaskMarkdownCodec as the app for validation."
```

---

## Phase 2: Ecosystem Tools

### Task 6: .inbox/ magic folder

**Why:** Drops the barrier for external tools from "write perfect YAML frontmatter" to "drop any text file." `echo 'Buy milk' > .inbox/buy-milk.md` creates a task.

**Files:**
- Create: `Sources/TodoMDCore/Storage/InboxFolderService.swift`
- Create: `Sources/TodoMDCore/Storage/InboxIngestResult.swift`
- Create: `Tests/TodoMDCoreTests/InboxFolderServiceTests.swift`
- Modify: `Sources/TodoMDCore/Storage/FileWatcherService.swift` (add .inbox/ monitoring)
- Modify: `Sources/TodoMDCore/Storage/FileTaskRepository.swift` (ingest method)

**Reference:**
- External task detection: `Sources/TodoMDCore/Storage/FileWatcherService.swift` lines 80-84
- Task creation: `Sources/TodoMDCore/Storage/FileTaskRepository.swift` line 31
- Codec parsing: `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` line 10

- [ ] **Step 1: Write the failing test — file with no frontmatter becomes a task**

```swift
// Tests/TodoMDCoreTests/InboxFolderServiceTests.swift
import XCTest
@testable import TodoMDCore

final class InboxFolderServiceTests: XCTestCase {
    var tempDir: URL!
    var inboxDir: URL!
    var tasksDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        tasksDir = tempDir
        inboxDir = tempDir.appendingPathComponent(".inbox")
        try! FileManager.default.createDirectory(
            at: inboxDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFileWithNoFrontmatterBecomesTask() throws {
        // Drop a plain text file into .inbox/
        let file = inboxDir.appendingPathComponent("buy-milk.md")
        try "Buy milk and eggs".write(to: file, atomically: true, encoding: .utf8)

        let service = InboxFolderService(
            inboxURL: inboxDir,
            tasksURL: tasksDir,
            repository: FileTaskRepository(rootURL: tasksDir)
        )
        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "buy-milk")
        XCTAssertEqual(results[0].task.frontmatter.status, .todo)
        XCTAssertEqual(results[0].task.frontmatter.source, "inbox-drop")

        // Original file should be removed from .inbox/
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))

        // Task file should exist in tasks dir
        XCTAssertTrue(results[0].createdPath.hasPrefix(tasksDir.path))
    }

    func testFileWithPartialFrontmatterFillsDefaults() throws {
        let content = """
        ---
        title: "Call dentist"
        tags:
          - health
        ---
        Schedule a cleaning appointment.
        """
        let file = inboxDir.appendingPathComponent("call-dentist.md")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let service = InboxFolderService(
            inboxURL: inboxDir,
            tasksURL: tasksDir,
            repository: FileTaskRepository(rootURL: tasksDir)
        )
        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].task.frontmatter.title, "Call dentist")
        XCTAssertEqual(results[0].task.frontmatter.status, .todo)
        XCTAssertEqual(results[0].task.frontmatter.source, "inbox-drop")
        XCTAssertEqual(results[0].task.frontmatter.tags, ["health"])
        XCTAssertEqual(results[0].task.body, "Schedule a cleaning appointment.")
    }

    func testEmptyFileIsSkipped() throws {
        let file = inboxDir.appendingPathComponent("empty.md")
        try "".write(to: file, atomically: true, encoding: .utf8)

        let service = InboxFolderService(
            inboxURL: inboxDir,
            tasksURL: tasksDir,
            repository: FileTaskRepository(rootURL: tasksDir)
        )
        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results.count, 0)
        // Empty file moved to .inbox/.errors/
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: inboxDir.appendingPathComponent(".errors/empty.md").path))
    }

    func testBulkIngest50Files() throws {
        for i in 1...50 {
            let file = inboxDir.appendingPathComponent("task-\(i).md")
            try "Task number \(i)".write(to: file, atomically: true, encoding: .utf8)
        }

        let service = InboxFolderService(
            inboxURL: inboxDir,
            tasksURL: tasksDir,
            repository: FileTaskRepository(rootURL: tasksDir)
        )
        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results.count, 50)
        // .inbox/ should be empty (no remaining .md files)
        let remaining = try FileManager.default.contentsOfDirectory(
            at: inboxDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "md" }
        XCTAssertEqual(remaining.count, 0)
    }

    func testFileWithValidFrontmatterIsPreservedExactly() throws {
        let content = """
        ---
        title: "Already perfect"
        status: todo
        source: claude-agent
        created: "2026-03-24T10:00:00Z"
        priority: high
        ---
        This file has complete frontmatter.
        """
        let file = inboxDir.appendingPathComponent("perfect.md")
        try content.write(to: file, atomically: true, encoding: .utf8)

        let service = InboxFolderService(
            inboxURL: inboxDir,
            tasksURL: tasksDir,
            repository: FileTaskRepository(rootURL: tasksDir)
        )
        let results = try service.processInbox(now: Date())

        XCTAssertEqual(results[0].task.frontmatter.title, "Already perfect")
        XCTAssertEqual(results[0].task.frontmatter.source, "claude-agent")
        XCTAssertEqual(results[0].task.frontmatter.priority, .high)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter InboxFolderServiceTests`
Expected: Compilation error — `InboxFolderService` does not exist.

- [ ] **Step 3: Implement InboxIngestResult**

```swift
// Sources/TodoMDCore/Storage/InboxIngestResult.swift
import Foundation

public struct InboxIngestResult: Sendable {
    public let task: TaskDocument
    public let createdPath: String
    public let originalFilename: String
}
```

- [ ] **Step 4: Implement InboxFolderService**

```swift
// Sources/TodoMDCore/Storage/InboxFolderService.swift
import Foundation

public final class InboxFolderService: Sendable {
    // Watches .inbox/ folder, processes dropped files:
    // 1. Try to parse with TaskMarkdownCodec
    // 2. If valid: create task via repository, delete inbox file
    // 3. If partial frontmatter: fill defaults (status=todo, source=inbox-drop, created=now)
    // 4. If no frontmatter: use filename as title, file content as body
    // 5. If empty: move to .inbox/.errors/
    // 6. If corrupt YAML: move to .inbox/.errors/
}
```

Full implementation should:
- Enumerate .md files in .inbox/
- **Skip files with modification date within the last 2 seconds** — this prevents reading files that are still being written by an external tool (e.g., a script appending content). Files skipped this way will be picked up on the next sync cycle.
- Attempt parse with `TaskMarkdownCodec().parse(markdown:fallbackTitle:)`
- On success: create via `FileTaskRepository.create(document:)`
- On failure with recoverable content: build a `TaskDocument` with defaults, then create
- On failure with no content: move to `.inbox/.errors/`
- Remove successfully processed files from .inbox/
- Return array of `InboxIngestResult`

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter InboxFolderServiceTests`
Expected: All 5 tests PASS.

- [ ] **Step 6: Integrate with FileWatcherService**

Modify `Sources/TodoMDCore/Storage/FileWatcherService.swift` to call `InboxFolderService.processInbox()` during each sync cycle when .inbox/ directory exists. The watcher should check for .inbox/ at the same base URL as the task folder.

**Production wiring:** The `InboxFolderService` must use the **same** `FileTaskRepository` instance that `AppContainer` already owns — do NOT create a second repository pointing at the same directory (this would create a separate `knownRefsCache` and risk ref collisions). Pass the existing repository instance when constructing `InboxFolderService` in the app startup path.

- [ ] **Step 7: Ensure .inbox/ is created on app launch if it doesn't exist**

In the app startup path, create the `.inbox/` directory alongside `.schema.json`. This makes the feature discoverable.

- [ ] **Step 8: Commit**

```bash
git add Sources/TodoMDCore/Storage/InboxFolderService.swift
git add Sources/TodoMDCore/Storage/InboxIngestResult.swift
git add Tests/TodoMDCoreTests/InboxFolderServiceTests.swift
git add Sources/TodoMDCore/Storage/FileWatcherService.swift
git commit -m "feat: add .inbox/ magic folder for frictionless external ingest

Drop any .md file into .inbox/ and the app ingests it as a task.
Files with valid frontmatter are preserved. Files with partial or
no frontmatter get smart defaults. Empty/corrupt files go to .errors/."
```

---

### Task 7: .prompt.md AI agent template

**Why:** An AI agent that reads this file knows exactly how to create well-formed tasks. No setup, no API keys, no integration docs to find.

**Files:**
- This is a static file written to the task folder at runtime, similar to .schema.json

- [ ] **Step 1: Write the prompt template content**

Create the template as a string constant in the codebase (or a resource file). The content should include:
- What todo.md is (one paragraph)
- The file format with a complete example
- Required vs optional fields with types
- How to use .inbox/ (just drop files)
- How to use the full format (with frontmatter)
- Common patterns: "schedule for today", "add to project", "set a deadline"
- What NOT to do: don't modify .order.json, don't delete files directly, don't modify completed tasks
- Clarify that typed date/time phrases map to `due` / `due_time` (deadline fields), and reminder UI defaults to that same value rather than a separate stored reminder timestamp

```markdown
# todo.md — Instructions for AI Agents

You are interacting with a todo.md task folder. Each task is a `.md` file
with YAML frontmatter. You can create, read, and modify tasks by writing
files to this folder.

## Quick Start: Drop a file into .inbox/

The fastest way to create a task:

    echo "Buy groceries" > .inbox/buy-groceries.md

The app will auto-ingest it with smart defaults.

## Full Format

    ---
    title: "Buy groceries for meal prep"
    status: todo
    scheduled: 2026-03-24
    priority: medium
    area: Personal
    project: Meal Prep
    tags:
      - errands
    source: your-agent-name
    created: 2026-03-24T14:30:00Z
    ---

    Pick up chicken, rice, and broccoli.

## Required Fields

- title (string): Task name
- status (enum): todo | in-progress | done | cancelled | someday
- source (string): Your agent identifier (e.g., "claude-agent", "cron-script")
- created (ISO 8601 datetime): When the task was created

## Optional Fields

[... list all optional fields with types and descriptions ...]

## Date And Reminder Behavior

- A typed date phrase such as "tomorrow" maps to the task deadline field: `due`
- A typed date+time phrase such as "tomorrow at 3:15pm" maps to `due` + `due_time`
- The app's reminder UI starts from that same deadline date/time by default
- There is no separate reminder timestamp field in the task file format

## Rules

- Set `source` to your identifier so the user knows who created the task
- Use ISO 8601 dates: YYYY-MM-DD for dates, YYYY-MM-DDTHH:MM:SSZ for datetimes
- Unknown frontmatter keys are preserved — you can add custom fields
- Do NOT modify .order.json or .perspectives.json
- Do NOT delete task files — set status to "cancelled" instead
- Do NOT modify tasks with status "done" unless the user asked

## Validation

Check your files against `.schema.json` in this folder for the full schema.
```

- [ ] **Step 2: Add runtime write — write .prompt.md to task folder on app launch**

Same pattern as .schema.json: write to the task folder root on each launch so it stays current with the app version.

- [ ] **Step 3: Commit**

```bash
git commit -m "feat: ship .prompt.md AI agent template in task folder

Teaches any LLM that reads the file how to create well-formed tasks.
Includes quick start, full format, field reference, and rules."
```

---

### Task 8: Write todomd:// URL into task frontmatter

**Why:** Every task becomes linkable from any external tool. Obsidian daily notes, Slack messages, and scripts can deep-link to the task in the app.

**Files:**
- Modify: `Sources/TodoMDCore/Contracts/TaskFrontmatterV1.swift` (add `url` property)
- Modify: `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` (parse/serialize `url`)
- Modify: `Sources/TodoMDCore/Storage/FileTaskRepository.swift` (write url on create)
- Modify: `Tests/TodoMDCoreTests/TaskMarkdownCodecTests.swift` (round-trip test)

**Reference:**
- Ref generation: `Sources/TodoMDCore/Contracts/TaskRecord.swift` lines 17-59
- URL routing: `Sources/TodoMDCore/Integration/URLRouting.swift` — handles `todomd://task?ref=t-xxxx`

- [ ] **Step 1: Write the failing test — url field round-trips through codec**

```swift
func testURLFieldRoundTrips() throws {
    let markdown = """
    ---
    title: "Test task"
    status: todo
    source: user
    created: "2026-03-24T10:00:00Z"
    ref: "t-abc1"
    url: "todomd://task/t-abc1"
    ---
    Body text.
    """
    let codec = TaskMarkdownCodec()
    let doc = try codec.parse(markdown: markdown)
    XCTAssertEqual(doc.frontmatter.url, "todomd://task/t-abc1")

    let serialized = try codec.serialize(document: doc)
    XCTAssertTrue(serialized.contains("url: \"todomd://task/t-abc1\""))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testURLFieldRoundTrips`
Expected: Compilation error — `url` property doesn't exist on `TaskFrontmatterV1`.

- [ ] **Step 3: Add url property to TaskFrontmatterV1**

Add `public var url: String?` to `TaskFrontmatterV1` struct. This is a computed-on-write field: the app sets it based on the ref, but external tools can read it.

- [ ] **Step 4: Add url parsing/serialization to TaskMarkdownCodec**

Add "url" to the known keys set. Parse it as an optional string. Serialize it alongside ref.

- [ ] **Step 5: Auto-generate url on task creation in FileTaskRepository**

In `FileTaskRepository.create(document:)` (line 31), after `ensureReference(onCreate:)` returns (line 33) and before `TaskValidation.validate` (line 34), set `document.frontmatter.url = "todomd://task/\(document.frontmatter.ref!)"`. This means every new task has a deep link from birth. The ref is guaranteed to exist at this point because `ensureReference` just set it.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter testURLFieldRoundTrips`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: write todomd:// URL into task frontmatter

Every task now includes a deep link URL in its frontmatter.
External tools can use this URL to open the task directly in the app."
```

---

### Task 9: Expand CLI with add, list, done, inbox commands

**Why:** Developers live in terminals. `todomd add "Buy milk"` is how the target audience falls in love with the product.

**Files:**
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/AddCommand.swift`
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/ListCommand.swift`
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/DoneCommand.swift`
- Create: `Tools/todomd-cli/Sources/TodoMDCLI/InboxCommand.swift`
- Modify: `Tools/todomd-cli/Sources/TodoMDCLI/main.swift` (register subcommands)

**Reference:**
- Task folder location: defaults to `~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault/todo.md/` or a configurable path
- Ref resolution: `Sources/TodoMDCore/Contracts/TaskRecord.swift` `TaskRefResolver` lines 61-80
- Task query engine: `Sources/TodoMDCore/Domain/TaskQueryEngine.swift`

- [ ] **Step 1: Implement AddCommand**

```swift
struct AddCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Create a new task"
    )

    @Argument(help: "Task title")
    var title: String

    @Option(name: .shortAndLong, help: "Due date (YYYY-MM-DD or natural language)")
    var due: String?

    @Option(name: .shortAndLong, help: "Project name")
    var project: String?

    @Option(name: .shortAndLong, help: "Priority (none, low, medium, high)")
    var priority: String?

    @Option(name: .long, help: "Source identifier")
    var source: String = "cli"

    @Option(name: .long, help: "Path to todo.md folder")
    var folder: String?

    mutating func run() throws {
        // Build TaskDocument with the provided fields
        // Write via FileTaskRepository
        // Print: "Created: <title> (ref: t-xxxx)"
    }
}
```

- [ ] **Step 2: Implement ListCommand**

```swift
struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List tasks"
    )

    @Argument(help: "View: today, inbox, upcoming, all (default: today)")
    var view: String = "today"

    @Option(name: .long, help: "Path to todo.md folder")
    var folder: String?

    mutating func run() throws {
        // Load all tasks via FileTaskRepository
        // Filter using TaskQueryEngine for the requested view
        // Print formatted task list with refs
    }
}
```

- [ ] **Step 3: Implement DoneCommand**

```swift
struct DoneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Mark a task as complete"
    )

    @Argument(help: "Task ref (e.g., t-abc1)")
    var ref: String

    @Option(name: .long, help: "Path to todo.md folder")
    var folder: String?

    mutating func run() throws {
        // Resolve ref to file path via TaskRefResolver
        // Complete via FileTaskRepository.complete(path:at:completedBy:)
        // Print: "Completed: <title>"
    }
}
```

- [ ] **Step 4: Implement InboxCommand**

```swift
struct InboxCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Process .inbox/ folder"
    )

    @Option(name: .long, help: "Path to todo.md folder")
    var folder: String?

    mutating func run() throws {
        // Call InboxFolderService.processInbox()
        // Print results: "Ingested 3 tasks from .inbox/"
    }
}
```

- [ ] **Step 5: Register all subcommands in main.swift**

Update `TodoMDCLI` to include: `ValidateCommand`, `AddCommand`, `ListCommand`, `DoneCommand`, `InboxCommand`.

- [ ] **Step 6: Write integration tests for CLI commands**

Create `Tools/todomd-cli/Tests/TodoMDCLITests/CLIIntegrationTests.swift`. Each test creates a temp directory, writes task files, runs the command logic, and verifies output. Use `FileTaskRepository` directly (don't shell out to the binary).

```swift
final class CLIIntegrationTests: XCTestCase {
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testAddCommandCreatesTaskFile() throws {
        let repo = FileTaskRepository(rootURL: tempDir)
        // Simulate AddCommand logic: build document, create via repo
        let doc = TaskDocument(/* title: "Buy milk", status: .todo, source: "cli" */)
        let record = try repo.create(document: doc, preferredFilename: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.identity.path))
        XCTAssertEqual(record.document.frontmatter.source, "cli")
    }

    func testDoneCommandCompletesTask() throws {
        let repo = FileTaskRepository(rootURL: tempDir)
        let doc = TaskDocument(/* title: "Test", status: .todo */)
        let record = try repo.create(document: doc, preferredFilename: nil)
        let completed = try repo.complete(path: record.identity.path, at: Date(), completedBy: "cli")
        XCTAssertEqual(completed.document.frontmatter.status, .done)
    }
}
```

Update `Tools/todomd-cli/Package.swift` to include a test target.

Run: `cd Tools/todomd-cli && swift test`

- [ ] **Step 7: Build and test manually (smoke test)**

```bash
cd Tools/todomd-cli
swift build
swift run todomd add "Buy milk" --due 2026-03-25 --source cli --folder /tmp/todomd-test
swift run todomd list today --folder /tmp/todomd-test
swift run todomd done t-xxxx --folder /tmp/todomd-test
```

- [ ] **Step 8: Commit**

```bash
git add Tools/todomd-cli/
git commit -m "feat: add, list, done, inbox CLI commands

todomd add 'Buy milk' --due tomorrow
todomd list today
todomd done t-abc1
todomd inbox (process .inbox/ folder)"
```

---

## Phase 3: In-App Visibility

### Task 10: Source badges on task rows

**Why:** When external tools create tasks, users need to see who created what at a glance. A subtle badge makes the multi-source world visible and trustworthy.

**Files:**
- Create: `Sources/TodoMDApp/Features/TaskRowSourceBadge.swift`
- Modify: `Sources/TodoMDApp/Shared/TaskSourceAttribution.swift` (add badge icon mapping)
- Modify: Task row view (in the decomposed tab views from Task 1) to include the badge

**Reference:**
- Known sources: `Sources/TodoMDApp/Shared/TaskSourceAttribution.swift` lines 1-39
- Current sources: "user", "shortcut", "voice-ramble", "import-reminders", "unknown"
- New sources to support: "cli", "inbox-drop", "claude-agent", "obsidian", any custom string

- [ ] **Step 1: Define badge icon mapping**

Extend `TaskSourceAttribution` to provide SF Symbol names for known sources:
- "user" → no badge (default, don't clutter)
- "shortcut" → `bolt.fill`
- "voice-ramble" → `mic.fill`
- "import-reminders" → `arrow.down.circle`
- "cli" → `terminal`
- "inbox-drop" → `tray.and.arrow.down`
- "claude-agent" or any AI source → `sparkles`
- "obsidian" → `link`
- unknown/other → `person.badge.plus` (subtle indicator that it's external)

- [ ] **Step 2: Create TaskRowSourceBadge view**

```swift
struct TaskRowSourceBadge: View {
    let source: String

    var body: some View {
        if source != "user", let icon = TaskSourceAttribution.badgeIcon(for: source) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
```

- [ ] **Step 3: Add badge to task row layout**

In the task row view (the one used across all tab views), add `TaskRowSourceBadge(source: task.source)` in the metadata line, after the project pill or tag chips.

- [ ] **Step 4: Verify visually**

Build and run. Create a task via the app (should show no badge). Create a task via the CLI or .inbox/ (should show appropriate badge).

- [ ] **Step 5: Commit**

```bash
git add Sources/TodoMDApp/Features/TaskRowSourceBadge.swift
git add Sources/TodoMDApp/Shared/TaskSourceAttribution.swift
git commit -m "feat: show source badges on task rows

Tasks created by external tools show a subtle SF Symbol badge
indicating their origin (CLI, inbox drop, AI agent, etc.).
User-created tasks show no badge to avoid clutter."
```

---

### Task 11: Source activity feed

**Why:** "Claude triaged your inbox overnight" is the money moment. Without a feed, external writes are invisible ghosts.

**Files:**
- Create: `Sources/TodoMDCore/Observability/SourceActivityLog.swift`
- Create: `Sources/TodoMDApp/Features/SourceActivityFeedView.swift`
- Create: `Tests/TodoMDCoreTests/SourceActivityLogTests.swift`
- Modify: `Sources/TodoMDCore/Storage/FileWatcherService.swift` (log events)

**Reference:**
- FileWatcherEvent types: `Sources/TodoMDCore/Contracts/FileWatcherEvent.swift` lines 4-9
- Existing diagnostics: `Sources/TodoMDCore/Observability/Diagnostics.swift`

- [ ] **Step 1: Write the failing test**

The `SourceActivityLog` uses its own event type (`SourceActivityEvent`), distinct from `FileWatcherEvent`. This is intentional — the activity log is a higher-level abstraction that includes task titles and groups by source, while `FileWatcherEvent` is a low-level filesystem event with paths.

```swift
// Tests/TodoMDCoreTests/SourceActivityLogTests.swift
import XCTest
@testable import TodoMDCore

final class SourceActivityLogTests: XCTestCase {
    func testLogRecordsSourceGroupedEvents() {
        let log = SourceActivityLog()
        let now = Date()

        log.record(SourceActivityEvent(
            action: .created, source: "claude-agent", title: "Buy milk", timestamp: now))
        log.record(SourceActivityEvent(
            action: .created, source: "claude-agent", title: "Call dentist", timestamp: now))
        log.record(SourceActivityEvent(
            action: .created, source: "cli", title: "Review PR", timestamp: now))

        let entries = log.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 2) // grouped by source + action within 5-min window
        XCTAssertEqual(entries[0].source, "claude-agent")
        XCTAssertEqual(entries[0].action, .created)
        XCTAssertEqual(entries[0].taskTitles.count, 2)
    }

    func testEventsOutsideGroupingWindowAreNotGrouped() {
        let log = SourceActivityLog()
        let now = Date()
        let sixMinutesLater = now.addingTimeInterval(360)

        log.record(SourceActivityEvent(
            action: .created, source: "cli", title: "Task 1", timestamp: now))
        log.record(SourceActivityEvent(
            action: .created, source: "cli", title: "Task 2", timestamp: sixMinutesLater))

        let entries = log.recentEntries(limit: 10)
        XCTAssertEqual(entries.count, 2) // Not grouped — outside 5-min window
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SourceActivityLogTests`
Expected: Compilation error — `SourceActivityLog` and `SourceActivityEvent` do not exist.

- [ ] **Step 3: Implement SourceActivityEvent and SourceActivityLog**

```swift
// Sources/TodoMDCore/Observability/SourceActivityLog.swift
import Foundation

/// A single activity event recorded when a task is created/modified/completed by any source.
public struct SourceActivityEvent: Sendable {
    public enum Action: String, Sendable { case created, modified, completed, deleted }

    public let action: Action
    public let source: String
    public let title: String
    public let timestamp: Date

    public init(action: Action, source: String, title: String, timestamp: Date) {
        self.action = action
        self.source = source
        self.title = title
        self.timestamp = timestamp
    }
}

/// A grouped entry for display: multiple events from the same source + action within a time window.
public struct SourceActivityEntry: Sendable {
    public let source: String
    public let action: SourceActivityEvent.Action
    public let taskTitles: [String]
    public let timestamp: Date // earliest in the group
}
```

The `SourceActivityLog` class is an in-memory log (with optional persistence to `.activity.json` in the task folder) that records:
- Source identifier
- Action type (created, modified, completed, deleted)
- Task titles
- Timestamp
- Grouping: events from the same source within a 5-minute window are grouped

- [ ] **Step 4: Implement SourceActivityFeedView**

SwiftUI view added as a section in `Sources/TodoMDApp/Settings/DebugView.swift` (the existing diagnostics screen). Layout:
```
Today
  claude-agent created 3 tasks at 2:15 PM
    • Buy milk
    • Call dentist
    • Schedule appointment

  cli completed 1 task at 3:00 PM
    • Review PR

Yesterday
  inbox-drop created 1 task at 11:30 PM
    • Meeting notes from email
```

- [ ] **Step 5: Wire FileWatcherService to log events**

After processing file events, record them in the SourceActivityLog with the source extracted from the parsed task frontmatter.

- [ ] **Step 6: Run tests to verify they pass**

- [ ] **Step 7: Commit**

```bash
git commit -m "feat: add source activity feed

Shows what external tools did to the task folder, grouped by source
and time window. Visible in Diagnostics. Makes multi-source
task management transparent and trustworthy."
```

---

### Task 12: Markdown body rendering in task detail

**Why:** The target audience writes markdown natively. Plain text rendering of task bodies is a paper cut every time they open a task with links, code, or checklists.

**Files:**
- Create: `Sources/TodoMDApp/Detail/MarkdownBodyView.swift`
- Modify: `Sources/TodoMDApp/Detail/TaskDetailView.swift` (use MarkdownBodyView)
- Modify: `Package.swift` or dependency setup (add swift-markdown if needed)

**Reference:**
- Current body rendering: `Sources/TodoMDApp/Detail/` — find the view that displays `task.body`
- Checklist handling: `Sources/TodoMDCore/Parsing/TaskMarkdownCodec.swift` lines 565-720 (`TaskChecklistMarkdown`)

**Note:** SwiftUI has built-in markdown rendering via `Text(LocalizedStringKey(markdownString))` for simple cases (bold, italic, links, code). For full rendering (headings, code blocks, lists), use `swift-markdown` or `AttributedString`.

- [ ] **Step 1: Start with SwiftUI built-in markdown rendering**

**Decision (made upfront):** Use SwiftUI's built-in `Text(AttributedString(markdown:))` first. It handles the most common patterns in task notes: **bold**, *italic*, `inline code`, [links](url), and bullet lists. This requires zero new dependencies.

Only escalate to `swift-markdown` if user feedback shows that headings (`##`) or fenced code blocks (` ``` `) are common in task bodies — these are not well-supported by built-in `Text`. For now, the built-in approach is sufficient for the interop-developer audience's typical task notes.

Checklists are already handled separately by `TaskChecklistMarkdown` and remain unchanged.

- [ ] **Step 2: Create MarkdownBodyView**

```swift
struct MarkdownBodyView: View {
    let markdown: String

    var body: some View {
        // If using built-in:
        Text(LocalizedStringKey(markdown))
            .font(.body)
            .textSelection(.enabled)

        // If using swift-markdown:
        // Parse to AST, walk nodes, render as SwiftUI views
    }
}
```

- [ ] **Step 3: Replace plain text body in TaskDetailView**

Find where `task.body` is displayed as plain text and replace with `MarkdownBodyView(markdown: task.body)`. Preserve the existing checklist editing behavior — `TaskChecklistMarkdown` handles checklist items separately.

- [ ] **Step 4: Test visually**

Create a task with markdown body:
```markdown
## Notes

- Buy **organic** eggs
- Check [this recipe](https://example.com)
- Code: `git pull && swift build`
```

Verify it renders with formatting, not as raw text.

- [ ] **Step 5: Commit**

```bash
git commit -m "feat: render task body as markdown in detail view

Task notes now display with proper markdown formatting: links,
bold, italic, code, and lists. Checklist editing preserved."
```

---

## Execution Order Summary

| Order | Task | Phase | Effort | Dependencies |
|-------|------|-------|--------|--------------|
| 1 | Decompose RootView | 0 | L | None |
| 2 | Decompose AppContainer | 0 | L | None |
| 3 | todomd:// URL in frontmatter | 1 | S | None (adds `url` to knownKeys + frontmatter) |
| 4 | .schema.json exporter | 1 | S | Task 3 (schema must include `url`) |
| 5 | Schema-code sync test | 1 | S | Task 4 |
| 6 | Validator CLI | 1 | M | Task 4 |
| 7 | .inbox/ magic folder | 2 | M | Task 4 |
| 8 | .prompt.md AI template | 2 | S | Task 4 |
| 9 | CLI add/list/done/inbox | 2 | M | Tasks 6, 7 |
| 10 | Source badges | 3 | S | Task 1 |
| 11 | Source activity feed | 3 | M | Task 1 |
| 12 | Markdown body rendering | 3 | M | Task 1 |

**Parallelization opportunities:**
- Tasks 1 and 2 can run in parallel (independent files)
- Tasks 3 can run in parallel with Tasks 1-2 (independent)
- Tasks 7 and 8 can run in parallel after Task 4
- Tasks 10, 11, and 12 can run in parallel after Tasks 1-2

**Total estimated effort:** ~2 L + 4 S + 6 M tasks
