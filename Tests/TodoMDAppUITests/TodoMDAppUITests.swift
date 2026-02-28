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

        let quickAddButton = app.buttons["root.quickAddButton"].firstMatch
        XCTAssertTrue(quickAddButton.waitForExistence(timeout: 10))
        quickAddButton.tap()

        let quickEntryForm = app.descendants(matching: .any)["quickEntry.form"]
        XCTAssertTrue(quickEntryForm.waitForExistence(timeout: 10))

        let identifiedTextField = quickEntryForm.descendants(matching: .textField)["quickEntry.titleField"]
        let identifiedTextView = quickEntryForm.descendants(matching: .textView)["quickEntry.titleField"]
        let fallbackTextField = quickEntryForm.descendants(matching: .textField).firstMatch
        let fallbackTextView = quickEntryForm.descendants(matching: .textView).firstMatch

        let titleInput: XCUIElement
        if identifiedTextField.exists {
            titleInput = identifiedTextField
        } else if identifiedTextView.exists {
            titleInput = identifiedTextView
        } else if fallbackTextField.exists {
            titleInput = fallbackTextField
        } else {
            titleInput = fallbackTextView
        }

        XCTAssertTrue(titleInput.waitForExistence(timeout: 10))
        titleInput.tap()
        titleInput.typeText("test")

        let addButton = app.buttons["quickEntry.addButton"]
        XCTAssertTrue(addButton.isEnabled)
        addButton.tap()

        XCTAssertFalse(quickEntryForm.waitForExistence(timeout: 2), "Quick Entry sheet did not dismiss")
        let createdTaskRow = app.descendants(matching: .any)["taskRow.test"]
        XCTAssertTrue(createdTaskRow.waitForExistence(timeout: 10), "Created task was not visible")

        quickAddButton.tap()
        XCTAssertTrue(quickEntryForm.waitForExistence(timeout: 5), "App became unresponsive after adding task")

        let cancelButton = app.buttons["quickEntry.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5))
        cancelButton.tap()
    }

    func testRemindersImportEndToEndWithFakeSource() {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-ui-testing-reset", "-ui-testing-force-onboarding"]
        app.launchEnvironment["TODOMD_STORAGE_OVERRIDE_PATH"] = "Library/Caches/TodoMDUITests/\(UUID().uuidString)"
        app.launchEnvironment["TODOMD_FAKE_REMINDERS_IMPORT"] = "1"
        app.launch()

        completeOnboarding(app: app)

        let settingsButton = app.buttons["root.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10))
        settingsButton.tap()

        let remindersImportSection = app.buttons["settings.section.remindersImport"]
        XCTAssertTrue(remindersImportSection.waitForExistence(timeout: 10), "Reminders Import section not visible")
        remindersImportSection.tap()

        let importButton = app.descendants(matching: .any)["settings.remindersImport.importButton"]
        var scrollAttempts = 0
        while !importButton.exists && scrollAttempts < 6 {
            app.swipeUp()
            scrollAttempts += 1
        }
        XCTAssertTrue(importButton.waitForExistence(timeout: 10), "Reminders import button not visible")

        let refreshButton = app.descendants(matching: .any)["settings.remindersImport.refreshListsButton"]
        if refreshButton.exists {
            refreshButton.tap()
        }

        XCTAssertTrue(importButton.isHittable)
        importButton.tap()

        let status = app.staticTexts["settings.remindersImport.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10), "Import status did not appear")
        XCTAssertTrue(status.label.contains("Imported 1 reminder"))

        for _ in 0..<2 {
            let backButton = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(backButton.waitForExistence(timeout: 10))
            backButton.tap()
        }

        let importedTaskRow = app.descendants(matching: .any)["taskRow.from reminders e2e"]
        XCTAssertTrue(importedTaskRow.waitForExistence(timeout: 10), "Imported reminder task row not found")
    }

    private func completeOnboarding(app: XCUIApplication) {
        let nextButton = app.buttons["onboarding.nextButton"]
        let useDefaultButton = app.buttons["onboarding.useDefaultButton"]
        let getStartedButton = app.buttons["onboarding.getStartedButton"]
        let settingsButton = app.buttons["root.settingsButton"]

        let timeout = Date().addingTimeInterval(25)
        while Date() < timeout {
            if settingsButton.exists {
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

        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "App did not reach root view")
    }
}
