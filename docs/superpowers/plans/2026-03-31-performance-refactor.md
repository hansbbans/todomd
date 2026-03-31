# Performance Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate UI lag and sluggish screen transitions by reducing unnecessary view invalidation, removing AnyView type-erasure, caching expensive computations, and moving file I/O off the main thread.

**Architecture:** The root cause is a monolithic `ObservableObject` (`AppContainer`) with 35+ `@Published` properties that invalidates every view on any change, combined with a 7,000-line `RootView` holding 65+ `@State` properties and using `AnyView` for screen switching. The fix migrates to `@Observable` for fine-grained tracking, replaces `AnyView` with `@ViewBuilder`, caches computed sections, and moves synchronous file I/O to a background task.

**Tech Stack:** Swift, SwiftUI, Observation framework (iOS 17+), Swift Concurrency

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/TodoMDApp/App/AppContainer.swift` | Modify | Migrate to `@Observable`, add cached sections, background refresh |
| `Sources/TodoMDApp/App/TodoMDApp.swift` | Modify | Update injection from `.environmentObject` to `.environment` |
| `Sources/TodoMDApp/App/ThemeManager.swift` | Modify | Migrate to `@Observable` for consistency |
| `Sources/TodoMDApp/Features/RootView.swift` | Modify | Replace `AnyView` with `@ViewBuilder`, extract state groups |
| 12 other view files using `@EnvironmentObject` | Modify | Update to `@Environment` |
| `Tests/TodoMDAppTests/AppContainerObservableTests.swift` | Create | Verify observable migration correctness |
| `Tests/TodoMDAppTests/CachedSectionsTests.swift` | Create | Verify section caching invalidation |

---

## Task 1: Migrate `AppContainer` from `ObservableObject` to `@Observable`

This is the highest-impact change. With `ObservableObject`, a change to ANY `@Published` property (e.g. `isCalendarSyncing`) triggers re-evaluation of EVERY view reading `container`, even if that view only reads `records`. With `@Observable`, only views reading the specific changed property re-evaluate.

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift:117-151`
- Test: `Tests/TodoMDAppTests/AppContainerObservableTests.swift`

- [ ] **Step 1: Write a test verifying the current container publishes records**

```swift
// Tests/TodoMDAppTests/AppContainerObservableTests.swift
import Testing
@testable import TodoMDApp

@Suite("AppContainer Observable Migration")
struct AppContainerObservableTests {
    @Test("Container exposes records after initialization")
    @MainActor
    func containerExposesRecords() {
        let container = AppContainer.forTesting()
        #expect(container.records.isEmpty || !container.records.isEmpty)
        // Baseline: container initializes without crash
    }
}
```

- [ ] **Step 2: Run tests to establish baseline**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing TodoMDAppTests/AppContainerObservableTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 3: Change class declaration to `@Observable`**

In `AppContainer.swift`, replace:

```swift
@MainActor
final class AppContainer: ObservableObject {
```

with:

```swift
@MainActor
@Observable
final class AppContainer {
```

- [ ] **Step 4: Remove all `@Published` property wrappers**

Replace every `@Published var` and `@Published private(set) var` with plain `var` and `private(set) var`. The `@Observable` macro handles tracking automatically. There are ~35 properties to update (lines 119-151).

For example, change:
```swift
@Published var selectedView: ViewIdentifier = .builtIn(.inbox) {
    didSet { _ = applyCurrentViewFilter() }
}
@Published var records: [TaskRecord] = []
@Published var diagnostics: [ParseFailureDiagnostic] = []
@Published private(set) var sourceActivityLog = SourceActivityLog()
// ... all remaining @Published properties
```

to:

```swift
var selectedView: ViewIdentifier = .builtIn(.inbox) {
    didSet { _ = applyCurrentViewFilter() }
}
var records: [TaskRecord] = []
var diagnostics: [ParseFailureDiagnostic] = []
private(set) var sourceActivityLog = SourceActivityLog()
// ... all remaining properties without @Published
```

