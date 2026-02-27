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
}
