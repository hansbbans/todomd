import XCTest
@testable import TodoMDCore

final class CompactTabSettingsTests: XCTestCase {
    func testNormalizedCustomViewsFallsBackToDefaultsForInvalidValues() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: "",
            trailingRawValue: "not-a-view",
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .builtIn(.upcoming))
        XCTAssertEqual(normalized.secondary, .builtIn(.logbook))
    }

    func testNormalizedCustomViewsAvoidsDuplicateSelections() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: BuiltInView.logbook.rawValue,
            trailingRawValue: BuiltInView.logbook.rawValue,
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .builtIn(.logbook))
        XCTAssertEqual(normalized.secondary, .builtIn(.upcoming))
    }

    func testNormalizedCustomViewsDropsPomodoroWhenDisabled() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: BuiltInView.pomodoro.rawValue,
            trailingRawValue: BuiltInView.anytime.rawValue,
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .builtIn(.upcoming))
        XCTAssertEqual(normalized.secondary, .builtIn(.anytime))
    }

    func testAvailableCustomViewsIncludesCustomPerspectives() {
        let perspectiveView = ViewIdentifier.custom("perspective:focus")

        let views = CompactTabSettings.availableCustomViews(
            pomodoroEnabled: false,
            additionalViews: [perspectiveView]
        )

        XCTAssertTrue(views.contains(perspectiveView))
    }

    func testAvailableCustomViewsIncludesProjects() {
        let projectView = ViewIdentifier.project("Work")

        let views = CompactTabSettings.availableCustomViews(
            pomodoroEnabled: false,
            additionalViews: [projectView]
        )

        XCTAssertTrue(views.contains(projectView))
    }

    func testNormalizedCustomViewsKeepsCustomPerspectiveSelections() {
        let firstPerspective = ViewIdentifier.custom("perspective:focus")
        let secondPerspective = ViewIdentifier.custom("perspective:deep-work")

        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: firstPerspective.rawValue,
            trailingRawValue: secondPerspective.rawValue,
            pomodoroEnabled: false,
            additionalViews: [firstPerspective, secondPerspective]
        )

        XCTAssertEqual(normalized.primary, firstPerspective)
        XCTAssertEqual(normalized.secondary, secondPerspective)
    }

    func testNormalizedCustomViewsAvoidsDuplicateCustomPerspectives() {
        let firstPerspective = ViewIdentifier.custom("perspective:focus")
        let secondPerspective = ViewIdentifier.custom("perspective:deep-work")

        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: firstPerspective.rawValue,
            trailingRawValue: firstPerspective.rawValue,
            pomodoroEnabled: false,
            additionalViews: [firstPerspective, secondPerspective]
        )

        XCTAssertEqual(normalized.primary, firstPerspective)
        XCTAssertEqual(normalized.secondary, .builtIn(.logbook))
    }

    func testNormalizedCustomViewsKeepsProjectSelections() {
        let projectView = ViewIdentifier.project("Work")

        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: projectView.rawValue,
            trailingRawValue: BuiltInView.logbook.rawValue,
            pomodoroEnabled: false,
            additionalViews: [projectView]
        )

        XCTAssertEqual(normalized.primary, projectView)
        XCTAssertEqual(normalized.secondary, .builtIn(.logbook))
    }

    func testDefaultPerspectiveDisplayNameTruncatesLongNames() {
        let displayName = CompactTabSettings.defaultPerspectiveDisplayName("This perspective name is too long")

        XCTAssertEqual(displayName, "This persp")
    }

    func testNormalizedPerspectiveDisplayNameUsesTrimmedUserInputWhenPresent() {
        let displayName = CompactTabSettings.normalizedPerspectiveDisplayName(
            "  Deep Work  ",
            perspectiveName: "Long Perspective Name"
        )

        XCTAssertEqual(displayName, "Deep Work")
    }

    func testNormalizedPerspectiveDisplayNameFallsBackToPerspectiveNameWhenEmpty() {
        let displayName = CompactTabSettings.normalizedPerspectiveDisplayName(
            "   ",
            perspectiveName: "Long Perspective Name"
        )

        XCTAssertEqual(displayName, "Long Persp")
    }
}
