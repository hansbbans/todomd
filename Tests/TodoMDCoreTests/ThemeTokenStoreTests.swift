import XCTest
@testable import TodoMDCore

final class ThemeTokenStoreTests: XCTestCase {
    func testClassicPresetTokenValues() {
        let tokens = ThemeTokenStore().loadPreset(.classic)
        XCTAssertEqual(tokens.colors.backgroundPrimaryLight, "#F2F2F7")
        XCTAssertEqual(tokens.colors.surfaceLight, "#FFFFFF")
        XCTAssertEqual(tokens.colors.accentLight, "#4A7FD4")
        XCTAssertEqual(tokens.colors.separatorLight, "#E5E5EA")
        XCTAssertEqual(tokens.spacing.rowVertical, 14)
        XCTAssertEqual(tokens.motion.completionSpringResponse, 0.28)
    }
}