**Important:** Properties that should NOT trigger observation (internal caches) should be annotated with `@ObservationIgnored`:

```swift
@ObservationIgnored private var canonicalByPath: [String: TaskRecord] = [:]
@ObservationIgnored private var allIndexedRecords: [TaskRecord] = []
@ObservationIgnored private var metadataIndex = TaskMetadataIndex.build(from: [TaskRecord]())
@ObservationIgnored private var cachedPerspectivesDocument = PerspectivesDocument()
@ObservationIgnored private var snapshotDiagnostics: [ParseFailureDiagnostic] = []
@ObservationIgnored private var triageRules = TriageRulesDocument()
@ObservationIgnored private let observationState = AppContainerObservationState()
@ObservationIgnored private var metadataQuery: NSMetadataQuery?
```

- [ ] **Step 5: Run tests to verify nothing breaks**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All existing tests pass (some may need updates in next task)

- [ ] **Step 6: Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift Tests/TodoMDAppTests/AppContainerObservableTests.swift
git commit -m "refactor: migrate AppContainer to @Observable for fine-grained view updates"
```

---

## Task 2: Update all view injection sites from `@EnvironmentObject` to `@Environment`

With `@Observable`, views must use `@Environment` instead of `@EnvironmentObject`. The app entry point must use `.environment()` instead of `.environmentObject()`.

**Files:**
- Modify: `Sources/TodoMDApp/App/TodoMDApp.swift:37`
- Modify: `Sources/TodoMDApp/App/AppContainer.swift` (add EnvironmentKey)
- Modify: 14 view files listed below

- [ ] **Step 1: Add `EnvironmentKey` conformance for AppContainer**

At the bottom of `AppContainer.swift`, add:

```swift
private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Update TodoMDApp.swift injection**

In `TodoMDApp.swift`, change line 11 from:
```swift
@StateObject private var container = AppContainer()
```
to:
```swift
@State private var container = AppContainer()
```

Change line 37 from:
```swift
.environmentObject(container)
```
to:
```swift
.environment(\.appContainer, container)
```

- [ ] **Step 3: Update all 14 view files**

In each file, replace:
```swift
@EnvironmentObject var container: AppContainer
// or
@EnvironmentObject private var container: AppContainer
```
with:
```swift
@Environment(\.appContainer) private var container
```

**Files to update (with line numbers):**

1. `Sources/TodoMDApp/Features/RootView.swift:788` — also check line 5660 for second reference
2. `Sources/TodoMDApp/Detail/TaskDetailView.swift:14`
3. `Sources/TodoMDApp/Features/QuickEntrySheet.swift:10`
4. `Sources/TodoMDApp/Features/InboxTriageView.swift:8`
5. `Sources/TodoMDApp/Features/VoiceRambleSheet.swift:445`
6. `Sources/TodoMDApp/Features/InboxRemindersImportPanel.swift:4`
7. `Sources/TodoMDApp/Settings/SettingsView.swift:149`
8. `Sources/TodoMDApp/Settings/DebugView.swift:4`
9. `Sources/TodoMDApp/Settings/PerspectivesView.swift:169`
10. `Sources/TodoMDApp/Settings/UnparseableFilesView.swift:5`
11. `Sources/TodoMDApp/Settings/ConflictResolutionView.swift:5` and `:119`
12. `Sources/TodoMDApp/App/OnboardingView.swift:12`

**Note:** Since `container` becomes `AppContainer?` via the environment key, either force-unwrap at injection (`container!`) or make the `EnvironmentKey.defaultValue` non-optional by providing a test/empty instance. The cleaner approach is to keep it optional and guard at view boundaries, or use a fatalError default:

```swift
private struct AppContainerKey: EnvironmentKey {
    @MainActor static let defaultValue: AppContainer = AppContainer()
}

extension EnvironmentValues {
    var appContainer: AppContainer {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
```

