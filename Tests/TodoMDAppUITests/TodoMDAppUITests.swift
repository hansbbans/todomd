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

        dismissIntegrationPrimersIfNeeded(app: app)

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

    func testOnboardingShowsIntegrationPrimersBeforeEnteringHomeScreen() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        let nextButton = app.buttons["onboarding.nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 10), "Onboarding did not appear")
        nextButton.tap()
        nextButton.tap()

        let useDefaultButton = app.buttons["onboarding.useDefaultButton"]
        XCTAssertTrue(useDefaultButton.waitForExistence(timeout: 10), "Default folder option did not appear")
        useDefaultButton.tap()

        let getStartedButton = app.buttons["onboarding.getStartedButton"]
        XCTAssertTrue(getStartedButton.waitForExistence(timeout: 10), "Get Started button did not appear")
        getStartedButton.tap()

        let primerModal = app.otherElements["onboarding.accessPrimer.modal"].firstMatch
        XCTAssertTrue(primerModal.waitForExistence(timeout: 10), "An integration primer did not appear before entering the app")
        let primerTitle = app.staticTexts["onboarding.accessPrimer.title"].firstMatch
        XCTAssertTrue(primerTitle.waitForExistence(timeout: 5), "Reminders primer title was not visible")
        XCTAssertTrue(
            ["Allow Reminders Access", "Allow Calendar Access"].contains(primerTitle.label),
            "Unexpected onboarding primer title: \(primerTitle.label)"
        )

        let skipButton = app.buttons["onboarding.accessPrimer.skipButton"].firstMatch
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5), "Primer dismiss button was not visible")
        let initialPrimerTitle = primerTitle.label
        skipButton.tap()

        if initialPrimerTitle == "Allow Reminders Access",
           primerModal.waitForExistence(timeout: 5)
        {
            XCTAssertEqual(primerTitle.label, "Allow Calendar Access")
            skipButton.tap()
        }

        XCTAssertTrue(rootViewReached(app: app, timeout: 10), "App did not reach the home screen after onboarding primers")
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
        XCTAssertTrue(
            createdTaskRow.waitForExistence(timeout: 10),
            "Inline add did not strip the natural-language due phrase"
        )
        XCTAssertTrue(
            app.staticTexts["Tomorrow"].waitForExistence(timeout: 10),
            "Created task did not show the parsed due date"
        )
    }

    func testRegularWidthInlineComposerAppearsBelowExistingTasks() throws {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let settingsButton = app.buttons["root.settingsButton"].firstMatch
        try XCTSkipUnless(
            settingsButton.waitForExistence(timeout: 5),
            "This regression only applies to regular-width layouts."
        )

        createTask(app: app, title: "placement first")
        createTask(app: app, title: "placement second")

        let firstRow = app.descendants(matching: .any)["taskRow.placement first"].firstMatch
        let secondRow = app.descendants(matching: .any)["taskRow.placement second"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "First seeded task row was not visible")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10), "Second seeded task row was not visible")

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                let lastTaskBottom = max(firstRow.frame.maxY, secondRow.frame.maxY)
                return titleInput.frame.minY >= lastTaskBottom - 2
            },
            "Inline composer should appear below the existing task rows on regular-width layouts"
        )
    }

    func testMarkingTaskDoneRemovesItFromInboxImmediately() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "done regression")

        let row = app.descendants(matching: .any)["taskRow.done regression"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Created task row was not visible before completion")
        completeTask(app: app, title: "done regression")

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) { !row.exists },
            "Completed task row should disappear from Inbox immediately"
        )
    }

    func testNewInboxTaskAppendsBelowExistingTasksOnCompactLayout() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "append first")
        createTask(app: app, title: "append second")

        let firstRow = app.descendants(matching: .any)["taskRow.append first"].firstMatch
        let secondRow = app.descendants(matching: .any)["taskRow.append second"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "First seeded task row was not visible")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10), "Second seeded task row was not visible")

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        titleInput.tap()
        titleInput.typeText("append third")
        submitInlineTask(from: app)

        let thirdRow = app.descendants(matching: .any)["taskRow.append third"].firstMatch
        XCTAssertTrue(thirdRow.waitForExistence(timeout: 10), "New task row was not visible")
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                let existingBottom = max(firstRow.frame.maxY, secondRow.frame.maxY)
                return thirdRow.frame.minY >= existingBottom - 2
            },
            "New tasks should append below the existing task rows instead of jumping to the top"
        )
    }

    func testInlineComposerShowsKeyboardAfterTappingAdd() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "Keyboard did not appear after opening the inline composer"
        )
    }

    func testInlineComposerKeyboardCheckmarkCreatesTask() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear for inline task entry")
        titleInput.typeText("keyboard checkmark inbox")

        let keyboardCommitButton = app.buttons["inlineTask.keyboardCommitButton"].firstMatch
        if keyboardCommitButton.waitForExistence(timeout: 3), keyboardCommitButton.isHittable {
            keyboardCommitButton.tap()
        } else {
            submitInlineTask(from: app)
        }

        let createdTaskRow = app.descendants(matching: .any)["taskRow.keyboard checkmark inbox"].firstMatch
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Keyboard checkmark did not create the task")
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) { !titleInput.exists },
            "Inline composer did not dismiss after confirming from the keyboard"
        )
    }

    func testInlineComposerKeyboardReturnCreatesTask() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Keyboard did not appear for inline task entry")
        titleInput.typeText("keyboard return inbox")
        app.typeText("\n")

        let createdTaskRow = app.descendants(matching: .any)["taskRow.keyboard return inbox"].firstMatch
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Keyboard return did not create the task")
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) { !titleInput.exists },
            "Inline composer did not dismiss after pressing the keyboard return key"
        )
    }

    func testTappingBlankListSpaceCollapsesExpandedTask() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "collapse on blank space")

        let taskRow = app.descendants(matching: .any)["taskRow.collapse on blank space"].firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 10), "Task row was not visible")
        taskRow.tap()

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (taskRow.value as? String) == "expanded"
            },
            "Task did not expand before tapping the list background"
        )

        let appFrame = app.frame
        let blankY = min(appFrame.maxY - 120, taskRow.frame.maxY + 140)
        let blankCoordinate = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: taskRow.frame.midX, dy: blankY))
        blankCoordinate.tap()

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (taskRow.value as? String) == "collapsed"
            },
            "Tapping the empty part of the list should collapse the expanded task"
        )
    }

    func testInlineComposerOpensExpandedAtTopOfInboxList() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "composer first")
        createTask(app: app, title: "composer second")

        let firstRow = app.descendants(matching: .any)["taskRow.composer first"].firstMatch
        let secondRow = app.descendants(matching: .any)["taskRow.composer second"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "First seeded task row was not visible")
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10), "Second seeded task row was not visible")

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        let notesInput = app.textFields["inlineTask.notesField"].firstMatch
        XCTAssertTrue(notesInput.waitForExistence(timeout: 10), "New task creation should open with the expanded notes field visible")

        let composerRow = app.descendants(matching: .any)["inlineTask.row"].firstMatch
        XCTAssertTrue(
            composerRow.waitForExistence(timeout: 2),
            "Inline composer row was not visible"
        )
        XCTAssertEqual(composerRow.value as? String, "expanded", "New task composer should open expanded")

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                let firstExistingTop = min(firstRow.frame.minY, secondRow.frame.minY)
                return composerRow.frame.maxY <= firstExistingTop + 2
            },
            "New task composer should appear above the existing tasks at the top of the list"
        )

        let referenceHeight = max(firstRow.frame.height, secondRow.frame.height)
        XCTAssertGreaterThanOrEqual(
            composerRow.frame.height,
            referenceHeight + 40,
            "New task composer should open as an expanded row instead of a collapsed task row"
        )
    }

    func testTaskDetailProjectAssignmentPersistsImmediately() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "immediate project save")

        let taskRow = app.descendants(matching: .any)["taskRow.immediate project save"].firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 10), "Created task row was not visible")
        taskRow.tap()

        let moreButton = app.buttons["More"].firstMatch
        let legacyMoreButton = app.buttons["Open full task editor"].firstMatch
        XCTAssertTrue(
            moreButton.waitForExistence(timeout: 2) || legacyMoreButton.waitForExistence(timeout: 10),
            "Expanded task detail action button was not visible"
        )
        if moreButton.exists {
            moreButton.tap()
        } else {
            legacyMoreButton.tap()
        }

        let projectField = app.textFields["taskDetail.field.project"].firstMatch
        if !projectField.waitForExistence(timeout: 2) {
            let moreDetailsButton = app.buttons["More details"].firstMatch
            XCTAssertTrue(moreDetailsButton.waitForExistence(timeout: 10), "More details toggle was not visible")
            moreDetailsButton.tap()
        }

        XCTAssertTrue(projectField.waitForExistence(timeout: 10), "Project field was not visible in task detail")
        projectField.tap()
        projectField.typeText("Errands")

        XCTAssertTrue(
            waitForMarkdownStorage(rootPath: storageOverride) { content in
                content.contains("immediate project save")
                    && (content.contains("project: Errands") || content.contains("project: \"Errands\""))
            },
            "Project assignment from task detail was not persisted before leaving the editor"
        )
    }

    func testInlineTaskDateButtonUsesSharedDateChooserAndPersistsDueTime() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let dateButton = app.buttons["inlineTask.dateButton"].firstMatch
        XCTAssertTrue(dateButton.waitForExistence(timeout: 10), "Inline task date button was not visible")
        dateButton.tap()

        let popup = app.otherElements["inlineTaskDate.modal"].firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 10), "Date chooser should open in a distinct popup")

        let tonightPreset = app.descendants(matching: .any)["dateChooser.due.preset.tonight"].firstMatch
        XCTAssertTrue(tonightPreset.waitForExistence(timeout: 10), "Tonight preset was not visible in inline task creation")
        tonightPreset.tap()

        let closeButton = app.buttons["inlineTaskDate.closeButton"].firstMatch
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10), "Inline date popup close button was not visible")
        closeButton.tap()
        XCTAssertFalse(popup.waitForExistence(timeout: 1), "Date chooser popup should dismiss after tapping Done")

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        titleInput.tap()
        titleInput.typeText("inline tonight chooser")
        submitInlineTask(from: app)

        XCTAssertTrue(
            waitForMarkdownStorage(rootPath: storageOverride) { content in
                content.contains("inline tonight chooser") && content.contains("due_time:")
            },
            "Inline task creation should persist a due time when Tonight is selected"
        )
    }

    func testInlineTaskDateButtonOpensDateChooserExpandedAtTop() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let dateButton = app.buttons["inlineTask.dateButton"].firstMatch
        XCTAssertTrue(dateButton.waitForExistence(timeout: 10), "Inline task date button was not visible")
        dateButton.tap()

        let popup = app.otherElements["inlineTaskDate.modal"].firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 10), "Date chooser should open in a distinct popup")

        XCTAssertTrue(
            waitForCondition(timeout: 3, pollInterval: 0.1) {
                popup.frame.minY <= app.frame.height * 0.18
            },
            "Date chooser should open expanded near the top of the screen instead of requiring an upward drag"
        )
    }

    func testInlineComposerUsesIconToolbarAndProjectMenuSelection() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let browseTab = browseTabButton(in: app, timeout: 10)
        XCTAssertTrue(browseTab.exists, "Browse tab not visible")
        browseTab.tap()

        let createProjectButton = app.buttons["Create Project"].firstMatch
        XCTAssertTrue(createProjectButton.waitForExistence(timeout: 10), "Create Project action not visible")
        createProjectButton.tap()

        let projectNameField = app.textFields["projectSheet.nameField"].firstMatch
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 10), "Project name field did not appear")
        projectNameField.tap()
        projectNameField.typeText("Errands")

        let createButton = app.buttons["projectSheet.createButton"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 10), "Project create button did not appear")
        createButton.tap()

        let inboxTab = inboxTabButton(in: app, timeout: 10)
        XCTAssertTrue(inboxTab.exists, "Inbox tab not visible")
        inboxTab.tap()

        let addButton = app.buttons["root.inlineAddButton"].firstMatch
        XCTAssertTrue(addButton.waitForExistence(timeout: 10), "Inline add button not visible")
        addButton.tap()

        let dateButton = app.buttons["inlineTask.dateButton"].firstMatch
        let projectMenuButton = app.buttons["inlineTask.projectMenuButton"].firstMatch
        let tagsButton = app.buttons["inlineTask.tagsButton"].firstMatch
        let flagButton = app.buttons["inlineTask.flagButton"].firstMatch
        let commitButton = app.buttons["inlineTask.commitButton"].firstMatch
        let submitButton = app.buttons["inlineTask.submitButton"].firstMatch

        XCTAssertTrue(dateButton.waitForExistence(timeout: 10), "Date icon button was not visible")
        XCTAssertTrue(projectMenuButton.waitForExistence(timeout: 10), "Project menu icon was not visible")
        XCTAssertTrue(tagsButton.waitForExistence(timeout: 10), "Tags icon button was not visible")
        XCTAssertTrue(flagButton.waitForExistence(timeout: 10), "Flag icon button was not visible")
        XCTAssertFalse(commitButton.exists, "Inline task entry should no longer show the in-card checkmark button")
        XCTAssertFalse(submitButton.exists, "Inline task entry should no longer show a footer submit button")

        XCTAssertTrue(
            waitForCondition(timeout: 3, pollInterval: 0.1) {
                dateButton.frame.minX < tagsButton.frame.minX
                    && tagsButton.frame.minX < projectMenuButton.frame.minX
                    && projectMenuButton.frame.minX < flagButton.frame.minX
            },
            "Toolbar should use the new trailing icon order: date, tags, list, flag"
        )

        projectMenuButton.tap()

        let errandsMenuItem = app.buttons["inlineTask.projectMenuItem.Errands"].firstMatch
        XCTAssertTrue(errandsMenuItem.waitForExistence(timeout: 10), "Project menu did not show the created project")
        errandsMenuItem.tap()

        let titleInput = app.textFields["inlineTask.titleField"].firstMatch
        XCTAssertTrue(titleInput.waitForExistence(timeout: 10), "Inline task title field did not appear")
        titleInput.tap()
        titleInput.typeText("project menu assignment")
        submitInlineTask(from: app)

        XCTAssertTrue(
            waitForMarkdownStorage(rootPath: storageOverride) { content in
                content.contains("project menu assignment")
                    && (content.contains("project: Errands") || content.contains("project: \"Errands\""))
            },
            "Project chosen from the inline project menu was not persisted to markdown storage"
        )
    }

    func testTappingExpandedTaskRowCollapsesIt() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "collapse on retap")

        let taskRow = app.descendants(matching: .any)["taskRow.collapse on retap"].firstMatch
        XCTAssertTrue(taskRow.waitForExistence(timeout: 10), "Task row was not visible")

        taskRow.tap()
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (taskRow.value as? String) == "expanded"
            },
            "Task did not expand on first tap"
        )

        taskRow.tap()
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (taskRow.value as? String) == "collapsed"
            },
            "Task did not collapse when tapped again while expanded"
        )
    }

    func testQuickEntryKeyboardDoneCreatesTask() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding", "-ui-testing-show-quick-entry"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)

        let titleField = app.textFields["quickEntry.titleField"].firstMatch
        XCTAssertTrue(titleField.waitForExistence(timeout: 10), "QuickEntry sheet did not appear")
        titleField.tap()
        titleField.typeText("keyboard done test")

        if app.keyboards.buttons["Done"].waitForExistence(timeout: 3) {
            app.keyboards.buttons["Done"].tap()
        } else {
            app.typeText("\n")
        }

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                !titleField.exists
            },
            "QuickEntry sheet did not dismiss after pressing keyboard Done"
        )
    }

    func testSwitchingExpandedTasksCollapsesThePreviousCardWithoutShowingKeyboard() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)
        createTask(app: app, title: "smooth first")
        createTask(app: app, title: "smooth second")

        let firstRow = app.descendants(matching: .any)["taskRow.smooth first"].firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 10), "First task row was not visible")
        firstRow.tap()

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (firstRow.value as? String) == "expanded"
            },
            "First task did not expand"
        )
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Expanding a task should not auto-focus a text field")

        let secondRow = app.descendants(matching: .any)["taskRow.smooth second"].firstMatch
        XCTAssertTrue(secondRow.waitForExistence(timeout: 10), "Second task row was not visible")
        secondRow.tap()

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (secondRow.value as? String) == "expanded"
            },
            "Second task did not expand after tapping it"
        )
        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) {
                (firstRow.value as? String) == "collapsed"
            },
            "Switching tasks should collapse the previously expanded task"
        )
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Switching expanded tasks should not show the keyboard")
    }

    func testOnboardingDefaultFolderAllowsColdRelaunch() {
        let storageOverride = makeStorageOverridePath()

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

        XCTAssertTrue(
            rootViewReached(app: relaunchedApp, timeout: 10),
            "App did not relaunch into the root view after onboarding"
        )
    }

    func testRemindersImportEndToEndWithFakeSource() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launchEnvironment["TODOMD_FAKE_REMINDERS_IMPORT"] = "1"
        app.launch()

        completeOnboarding(app: app)

        let importRow = app.buttons["inbox.remindersImport.row.ui-test-reminder-1"].firstMatch
        let importAllButton = app.buttons["inbox.remindersImport.importAllButton"].firstMatch
        XCTAssertTrue(importRow.waitForExistence(timeout: 10), "Pending reminders row not visible")

        XCTAssertTrue(importAllButton.waitForExistence(timeout: 10), "Import all button not visible")
        XCTAssertTrue(importAllButton.isHittable)
        importAllButton.tap()

        XCTAssertTrue(
            waitForCondition(timeout: 5, pollInterval: 0.1) { !importRow.exists },
            "Imported reminder should no longer be listed as pending"
        )

        let importedTaskRow = app.descendants(matching: .any)["taskRow.from reminders e2e"].firstMatch
        XCTAssertTrue(
            importedTaskRow.waitForExistence(timeout: 10),
            "Imported reminder task should appear in Inbox immediately without force-closing the app"
        )

        let importSummary = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Imported 1 reminder"))
            .firstMatch
        XCTAssertTrue(importSummary.waitForExistence(timeout: 10), "Import summary did not appear in Inbox")
    }

    func testProjectCanBeDuplicatedFromSettings() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        let browseTab = browseTabButton(in: app)
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

        let relaunchedBrowseTab = browseTabButton(in: relaunchedApp)
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

        let verificationBrowseTab = browseTabButton(in: verificationApp)
        XCTAssertTrue(verificationBrowseTab.waitForExistence(timeout: 10), "Browse tab not visible after duplication")
        verificationBrowseTab.tap()

        let copiedProjectEditButton = verificationApp.buttons["project.edit.Weekly Template Copy"].firstMatch
        XCTAssertTrue(
            copiedProjectEditButton.waitForExistence(timeout: 10),
            "Duplicated project was not listed in Browse"
        )

        let copiedProjectButton = verificationApp.buttons["Weekly Template Copy"].firstMatch
        XCTAssertTrue(copiedProjectButton.waitForExistence(timeout: 10), "Duplicated project button was not visible")
        copiedProjectButton.tap()

        let copiedTaskRow = verificationApp.descendants(matching: .any)["taskRow.Plan meals"].firstMatch
        XCTAssertTrue(copiedTaskRow.waitForExistence(timeout: 10), "Duplicated project did not contain the copied task")
    }

    func testPullDownPresentsSearchModalWithStableInlineFieldAndLiveResults() {
        let storageOverride = makeStorageOverridePath()
        XCTAssertNoThrow(try seedMarkdownTask(rootPath: storageOverride, title: "search smoke"))

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launch()

        completeOnboarding(app: app)

        // Quick Find uses a floating overlay — no search field visible before opening
        let searchField = app.textFields["quickFind.searchField"].firstMatch

        XCTAssertFalse(
            searchField.exists && searchField.isHittable,
            "Quick Find search field should not be visible before the modal is opened"
        )

        if app.collectionViews.firstMatch.exists {
            app.collectionViews.firstMatch.swipeDown()
        } else if app.tables.firstMatch.exists {
            app.tables.firstMatch.swipeDown()
        } else {
            app.swipeDown()
        }

        // Quick Find is a floating overlay — no navigation bar, just the search field
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Pulling down should present the Quick Find modal with a search field")
        XCTAssertTrue(searchField.isHittable, "Search field should be interactive after pull-down")

        let initialMinY = searchField.frame.minY
        searchField.tap()
        XCTAssertEqual(
            searchField.frame.minY,
            initialMinY,
            accuracy: 12,
            "Focusing the search field should not reposition it"
        )
        searchField.typeText("search smoke")

        let taskResult = app.buttons["root.search.taskResult.search smoke"].firstMatch
        XCTAssertTrue(taskResult.waitForExistence(timeout: 5), "Typing should show matching task results in the modal")
    }

    func testPomodoroAppearsInBrowseWhenEnabled() {
        let storageOverride = makeStorageOverridePath()

        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = storageOverride
        app.launchEnvironment["TODOMD_UI_TEST_POMODORO_ENABLED"] = "1"
        app.launch()

        completeOnboarding(app: app)

        let browseTab = browseTabButton(in: app, timeout: 10)
        XCTAssertTrue(browseTab.exists, "Browse tab not visible")
        browseTab.tap()

        let pomodoroButton = app.buttons["root.browse.pomodoro"].firstMatch
        XCTAssertTrue(reveal(element: pomodoroButton, in: app), "Pomodoro entry not visible in Browse")
    }

    func testIntegrationsSettingsContainsCalendarAndNewInstallsStartDisabledWithoutAccess() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)
        openSettings(app: app)

        XCTAssertFalse(
            app.buttons["settings.section.calendar"].exists,
            "Calendar should be configured inside Integrations instead of a standalone Settings section"
        )

        let integrationsSection = app.buttons["settings.section.integrations"]
        XCTAssertTrue(integrationsSection.waitForExistence(timeout: 10), "Integrations section not visible")
        integrationsSection.tap()

        let remindersToggle = app.switches["settings.integrations.remindersToggle"].firstMatch
        let calendarToggle = app.switches["settings.integrations.calendarToggle"].firstMatch
        XCTAssertTrue(remindersToggle.waitForExistence(timeout: 10), "Reminders toggle not visible")
        XCTAssertTrue(calendarToggle.waitForExistence(timeout: 10), "Calendar toggle not visible")

        if app.buttons["settings.integrations.allowRemindersAccessButton"].exists {
            XCTAssertEqual(remindersToggle.value as? String, "0", "Reminders should stay off before access is granted")
        }

        if app.buttons["settings.integrations.allowCalendarAccessButton"].exists {
            XCTAssertEqual(calendarToggle.value as? String, "0", "Calendar should stay off before access is granted")
        }
    }

    func testBrowseTabShowsAnIconInCompactTabBar() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = makeStorageOverridePath()
        app.launch()

        completeOnboarding(app: app)

        let browseTab = app.tabBars.buttons["Browse"]
        XCTAssertTrue(browseTab.waitForExistence(timeout: 10), "Browse tab should render in the compact tab bar after onboarding")
        XCTAssertFalse(
            app.staticTexts["square.grid.2x2"].exists,
            "Browse tab should not render the raw SF Symbol name as visible text"
        )
    }

    func testInboxSmartTriageManualProjectAssignmentCanAdvanceQueue() throws {
        throw XCTSkip("Workflow placement is covered by RootNavigationCatalogTests; compact tab automation is still flaky in UI tests.")
    }

    private func completeOnboarding(app: XCUIApplication) {
        let nextButton = app.buttons["onboarding.nextButton"]
        let useDefaultButton = app.buttons["onboarding.useDefaultButton"]
        let getStartedButton = app.buttons["onboarding.getStartedButton"]
        let skipPrimerButton = app.buttons["onboarding.accessPrimer.skipButton"]

        let timeout = Date().addingTimeInterval(25)
        while Date() < timeout {
            if rootViewReached(app: app) {
                return
            }

            if skipPrimerButton.exists, skipPrimerButton.isHittable {
                skipPrimerButton.tap()
                continue
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

    private func dismissIntegrationPrimersIfNeeded(app: XCUIApplication) {
        let skipPrimerButton = app.buttons["onboarding.accessPrimer.skipButton"]
        let timeout = Date().addingTimeInterval(10)

        while Date() < timeout {
            guard skipPrimerButton.exists, skipPrimerButton.isHittable else {
                return
            }
            skipPrimerButton.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
    }

    private func rootViewReached(app: XCUIApplication, timeout: TimeInterval = 0) -> Bool {
        let addButton = app.buttons["root.inlineAddButton"]
        let tabBar = app.tabBars.firstMatch
        guard timeout > 0 else {
            return addButton.exists || tabBar.exists
        }
        return addButton.waitForExistence(timeout: timeout) || tabBar.waitForExistence(timeout: timeout)
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

    private func completeTask(app: XCUIApplication, title: String) {
        let row = app.descendants(matching: .any)["taskRow.\(title)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Task row was not visible before completion")

        let checkbox = app.buttons["taskRow.complete.\(title)"].firstMatch
        if checkbox.waitForExistence(timeout: 1), checkbox.isHittable {
            checkbox.tap()
        } else {
            let checkboxCoordinate = row.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.32))
            checkboxCoordinate.tap()
        }

        if waitForCondition(timeout: 2, pollInterval: 0.1, predicate: { !row.exists }) {
            return
        }

        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
        let end = row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
        start.press(forDuration: 0.01, thenDragTo: end)

        let completeButton = app.buttons["Complete"].firstMatch
        if completeButton.waitForExistence(timeout: 2), completeButton.isHittable {
            completeButton.tap()
        }
    }

    private func openSettings(app: XCUIApplication) {
        let settingsButton = app.buttons["root.settingsButton"]
        if !settingsButton.exists {
            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Compact tab bar not visible")

            let tabButtons = tabBar.buttons.allElementsBoundByIndex
            XCTAssertFalse(tabButtons.isEmpty, "Compact tab bar had no buttons")

            for tabButton in tabButtons {
                tabButton.tap()
                if settingsButton.waitForExistence(timeout: 1) {
                    break
                }
            }
        }

        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings button not visible in compact navigation")
        settingsButton.tap()
    }

    private func submitInlineTask(from app: XCUIApplication) {
        let keyboardCommitButton = app.buttons["inlineTask.keyboardCommitButton"].firstMatch
        if keyboardCommitButton.waitForExistence(timeout: 1), keyboardCommitButton.isHittable {
            keyboardCommitButton.tap()
            return
        }
        let submitButton = app.buttons["inlineTask.submitButton"].firstMatch
        if submitButton.waitForExistence(timeout: 1), submitButton.isHittable {
            submitButton.tap()
            return
        }
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

    private func browseTabButton(in app: XCUIApplication, timeout: TimeInterval = 0) -> XCUIElement {
        let identifiedTab = app.buttons["root.tab.browse"].firstMatch
        if timeout > 0, identifiedTab.waitForExistence(timeout: timeout) {
            return identifiedTab
        }
        if identifiedTab.exists {
            return identifiedTab
        }

        let glyphTabBarButton = app.tabBars.buttons["▦ Browse"].firstMatch
        if timeout > 0, glyphTabBarButton.waitForExistence(timeout: min(2, timeout)) {
            return glyphTabBarButton
        }
        if glyphTabBarButton.exists {
            return glyphTabBarButton
        }

        let tabBarButton = app.tabBars.buttons["Browse"].firstMatch
        if timeout > 0, tabBarButton.waitForExistence(timeout: min(2, timeout)) {
            return tabBarButton
        }
        if tabBarButton.exists {
            return tabBarButton
        }

        let genericButton = app.buttons["Browse"].firstMatch
        if genericButton.exists {
            return genericButton
        }
        if timeout > 0 {
            _ = genericButton.waitForExistence(timeout: min(2, timeout))
            if genericButton.exists {
                return genericButton
            }
        }

        let indexedTab = app.tabBars.buttons.element(boundBy: 3)
        if timeout > 0 {
            _ = indexedTab.waitForExistence(timeout: min(2, timeout))
        }
        return indexedTab
    }

    private func inboxTabButton(in app: XCUIApplication, timeout: TimeInterval = 0) -> XCUIElement {
        let identifiedTab = app.buttons["root.tab.builtIn-inbox"].firstMatch
        if timeout > 0, identifiedTab.waitForExistence(timeout: timeout) {
            return identifiedTab
        }
        if identifiedTab.exists {
            return identifiedTab
        }

        let tabBarButton = app.tabBars.buttons["Inbox"].firstMatch
        if timeout > 0, tabBarButton.waitForExistence(timeout: min(2, timeout)) {
            return tabBarButton
        }
        if tabBarButton.exists {
            return tabBarButton
        }

        let genericButton = app.buttons["Inbox"].firstMatch
        if genericButton.exists {
            return genericButton
        }
        if timeout > 0 {
            _ = genericButton.waitForExistence(timeout: min(2, timeout))
            if genericButton.exists {
                return genericButton
            }
        }

        let indexedTab = app.tabBars.buttons.element(boundBy: 0)
        if timeout > 0 {
            _ = indexedTab.waitForExistence(timeout: min(2, timeout))
        }
        return indexedTab
    }

    private func reveal(element: XCUIElement, in app: XCUIApplication, maxScrolls: Int = 6) -> Bool {
        if element.waitForExistence(timeout: 1) {
            return true
        }

        let scrollContainer = app.tables.firstMatch.exists ? app.tables.firstMatch : app
        for _ in 0 ..< maxScrolls {
            scrollContainer.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            if element.exists {
                return true
            }
        }

        return element.waitForExistence(timeout: 1)
    }

    private func makeStorageOverridePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TodoMDUITests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .path
    }

    private func seedMarkdownTask(rootPath: String, title: String) throws {
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let taskURL = rootURL.appendingPathComponent("20260310-0000-search-smoke.md")
        let content = """
        ---
        title: "\(title)"
        status: todo
        priority: none
        flagged: false
        created: "2026-03-10T00:00:00.000Z"
        source: ui-test
        ---

        """
        try content.write(to: taskURL, atomically: true, encoding: .utf8)
    }

    private func waitForFileContents(
        at url: URL,
        containing needle: String,
        timeout: TimeInterval = 10,
        pollInterval: TimeInterval = 0.2
    )
        -> Bool
    {
        waitForCondition(timeout: timeout, pollInterval: pollInterval) {
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8)
            else {
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
    )
        -> Bool
    {
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
                      let content = String(data: data, encoding: .utf8)
                else {
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
    )
        -> Bool
    {
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
