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

        let importRow = app.buttons["from reminders e2e"].firstMatch
        let importAllButton = app.buttons["Import All"].firstMatch
        XCTAssertTrue(importRow.waitForExistence(timeout: 10), "Pending reminders row not visible")

        XCTAssertTrue(importAllButton.waitForExistence(timeout: 10), "Import all button not visible")
        XCTAssertTrue(importAllButton.isHittable)
        importAllButton.tap()

        XCTAssertFalse(importRow.waitForExistence(timeout: 5), "Imported reminder should no longer be listed as pending")

        let importedTaskRow = app.descendants(matching: .any)["taskRow.from reminders e2e"].firstMatch
        XCTAssertTrue(
            importedTaskRow.waitForExistence(timeout: 10),
            "Imported reminder task should appear in Inbox immediately without force-closing the app"
        )

        let importSummary = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Imported 1 reminder")).firstMatch
        XCTAssertTrue(importSummary.waitForExistence(timeout: 10), "Import summary did not appear in Inbox")
    }

    func testProjectCanBeDuplicatedFromSettings() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let browseTab = app.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(browseTab.waitForExistence(timeout: 10), "Browse tab not visible")
        browseTab.tap()

        let createProjectButton = app.buttons["Create Project"].firstMatch
        XCTAssertTrue(createProjectButton.waitForExistence(timeout: 10), "Create Project action not visible")
        createProjectButton.tap()

        let projectNameField = app.textFields["projectSheet.nameField"].firstMatch
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 10), "Project name field did not appear")
        projectNameField.tap()
        projectNameField.typeText("Weekly Template")

        let createButton = app.buttons["projectSheet.createButton"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 10), "Project create button did not appear")
        createButton.tap()

        createTask(app: app, title: "Plan meals")
        XCTAssertTrue(
            waitForMarkdownStorage(rootPath: storageOverride) { content in
                content.contains("Plan meals") && content.contains("Weekly Template")
            },
            "Created project task was not persisted to disk"
        )

        app.terminate()

        let relaunchedApp = XCUIApplication()
        relaunchedApp.launchArguments += ["-ui-testing"]
        relaunchedApp.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        relaunchedApp.launch()

        XCTAssertTrue(rootViewReached(app: relaunchedApp, timeout: 10), "App did not relaunch into the root view")

        let relaunchedBrowseTab = relaunchedApp.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(relaunchedBrowseTab.waitForExistence(timeout: 10), "Browse tab not visible after relaunch")
        relaunchedBrowseTab.tap()

        let editProjectButton = relaunchedApp.buttons["project.edit.Weekly Template"].firstMatch
        XCTAssertTrue(editProjectButton.waitForExistence(timeout: 10), "Project settings button not visible")
        editProjectButton.tap()

        let duplicateProjectButton = relaunchedApp.buttons["projectSettings.duplicateButton"].firstMatch
        XCTAssertTrue(duplicateProjectButton.waitForExistence(timeout: 10), "Duplicate Project action not visible")
        duplicateProjectButton.tap()

        let duplicateButton = relaunchedApp.buttons["projectSheet.duplicateButton"].firstMatch
        XCTAssertTrue(duplicateButton.waitForExistence(timeout: 10), "Project duplicate button did not appear")
        let duplicateNameField = relaunchedApp.textFields["projectSheet.nameField"].firstMatch
        XCTAssertTrue(duplicateNameField.waitForExistence(timeout: 10), "Project duplicate name field did not appear")
        XCTAssertEqual(
            duplicateNameField.value as? String,
            "Weekly Template Copy",
            "Duplicate flow did not prefill the expected project name"
        )
        XCTAssertTrue(duplicateButton.isEnabled, "Project duplicate button should be enabled")
        duplicateButton.tap()
        XCTAssertTrue(
            waitForFileContents(
                at: URL(fileURLWithPath: storageOverride, isDirectory: true).appendingPathComponent(".projects.json"),
                containing: "Weekly Template Copy"
            ),
            "Duplicated project metadata was not persisted to disk"
        )
        XCTAssertTrue(
            waitForMarkdownStorage(rootPath: storageOverride) { content in
                content.contains("Plan meals") && content.contains("Weekly Template Copy")
            },
            "Duplicated project task was not persisted to disk"
        )

        relaunchedApp.terminate()

        let verificationApp = XCUIApplication()
        verificationApp.launchArguments += ["-ui-testing"]
        verificationApp.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        verificationApp.launch()

        XCTAssertTrue(rootViewReached(app: verificationApp, timeout: 10), "App did not relaunch after duplication")

        let verificationBrowseTab = verificationApp.tabBars.buttons["Browse"].firstMatch
        XCTAssertTrue(verificationBrowseTab.waitForExistence(timeout: 10), "Browse tab not visible after duplication")
        verificationBrowseTab.tap()

        let copiedProjectEditButton = verificationApp.buttons["project.edit.Weekly Template Copy"].firstMatch
        XCTAssertTrue(copiedProjectEditButton.waitForExistence(timeout: 10), "Duplicated project was not listed in Browse")

        let copiedProjectButton = verificationApp.buttons["Weekly Template Copy"].firstMatch
        XCTAssertTrue(copiedProjectButton.waitForExistence(timeout: 10), "Duplicated project button was not visible")
        copiedProjectButton.tap()

        let copiedTaskRow = verificationApp.descendants(matching: .any)["taskRow.Plan meals"].firstMatch
        XCTAssertTrue(copiedTaskRow.waitForExistence(timeout: 10), "Duplicated project did not contain the copied task")
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

    private func waitForFileContents(
        at url: URL,
        containing needle: String,
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.2
    ) -> Bool {
        waitForCondition(timeout: timeout, pollInterval: pollInterval) {
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8) else {
                return false
            }
            return content.contains(needle)
        }
    }

    private func waitForMarkdownStorage(
        rootPath: String,
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.2,
        predicate: (String) -> Bool
    ) -> Bool {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)

        return waitForCondition(timeout: timeout, pollInterval: pollInterval) {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return false
            }

            for url in urls where url.pathExtension == "md" {
                guard let data = try? Data(contentsOf: url),
                      let content = String(data: data, encoding: .utf8) else {
                    continue
                }
                if predicate(content) {
                    return true
                }
            }

            return false
        }
    }

    private func waitForCondition(
        timeout: TimeInterval,
        pollInterval: TimeInterval,
        predicate: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return predicate()
    }
}