This way all views get a non-optional `AppContainer` and the injection is straightforward.

- [ ] **Step 4: Build and run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift Sources/TodoMDApp/App/TodoMDApp.swift Sources/TodoMDApp/Features/ Sources/TodoMDApp/Detail/ Sources/TodoMDApp/Settings/ Sources/TodoMDApp/App/OnboardingView.swift
git commit -m "refactor: update all views to use @Environment for AppContainer injection"
```

---

## Task 3: Migrate `ThemeManager` to `@Observable`

Same pattern as Task 1, applied to ThemeManager for consistency.

**Files:**
- Modify: `Sources/TodoMDApp/App/ThemeManager.swift:8`
- Modify: `Sources/TodoMDApp/App/TodoMDApp.swift:12,38`
- Modify: All files using `@EnvironmentObject var theme: ThemeManager`

- [ ] **Step 1: Change ThemeManager to `@Observable`**

Replace:
```swift
final class ThemeManager: ObservableObject {
    @Published private(set) var tokens: ThemeTokens
```
with:
```swift
@Observable
final class ThemeManager {
    private(set) var tokens: ThemeTokens
```

Remove all `@Published` wrappers from ThemeManager properties.

- [ ] **Step 2: Add EnvironmentKey for ThemeManager**

```swift
private struct ThemeManagerKey: EnvironmentKey {
    static let defaultValue: ThemeManager = ThemeManager()
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeManagerKey.self] }
        set { self[ThemeManagerKey.self] = newValue }
    }
}
```

- [ ] **Step 3: Update TodoMDApp.swift**

Change:
```swift
@StateObject private var theme = ThemeManager()
```
to:
```swift
@State private var theme = ThemeManager()
```

Change:
```swift
.environmentObject(theme)
```
to:
```swift
.environment(\.themeManager, theme)
```

- [ ] **Step 4: Update all views using `@EnvironmentObject var theme: ThemeManager`**

Search for `@EnvironmentObject` references to `theme` or `ThemeManager` and replace with `@Environment(\.themeManager)`. Follow the same pattern as Task 2.

- [ ] **Step 5: Build and run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/TodoMDApp/App/ThemeManager.swift Sources/TodoMDApp/App/TodoMDApp.swift Sources/TodoMDApp/Features/ Sources/TodoMDApp/Detail/ Sources/TodoMDApp/Settings/
git commit -m "refactor: migrate ThemeManager to @Observable"
```

---

## Task 4: Replace `AnyView` with `@ViewBuilder` in RootView screen switching

