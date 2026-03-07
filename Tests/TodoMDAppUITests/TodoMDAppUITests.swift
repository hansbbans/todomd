import Foundation
import XCTest

@MainActor
final class TodoMDAppUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingDefaultFolderThenQuickAddCreatesTaskAndAppStaysResponsive() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"
        app.launch()

        let nextButton = app.buttons["onboarding.nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "Onboarding did not appear")

        nextButton.tap()
        nextButton.tap()

        let useDefaultButton = app.buttons["onboarding.useDefaultButton"]
        XCTAssertTrue(useDefaultButton.waitForExistence(timeout: 10))
        useDefaultButton.tap()

        let getStartedButton = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 10))
        XCTAssertTrue(getStartedButton.isEnabled)
        getStartedButton.tap()

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10))
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10))
        titleInput.tap()
        titleInput.typeText("test")
        submitInlineTask(from: app)

        let createdTaskRow = app.descendants(matching: .any)["taskRow.test"]
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Created task was not visible")

        addButton.tap()
        XCTAssertTrue(titleInput.waitForExistence(timeout: 5), "Inline task composer did not reopen")
    }

    func testInlineQuickAddUsesNaturalLanguageDueDate() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        titleInput.tap()
        titleInput.typeText("buy cookies due tomorrow")
        submitInlineTask(from: app)

        let createdTaskRow = app.descendants(matching: .any)["taskRow.buy cookies"]
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Inline add did not strip the natural-language due phrase")
        XCTAssertTrue(app.staticTexts["Tomorrow"].waitForExistence(timeout: 10), "Created task did not show the parsed due date")
    }

    func testMarkingTaskDoneRemovesItFromInboxImmediately() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "done regression")

        let checkbox = app.buttons["taskRow.done regression"].firstMatch
        let rowLabel = app.staticTexts["taskRow.done regression"].firstMatch
        XCTAssertTrue(rowLabel.waitForExistence(timeout: 10), "Created task row was not visible before completion")

        XCTAssertTrue(checkbox.waitForExistence(timeout: 10), "Completion checkbox was not visible before completion")
        checkbox.tap()

        let rowRemoved = NSPredicate(format: "exists == false")
        expectation(for: rowRemoved, evaluatedWith: rowLabel)
        waitForExpectations(timeout: 5)
    }

    func testOnboardingDefaultFolderAllowsColdRelaunch() {
        let storageOverride = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        XCTAssertTrue(rootViewReached(app: app, timeout: 10), "App did not reach root view after onboarding")

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments += ["-ui-testing"]
        relaunchedApp.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        relaunchedApp.launch()

        XCTAssertTrue(rootViewReached(app: relaunchedApp, timeout: 10), "App did not relaunch into the root view after onboarding")
    }

    func testRemindersImportEndToEndWithFakeSource() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"
        app.launchEnvironment["TODOMD_FAKE_REMINDERS_IMPORT"] = "1"
        app.launch()

        completeOnboarding(app: app)

        openSettings(app: app)

        let remindersImportSection = app.buttons["settings.section.remindersImport"]
        XCTAssertTrue(remindersImportSection.waitForExistence(timeout: 10), "Reminders Import section not visible")
        remindersImportSection.tap()

        let importRow = app.descendants(matching: .any)["settings.remindersImport.row.ui-test-reminder-1"]
        let importAllButton = app.descendants(matching: .any)["settings.remindersImport.importAllButton"]
        var scrollAttempts = 0
        while !importRow.exists && !importAllButton.exists && scrollAttempts < 6 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(importRow.waitForExistence(timeout: 10), "Pending reminders row not visible")

        let refreshButton = app.descendants(matching: .any)["settings.remindersImport.refreshListsButton"]
        if refreshButton.exists {
            refreshButton.tap()
        }

        XCTAssertTrue(importAllButton.waitForExistence(timeout: 10), "Import all button not visible")
        XCTAssertTrue(importAllButton.isHittable)
        importAllButton.tap()

        let status = app.staticTexts["settings.remindersImport.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Import status did not appear")
        XCTAssertTrue(status.label.contains("Imported 1 reminder"))
        XCTAssertFalse(importRow.waitForExistence(timeout: 5), "Imported reminder should no longer be listed as pending")
    }

    func testPomodoroCanBeEnabledAndOpenedFromAreas() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"
        app.launch()

        completeOnboarding(app: app)

        openSettings(app: app)

        let taskBehaviorSection = app.buttons["settings.section.taskBehavior"]
        XCTAssertTrue(taskBehaviorSection.waitForExistence(timeout: 10), "Task Behavior section not visible")
        taskBehaviorSection.tap()

        let pomodoroToggle = app.switches["settings.taskBehavior.pomodoroToggle"]
        XCTAssertTrue(pomodoroToggle.waitForExistence(timeout: 10), "Pomodoro toggle not visible")
        if (pomodoroToggle.value as? String) != "1" {
            pomodoroToggle.tap()
        }

        for _ in 0..<2 {
            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 10))
            backButton.tap()
        }

        let pomodoroButton = app.buttons["Pomodoro"].firstMatch
        XCTAssertTrue(pomodoroButton.waitForExistence(timeout: 10), "Pomodoro entry not visible in Areas")
        pomodoroButton.tap()

        XCTAssertTrue(app.navigationBars["Pomodoro"].waitForExistence(timeout: 10), "Pomodoro view did not open")
    }

    func testInboxTriagePriorityAssignmentCanAdvanceQueue() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "triage single")

        let triageToggle = app.buttons["root.triageToggle"]
        XCTAssertTrue(triageToggle.waitForExistence(timeout: 10), "Triage toggle not visible")
        triageToggle.tap()

        let triageCard = app.descendants(matching: .any)["triage.card"]
        XCTAssertTrue(triageCard.waitForExistence(timeout: 10), "Triage card did not appear")

        let highPriorityButton = app.buttons["1 High"]
        XCTAssertTrue(highPriorityButton.waitForExistence(timeout: 10), "Priority shortcuts not visible in triage")
        highPriorityButton.tap()

        let nextButton = app.buttons["triage.nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "Next button not visible in triage")
        nextButton.tap()

        let emptyState = app.descendants(matching: .any)["triage.emptyState"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "Triage queue did not advance to completion state")
    }

    private func completeOnboarding(app: XCUIApplication) {
        let nextButton = app.buttons["onboarding.nextButton"]
        let useDefaultButton = app.buttons["onboarding.useDefaultButton"]
        let getStartedButton = app.buttons["onboarding.getStartedButton"]

        let timeout = Date().addingTimeInterval(25)
        while Date() < timeout {
            if rootViewReached(app: app) {
                return
            }

            if getStartedButton.exists, getStartedButton.isHittable, getStartedButton.isEnabled {
                getStartedButton.tap()
                continue
            }

            if nextButton.exists, nextButton.isHittable {
                nextButton.tap()
                continue
            }

            if useDefaultButton.exists, useDefaultButton.isHittable {
                useDefaultButton.tap()
                continue
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }

        XCTAssertTrue(rootViewReached(app: app, timeout: 5), "App did not reach root view")
    }

    private func rootViewReached(app: XCUIApplication, timeout: TimeInterval = 0) -> Bool {
        let addButton = app.buttons["root.inlineAddButton"]
        let areasTab = app.tabBars.buttons["Areas"]
        guard timeout > 0 else {
            return addButton.exists || areasTab.exists
        }
        return addButton.waitForExistence(timeout: timeout) || areasTab.waitForExistence(timeout: timeout)
    }

    private func createTask(app: XCUIApplication, title: String) {
        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        titleInput.tap()
        titleInput.typeText(title)
        submitInlineTask(from: app)

        let createdTaskRow = app.descendants(matching: .any)["taskRow.\(title)"]
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Created task row was not visible")
    }

    private func openSettings(app: XCUIApplication) {
        let areasTab = app.tabBars.buttons["Areas"]
        XCTAssertTrue(areasTab.waitForExistence(timeout: 10), "Areas tab not visible")
        areasTab.tap()

        let settingsButton = app.buttons["root.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings button not visible in Areas")
        settingsButton.tap()
    }

    private func submitInlineTask(from app: XCUIApplication) {
        if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
            return
        }
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
            return
        }
        if app.keyboards.buttons["return"].exists {
            app.keyboards.buttons["return"].tap()
            return
        }
        app.typeText("\n")
    }

    private func makeStorageOverridePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .path
    }
}
