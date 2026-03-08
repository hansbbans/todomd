import XCTest
@testable import TodoMDCore

final class CompactTabSettingsTests: XCTestCase {
    func testNormalizedCustomViewsFallsBackToDefaultsForInvalidValues() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: "",
            trailingRawValue: "not-a-view",
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .upcoming)
        XCTAssertEqual(normalized.secondary, .logbook)
    }

    func testNormalizedCustomViewsAvoidsDuplicateSelections() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: BuiltInView.logbook.rawValue,
            trailingRawValue: BuiltInView.logbook.rawValue,
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .logbook)
        XCTAssertEqual(normalized.secondary, .upcoming)
    }

    func testNormalizedCustomViewsDropsPomodoroWhenDisabled() {
        let normalized = CompactTabSettings.normalizedCustomViews(
            leadingRawValue: BuiltInView.pomodoro.rawValue,
            trailingRawValue: BuiltInView.anytime.rawValue,
            pomodoroEnabled: false
        )

        XCTAssertEqual(normalized.primary, .upcoming)
        XCTAssertEqual(normalized.secondary, .anytime)
    }
}