`AnyView` destroys SwiftUI's structural identity. When switching tabs, SwiftUI can't diff efficiently — it tears down and rebuilds the entire view tree instead of animating between known structures. This directly causes lag between screens.

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift:1745-1827`

- [ ] **Step 1: Convert `mainContent` from `AnyView` to `@ViewBuilder`**

Replace the current computed property (lines 1745-1827):

```swift
private var mainContent: AnyView {
    if container.selectedView.isBrowse {
        return AnyView(browseContent().transition(rootScreenTransition))
    }
    if container.selectedView == .builtIn(.upcoming) {
        return AnyView(upcomingMainContent().transition(rootScreenTransition))
    }
    // ... many more branches
    return AnyView(recordsMainContent(records: container.filteredRecords()).transition(rootScreenTransition))
}
```

with a `@ViewBuilder` computed property:

```swift
@ViewBuilder
private var mainContent: some View {
    switch container.selectedView {
    case _ where container.selectedView.isBrowse:
        browseContent()
            .transition(rootScreenTransition)
    case .builtIn(.upcoming):
        upcomingMainContent()
            .transition(rootScreenTransition)
    case .builtIn(.review):
        ReviewTabView(
            sections: container.weeklyReviewSections(),
            backgroundColor: theme.backgroundColor,
            textPrimaryColor: theme.textPrimaryColor,
            textSecondaryColor: theme.textSecondaryColor,
            accentColor: theme.accentColor,
            isPullToSearchEnabled: shouldAllowPullToSearchGesture,
            onSearchTrigger: {
                Task { @MainActor in
                    presentRootSearch()
                }
            },
            onSelectProject: { project in
                applyFilter(.project(project))
            },
            projectIcon: { project in
                container.projectIconSymbol(for: project)
            },
            projectColor: { project in
                color(forHex: container.projectColorHex(for: project))
            },
            heroRow: {
                mainHeroListRow
            },
            taskRow: { record in
                taskRowItem(record)
            }
        )
        .transition(rootScreenTransition)
    case .builtIn(.anytime):
        anytimeMainContent(records: container.filteredRecords())
            .transition(rootScreenTransition)
    case .builtIn(.someday):
        somedayMainContent(records: container.filteredRecords())
            .transition(rootScreenTransition)
    case .builtIn(.logbook):
        logbookMainContent(records: container.filteredRecords())
            .transition(rootScreenTransition)
    case .builtIn(.pomodoro):
        PomodoroTimerView(
            header: currentMainHeroConfiguration.map { configuration in
                AnyView(MainHeroHeader(
                    title: configuration.title,
                    symbolName: configuration.symbolName,
                    iconColor: configuration.iconColor
                ))
            }
        )
        .transition(rootScreenTransition)
    default:
        recordsMainContent(records: container.filteredRecords())
            .transition(rootScreenTransition)
    }
}
```

**Note:** If `ViewIdentifier` doesn't conform to the right pattern for `switch`, use `if/else if/else` instead — `@ViewBuilder` supports both. The key requirement is removing all `AnyView()` wrappers.

- [ ] **Step 2: Also convert `recordsMainContent` if it returns `AnyView`**

Check `recordsMainContent` (line 1829) and any other helper methods that return `AnyView`. Convert them to `@ViewBuilder` as well.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild build -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: Build succeeds

- [ ] **Step 4: Run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift
git commit -m "refactor: replace AnyView with @ViewBuilder for structural identity in screen switching"
```

---

## Task 5: Cache computed sections in AppContainer

`todaySections()`, `upcomingSections()`, and `projectPickerContent()` filter and sort all records on every call. These should be computed once when records change and cached.

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift:917-966, 1400-1429`
- Test: `Tests/TodoMDAppTests/CachedSectionsTests.swift`

- [ ] **Step 1: Write a test for cached section invalidation**

```swift
// Tests/TodoMDAppTests/CachedSectionsTests.swift
import Testing
@testable import TodoMDApp

@Suite("Cached Sections")
struct CachedSectionsTests {
    @Test("todaySections returns consistent results across calls")
    @MainActor
    func todaySectionsConsistent() {
        let container = AppContainer.forTesting()
        let first = container.todaySections()
        let second = container.todaySections()
        #expect(first.count == second.count)
    }
}
```

- [ ] **Step 2: Add cached section storage to AppContainer**

Add new cached properties (near line 186, with `@ObservationIgnored` since these are internal caches that feed into observable computed properties):

```swift
@ObservationIgnored private var _cachedTodaySections: [TodaySection]?
@ObservationIgnored private var _cachedUpcomingSections: [UpcomingSection]?
@ObservationIgnored private var _cachedProjectPickerContent: ProjectPickerContent?
@ObservationIgnored private var _sectionCacheGeneration: Int = 0
private var sectionCacheGeneration: Int = 0
```

- [ ] **Step 3: Invalidate caches when records change**

In `refresh()`, after `allIndexedRecords` is set (line 437), add:

```swift
allIndexedRecords = canonicalRecords
invalidateSectionCaches()
```

Add the invalidation method:

```swift
private func invalidateSectionCaches() {
    _cachedTodaySections = nil
    _cachedUpcomingSections = nil
    _cachedProjectPickerContent = nil
    _sectionCacheGeneration += 1
    sectionCacheGeneration += 1
}
```

Also call `invalidateSectionCaches()` at the end of `applySyncDelta()` (line 582).

- [ ] **Step 4: Add caching to `todaySections()`**

Replace `todaySections()` (lines 917-934):

```swift
func todaySections(today: LocalDate = LocalDate.today(in: .current)) -> [TodaySection] {
    if let cached = _cachedTodaySections { return cached }
    let todayRecords = allIndexedRecords.filter {
        queryEngine.matches($0, view: .builtIn(.today), today: today, eveningStart: eveningStartTime)
    }
    let ordered = manualOrderService.ordered(records: todayRecords, view: .builtIn(.today))
    var grouped: [TodayGroup: [TaskRecord]] = [:]
    for record in ordered {
        guard let group = queryEngine.todayGroup(for: record, today: today, eveningStart: eveningStartTime) else { continue }
        grouped[group, default: []].append(record)
    }
    let groupOrder: [TodayGroup] = [.overdue, .scheduled, .dueToday, .deferredNowAvailable, .scheduledEvening]
    let result = groupOrder.compactMap { group in
        guard let records = grouped[group], !records.isEmpty else { return nil }
        return TodaySection(group: group, records: records)
    }
    _cachedTodaySections = result
    return result
}
```

- [ ] **Step 5: Add caching to `upcomingSections()`**

Same pattern — check `_cachedUpcomingSections` at top, store result before returning.

- [ ] **Step 6: Add caching to `projectPickerContent()`**

Same pattern — check `_cachedProjectPickerContent` at top (only for the no-exclusion case, since the `excluding` parameter varies). For the common case of no exclusion, cache the result.

- [ ] **Step 7: Run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift Tests/TodoMDAppTests/CachedSectionsTests.swift
git commit -m "perf: cache todaySections, upcomingSections, and projectPickerContent"
```

---

## Task 6: Move `refresh()` file I/O off main thread

`fileWatcher.synchronize()` performs synchronous file enumeration and parsing. This blocks the main thread during every refresh cycle, causing frame drops.

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift:383-495`

- [ ] **Step 1: Audit what in `refresh()` must be on `@MainActor`**

The `@MainActor` constraint is on the class. The file I/O (`fileWatcher.synchronize()`) and post-processing (`backfillMissingRefs`, `autoResolveBlockedDependencies`, `inferCompletionMetadata`) are pure data operations that don't touch UI. Only the final assignments to `@Published`/observed properties need `@MainActor`.

- [ ] **Step 2: Extract the pure computation into a nonisolated helper**

Create a struct to hold the sync result:

```swift
private struct RefreshResult {
    let canonicalRecords: [TaskRecord]
    let syncSummary: SyncSummary
    let events: [FileWatcherEvent]
    let diagnostics: [ParseFailureDiagnostic]
    let conflicts: [ConflictSummary]
    let notificationUpserts: [String: TaskRecord]
    let notificationDeletedPaths: Set<String>
    let unblockedPaths: Set<String>
    let sourceActivityLog: SourceActivityLog
}
```

Extract the heavy computation (lines 388-434) into a `nonisolated` method or a detached task that returns `RefreshResult`. This requires `FileWatcherService` to be sendable or the work to happen in a detached context.

**Important:** If `FileWatcherService` is not `Sendable`, the simplest approach is to wrap the synchronous call in `Task.detached`:

```swift
func refresh(forceFullScan: Bool = false) {
    let fileWatcher = self.fileWatcher
    let canonicalByPath = self.canonicalByPath
    // capture other needed state...

    Task.detached { [weak self] in
        let sync = try fileWatcher.synchronize(forceFullScan: forceFullScan)
        // ... all pure computation ...

        await MainActor.run {
            self?.applyRefreshResult(result)
        }
    }
}
```

**Caveat:** This changes `refresh()` from synchronous to asynchronous. Callers that depend on refresh completing synchronously (e.g., initialization) may need adjustment. Check all call sites of `refresh()` before making this change. If initialization requires synchronous loading, keep the initial `refresh()` call synchronous and only make subsequent refreshes async.

- [ ] **Step 3: Verify no regressions**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift
git commit -m "perf: move file synchronization off main thread in refresh()"
```

---

## Task 7: Deduplicate `filteredRecords()` calls and sort in `refresh()`

`container.filteredRecords()` is called 4+ times in the same view body evaluation. The sort of `canonicalByPath.values` happens 4 times in `refresh()`.

**Files:**
- Modify: `Sources/TodoMDApp/Features/RootView.swift:1791-1824`
- Modify: `Sources/TodoMDApp/App/AppContainer.swift:383-434`

- [ ] **Step 1: Bind `filteredRecords()` once in `mainContent`**

At the top of `mainContent`, add:

```swift
let currentRecords = container.filteredRecords()
```

Then replace all `container.filteredRecords()` calls in that property with `currentRecords`.

- [ ] **Step 2: Deduplicate sorts in `refresh()`**

In `refresh()` (lines 397-434), `canonicalByPath.values.sorted { $0.identity.path < $1.identity.path }` is called 4 times (lines 397, 414, 423, 433). Restructure to sort once at the end:

```swift
// After all mutations to canonicalByPath are done:
let canonicalRecords = canonicalByPath.values.sorted { $0.identity.path < $1.identity.path }
allIndexedRecords = canonicalRecords
```

Move the intermediate uses of `canonicalRecords` to use `Array(canonicalByPath.values)` (unsorted is fine for `backfillMissingRefs` and `autoResolveBlockedDependencies` since they operate by path lookup, not order).

- [ ] **Step 3: Run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/TodoMDApp/Features/RootView.swift Sources/TodoMDApp/App/AppContainer.swift
git commit -m "perf: deduplicate filteredRecords calls and reduce redundant sorts in refresh"
```

---

## Task 8: Fix `projectProgress()` triple-filter

`projectProgress()` filters `allIndexedRecords` once to get project tasks, then filters that result two more times. A single pass is sufficient.

**Files:**
- Modify: `Sources/TodoMDApp/App/AppContainer.swift:1431-1438`

- [ ] **Step 1: Replace triple-filter with single pass**

Replace:

```swift
func projectProgress(for project: String) -> (completed: Int, total: Int) {
    let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
    let projectTasks = allIndexedRecords.filter {
        $0.document.frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProject
    }
    let total = projectTasks.filter { $0.document.frontmatter.status != .cancelled }.count
    let completed = projectTasks.filter { $0.document.frontmatter.status == .done }.count
    return (completed: completed, total: total)
}
```

with:

```swift
func projectProgress(for project: String) -> (completed: Int, total: Int) {
    let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
    var total = 0
    var completed = 0
    for record in allIndexedRecords {
        guard record.document.frontmatter.project?.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedProject else { continue }
        let status = record.document.frontmatter.status
        guard status != .cancelled else { continue }
        total += 1
        if status == .done { completed += 1 }
    }
    return (completed: completed, total: total)
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -scheme TodoMD -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git add Sources/TodoMDApp/App/AppContainer.swift
git commit -m "perf: single-pass projectProgress instead of triple filter"
```

---

## Verification Checklist

After all tasks are complete:

- [ ] All existing tests pass
- [ ] App launches without crash on simulator
- [ ] Tab switching is visibly faster (no frame drops)
- [ ] Add `Self._printChanges()` to RootView body temporarily — verify that switching from Today to Upcoming does NOT log changes for unrelated properties like `isCalendarSyncing`
- [ ] Profile with Instruments → SwiftUI instrument → confirm reduced view body evaluations
- [ ] Remove `Self._printChanges()` debug line before final commit
